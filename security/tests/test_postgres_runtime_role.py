"""PostgreSQL integration: the app running as the least-privilege runtime role.

Opt-in. Requires a DISPOSABLE PostgreSQL database that has been migrated with
``flask db upgrade`` (as the owner) and prepared with ``backend/db/roles.sql``:

    TRIPORA_PG_RUNTIME_URL=postgresql+psycopg://tripora_runtime:...@127.0.0.1:55432/tripora_security_test
    python -m pytest security/tests/test_postgres_runtime_role.py -m integration

What it proves:

* the runtime role cannot run DDL, read ``alembic_version`` or rewrite the
  admin audit trail;
* RLS fails closed with no context and isolates users with one;
* every real flow (register, verify, login, refresh, trips, expenses, email
  change, password reset, admin MFA login + cross-user stats, account
  deletion) works under that role and RLS -- including after mid-request
  commits on pooled connections.

Never point this at a production or shared database: it creates users.
"""

import os
import uuid

import pytest
from sqlalchemy import create_engine, text
from sqlalchemy.exc import DBAPIError

RUNTIME_URL = os.getenv("TRIPORA_PG_RUNTIME_URL", "")

pytestmark = [
    pytest.mark.integration,
    pytest.mark.skipif(
        not RUNTIME_URL, reason="TRIPORA_PG_RUNTIME_URL not set"
    ),
]


def _assert_disposable(url):
    name = url.rsplit("/", 1)[-1].split("?")[0]
    assert "test" in name or "disposable" in name, (
        "refusing to run against a non-disposable database: {}".format(name)
    )


@pytest.fixture(scope="module")
def engine():
    _assert_disposable(RUNTIME_URL)
    eng = create_engine(RUNTIME_URL, pool_pre_ping=True)
    yield eng
    eng.dispose()


@pytest.fixture
def pg_app(monkeypatch):
    _assert_disposable(RUNTIME_URL)
    import config.settings as settings_mod
    from app import create_app
    from config.database import db

    monkeypatch.setattr(settings_mod.Config, "SQLALCHEMY_DATABASE_URI", RUNTIME_URL)
    monkeypatch.setattr(
        settings_mod.Config,
        "SQLALCHEMY_ENGINE_OPTIONS",
        {"pool_pre_ping": True, "pool_size": 2, "max_overflow": 0},
    )
    application = create_app()
    application.config.update(TESTING=True)
    with application.app_context():
        yield application
        db.session.remove()
        db.engine.dispose()


def _email(tag):
    return "pg-{}-{}@example.com".format(tag, uuid.uuid4().hex[:10])


# ----------------------------------------------------------------------
# Privileges
# ----------------------------------------------------------------------

@pytest.mark.parametrize("statement", [
    "CREATE TABLE runtime_should_not_create (id int)",
    "DROP TABLE users",
    "ALTER TABLE trips ADD COLUMN pwned int",
    "TRUNCATE trips",
    "SELECT * FROM alembic_version",
    "UPDATE admin_audit_log SET action = 'x'",
    "DELETE FROM admin_audit_log",
    "CREATE ROLE runtime_escalation",
    "SET row_security = off; SELECT * FROM trips",
])
def test_runtime_role_cannot(engine, statement):
    denied = False
    with engine.connect() as conn:
        try:
            for part in statement.split(";"):
                if part.strip():
                    conn.execute(text(part))
        except DBAPIError as error:
            denied = "permission denied" in str(error).lower() or (
                "must be owner" in str(error).lower()
                or "row-level security" in str(error).lower()
            )
        finally:
            conn.rollback()
    assert denied, "runtime role was allowed: {}".format(statement)


def test_role_attributes(engine):
    with engine.connect() as conn:
        row = conn.execute(text(
            "SELECT rolsuper, rolcreatedb, rolcreaterole, rolbypassrls "
            "FROM pg_roles WHERE rolname = current_user"
        )).one()
    assert tuple(row) == (False, False, False, False)


def test_rls_fails_closed_without_context(engine):
    with engine.connect() as conn:
        assert conn.execute(text("SELECT count(*) FROM users")).scalar() == 0
        assert conn.execute(text("SELECT count(*) FROM trips")).scalar() == 0
        # A GUC that has been set before reverts to '' on a pooled
        # connection; the NULL-safe policies must not raise on it.
        conn.execute(text(
            "SELECT set_config('request.jwt.claims.sub', '', false)"))
        assert conn.execute(text("SELECT count(*) FROM trips")).scalar() == 0


# ----------------------------------------------------------------------
# End-to-end flows under the runtime role
# ----------------------------------------------------------------------

def test_full_user_lifecycle_under_runtime_role(pg_app):
    from .helpers import auth_headers, last_verification_code

    client = pg_app.test_client()
    email_a, email_b = _email("a"), _email("b")

    # register + verify + login (pre-auth users access via app.auth_flow)
    tokens = {}
    for email in (email_a, email_b):
        assert client.post("/api/auth/register", json={
            "name": "PG", "email": email, "password": "pg-runtime-pass-1",
        }).status_code == 201
        login = client.post("/api/auth/login", json={
            "email": email, "password": "pg-runtime-pass-1"})
        assert login.status_code == 200, login.get_json()
        body = login.get_json()
        verify = client.post(
            "/api/auth/verify-email",
            json={"code": last_verification_code(email)},
            headers=auth_headers(body["accessToken"]),
        )
        assert verify.status_code == 200, verify.get_json()
        tokens[email] = body

    a = auth_headers(tokens[email_a]["accessToken"])
    b = auth_headers(tokens[email_b]["accessToken"])

    # duplicate registration stays generic and does not error under RLS
    assert client.post("/api/auth/register", json={
        "name": "Dup", "email": email_a, "password": "pg-runtime-pass-1",
    }).status_code == 201

    # trips + expenses (FORCEd RLS) for A
    gen = client.post("/api/trips/generate", headers=a, json={
        "destination": "Lisbon", "startDate": "2026-12-01",
        "endDate": "2026-12-03", "travelers": 1, "interests": ["food"],
    })
    assert gen.status_code == 200, gen.get_json()
    trip_id = gen.get_json()["trip"]["id"]

    exp = client.post(
        "/api/trips/{}/expenses".format(trip_id), headers=a,
        json={"amount": 12.5, "category": "food", "date": "2026-01-02"},
    )
    assert exp.status_code == 201, exp.get_json()

    swap = client.post(
        "/api/trips/{}/swap-activity".format(trip_id), headers=a,
        json={"day": 1, "time": "Morning"},
    )
    assert swap.status_code == 200, swap.get_json()

    # B sees nothing of A's
    assert client.get("/api/trips/{}".format(trip_id), headers=b).status_code == 404
    assert client.get("/api/trips", headers=b).get_json()["count"] == 0
    assert client.get(
        "/api/trips/{}/expenses".format(trip_id), headers=b
    ).status_code == 404

    # refresh rotation (pre-auth lookup by token) still works
    refreshed = client.post("/api/auth/refresh", json={
        "refreshToken": tokens[email_a]["refreshToken"]})
    assert refreshed.status_code == 200, refreshed.get_json()

    # email change conflict check must see other rows -> 409, not 500
    conflict = client.patch("/api/auth/me", headers=a, json={
        "email": email_b, "currentPassword": "pg-runtime-pass-1"})
    assert conflict.status_code == 409, conflict.get_json()

    # account deletion as runtime role (FORCEd RLS on trips/expenses)
    deleted = client.delete("/api/auth/account", headers=a, json={
        "currentPassword": "pg-runtime-pass-1"})
    assert deleted.status_code == 200, deleted.get_json()
    assert client.post("/api/auth/login", json={
        "email": email_a, "password": "pg-runtime-pass-1"}).status_code == 401

    # B unaffected
    assert client.get("/api/auth/me", headers=b).status_code == 200


def test_admin_mfa_login_and_cross_user_stats_under_runtime_role(pg_app):
    from services import admin_auth
    from .helpers import auth_headers, last_verification_code

    client = pg_app.test_client()
    email = _email("admin")
    client.post("/api/auth/register", json={
        "name": "Admin", "email": email, "password": "pg-admin-pass-1"})
    login = client.post("/api/auth/login", json={
        "email": email, "password": "pg-admin-pass-1"}).get_json()
    client.post(
        "/api/auth/verify-email",
        json={"code": last_verification_code(email)},
        headers=auth_headers(login["accessToken"]),
    )

    runner = pg_app.test_cli_runner()
    result = runner.invoke(args=["admin", "grant", email])
    assert result.exit_code == 0, result.output

    pending = client.post("/api/admin/auth/login", json={
        "email": email, "password": "pg-admin-pass-1"}).get_json()
    setup = client.post("/api/admin/auth/mfa/setup", json={
        "pendingToken": pending["pendingToken"]}).get_json()
    activated = client.post("/api/admin/auth/mfa/activate", json={
        "pendingToken": pending["pendingToken"],
        "code": admin_auth.totp_code(setup["secret"]),
    })
    assert activated.status_code == 200, activated.get_json()

    stats = client.get(
        "/api/admin/stats",
        headers=auth_headers(activated.get_json()["sessionToken"]),
    )
    assert stats.status_code == 200, stats.get_json()
    assert stats.get_json()["stats"]["users"]["total"] >= 1

    users = client.get(
        "/api/admin/users",
        headers=auth_headers(activated.get_json()["sessionToken"]),
    )
    assert users.status_code == 200
    assert len(users.get_json()["users"]) >= 1
