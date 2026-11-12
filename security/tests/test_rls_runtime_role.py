"""Row-Level Security proven with the real ``tripora_runtime`` login.

Opt-in (integration). Needs a DISPOSABLE PostgreSQL database migrated to head
by the owner and prepared with ``backend/db/roles.sql`` (see
SECURITY_TESTING_GUIDE.md §1b). Every database statement in this module runs
as ``tripora_runtime`` -- never as the owner -- because the owner bypasses
RLS on Neon and a test run as the owner proves nothing.

Covers: cross-user read / update / delete, unauthorized inserts (including
expenses on someone else's trip and forged activity-log attribution),
anonymous access to every user-associated table, admin reads only with the
admin context, connection-pool identity leakage after commit / rollback /
exception, spoofing the context from API input, the operator CLI as a
background job, and every application feature end to end under RLS.
"""

import uuid
from datetime import date, timedelta

import pytest
from sqlalchemy import create_engine, text
from sqlalchemy.exc import DBAPIError

from .helpers import auth_headers, last_verification_code
from .test_postgres_runtime_role import RUNTIME_URL, _assert_disposable, pg_app  # noqa: F401

pytestmark = [
    pytest.mark.integration,
    pytest.mark.skipif(not RUNTIME_URL, reason="TRIPORA_PG_RUNTIME_URL not set"),
]

USER_TABLES = (
    "users", "trips", "trip_expenses", "weather_cache", "user_refresh_tokens",
    "activity_logs", "admin_mfa", "admin_recovery_codes", "admin_sessions",
    "admin_audit_log",
)


# ----------------------------------------------------------------------
# Raw runtime-role connections
# ----------------------------------------------------------------------

@pytest.fixture(scope="module")
def rt_engine():
    _assert_disposable(RUNTIME_URL)
    # One pooled connection: every transaction reuses the SAME connection,
    # which is exactly what an identity leak would exploit.
    eng = create_engine(RUNTIME_URL, pool_size=1, max_overflow=0)
    with eng.connect() as conn:
        assert conn.execute(text("SELECT current_user")).scalar() == "tripora_runtime"
    yield eng
    eng.dispose()


def ctx(conn, sub=None, auth_flow=False, admin_read=False):
    conn.execute(text(
        "SELECT set_config('request.jwt.claims.sub', :s, true), "
        "set_config('app.auth_flow', :a, true), "
        "set_config('app.admin_read', :r, true)"
    ), {"s": "" if sub is None else str(sub),
        "a": "on" if auth_flow else "off",
        "r": "on" if admin_read else "off"})


def count(conn, table, where="TRUE", **params):
    return conn.execute(text(
        "SELECT count(*) FROM {} WHERE {}".format(table, where)), params).scalar()


# ----------------------------------------------------------------------
# Fixture data, created through the real app (as tripora_runtime)
# ----------------------------------------------------------------------

def _signup(client, tag):
    email = "rls-{}-{}@example.com".format(tag, uuid.uuid4().hex[:8])
    password = "rls-pass-{}-1".format(tag)
    client.post("/api/auth/register", json={"name": tag, "email": email, "password": password})
    body = client.post("/api/auth/login", json={"email": email, "password": password}).get_json()
    assert client.post(
        "/api/auth/verify-email", json={"code": last_verification_code(email)},
        headers=auth_headers(body["accessToken"]),
    ).status_code == 200
    return {"email": email, "password": password, "access": body["accessToken"],
            "refresh": body["refreshToken"], "id": body["user"]["id"]}


@pytest.fixture
def world(pg_app, monkeypatch):
    """Two verified users, each with a trip, an expense, a weather-cache row,
    a refresh token and an attributed activity-log row."""
    import routes.weather as weather

    monkeypatch.setattr(weather, "_geocode_destination",
                        lambda d: (d, "PT", 38.72, -9.14))
    monkeypatch.setattr(weather, "_fetch_forecast", lambda *a, **k: (
        [{"date": (date.today() + timedelta(days=2)).isoformat(),
          "tempMax": 20, "tempMin": 12, "code": 1}], False))

    client = pg_app.test_client()
    users = {}
    start = date.today() + timedelta(days=2)
    for tag in ("a", "b"):
        u = _signup(client, tag)
        h = auth_headers(u["access"])
        trip = client.post("/api/trips/generate", headers=h, json={
            "destination": "Lisbon", "startDate": start.isoformat(),
            "endDate": (start + timedelta(days=2)).isoformat(),
            "travelers": 1, "budget": "moderate", "interests": ["food"],
        })
        assert trip.status_code == 200, trip.get_json()
        u["trip"] = trip.get_json()["trip"]["id"]
        exp = client.post("/api/trips/{}/expenses".format(u["trip"]), headers=h,
                          json={"amount": 9, "category": "food", "date": "2026-01-02"})
        assert exp.status_code == 201, exp.get_json()
        u["expense"] = exp.get_json()["expense"]["id"]
        weather_resp = client.get("/api/trips/{}/weather".format(u["trip"]), headers=h)
        assert weather_resp.status_code == 200, weather_resp.get_json()
        assert client.post("/api/admin/page-view", headers=h,
                           json={"path": "/rls-" + tag}).status_code == 201
        users[tag] = u
    users["client"] = client
    return users


# ======================================================================
# Role and table posture
# ======================================================================

def test_runtime_role_has_no_bypass(rt_engine):
    with rt_engine.connect() as conn:
        row = conn.execute(text(
            "SELECT rolsuper, rolbypassrls, rolcreaterole, rolcreatedb "
            "FROM pg_roles WHERE rolname = current_user")).one()
        member_of = conn.execute(text(
            "SELECT count(*) FROM pg_auth_members m JOIN pg_roles u "
            "ON u.oid = m.member WHERE u.rolname = current_user")).scalar()
    assert tuple(row) == (False, False, False, False)
    assert member_of == 0


def test_every_user_table_has_rls_enabled(rt_engine):
    with rt_engine.connect() as conn:
        rows = dict(conn.execute(text(
            "SELECT relname, relrowsecurity FROM pg_class "
            "WHERE relname = ANY(:t) AND relkind = 'r'"), {"t": list(USER_TABLES)}).all())
    assert set(rows) == set(USER_TABLES)
    assert all(rows.values()), rows


# ======================================================================
# Anonymous / no context
# ======================================================================

def test_anonymous_context_sees_nothing(rt_engine, world):
    with rt_engine.connect() as conn:
        ctx(conn)
        for table in USER_TABLES:
            assert count(conn, table) == 0, table


def test_anonymous_context_cannot_write(rt_engine, world):
    a = world["a"]
    statements = [
        "UPDATE trips SET destination = 'x'",
        "DELETE FROM trip_expenses",
        "UPDATE users SET name = 'x'",
        "DELETE FROM user_refresh_tokens",
        "UPDATE weather_cache SET destination = 'x'",
    ]
    with rt_engine.connect() as conn:
        ctx(conn)
        for sql in statements:
            assert conn.execute(text(sql)).rowcount == 0, sql
        conn.rollback()
    with rt_engine.connect() as conn:
        ctx(conn)
        with pytest.raises(DBAPIError):
            conn.execute(text(
                "INSERT INTO trips (user_id, destination, start_date, end_date, "
                "travelers, created_at) VALUES (:u, 'x', now(), now(), 1, now())"),
                {"u": a["id"]})
        conn.rollback()


# ======================================================================
# Cross-user read / update / delete / insert
# ======================================================================

def test_cross_user_read_is_empty(rt_engine, world):
    a, b = world["a"], world["b"]
    with rt_engine.connect() as conn:
        ctx(conn, sub=b["id"])
        assert count(conn, "users", "id = :i", i=a["id"]) == 0
        assert count(conn, "trips", "id = :i", i=a["trip"]) == 0
        assert count(conn, "trip_expenses", "id = :i", i=a["expense"]) == 0
        assert count(conn, "weather_cache", "trip_id = :i", i=a["trip"]) == 0
        assert count(conn, "user_refresh_tokens", "user_id = :i", i=a["id"]) == 0
        assert count(conn, "activity_logs", "user_id = :i", i=a["id"]) == 0
        # ...while the caller's own rows are visible.
        assert count(conn, "trips", "id = :i", i=b["trip"]) == 1
        assert count(conn, "trip_expenses", "id = :i", i=b["expense"]) == 1
        assert count(conn, "weather_cache", "trip_id = :i", i=b["trip"]) == 1


def test_cross_user_update_and_delete_affect_nothing(rt_engine, world):
    a, b = world["a"], world["b"]
    with rt_engine.connect() as conn:
        ctx(conn, sub=b["id"])
        for sql, params in [
            ("UPDATE trips SET destination = 'pwned' WHERE id = :i", {"i": a["trip"]}),
            ("UPDATE trip_expenses SET amount = 1 WHERE id = :i", {"i": a["expense"]}),
            ("UPDATE users SET name = 'pwned' WHERE id = :i", {"i": a["id"]}),
            ("UPDATE weather_cache SET destination = 'p' WHERE trip_id = :i", {"i": a["trip"]}),
            ("UPDATE user_refresh_tokens SET revoked_at = now() WHERE user_id = :i", {"i": a["id"]}),
            ("DELETE FROM trips WHERE id = :i", {"i": a["trip"]}),
            ("DELETE FROM trip_expenses WHERE id = :i", {"i": a["expense"]}),
            ("DELETE FROM users WHERE id = :i", {"i": a["id"]}),
            ("DELETE FROM user_refresh_tokens WHERE user_id = :i", {"i": a["id"]}),
            ("DELETE FROM activity_logs WHERE user_id = :i", {"i": a["id"]}),
        ]:
            assert conn.execute(text(sql), params).rowcount == 0, sql
        conn.commit()
    with rt_engine.connect() as conn:
        ctx(conn, sub=a["id"])
        assert conn.execute(text("SELECT destination FROM trips WHERE id = :i"),
                            {"i": a["trip"]}).scalar() == "Lisbon"


@pytest.mark.parametrize("label,sql", [
    ("trip for another user",
     "INSERT INTO trips (user_id, destination, start_date, end_date, travelers, created_at) "
     "VALUES (:a, 'x', now(), now(), 1, now())"),
    ("expense on another user's trip under own user_id",
     "INSERT INTO trip_expenses (trip_id, user_id, amount, currency, category, date, "
     "created_at, updated_at) VALUES (:a_trip, :b, 1, 'USD', 'food', now(), now(), now())"),
    ("expense attributed to another user",
     "INSERT INTO trip_expenses (trip_id, user_id, amount, currency, category, date, "
     "created_at, updated_at) VALUES (:b_trip, :a, 1, 'USD', 'food', now(), now(), now())"),
    ("move own expense onto another user's trip",
     "UPDATE trip_expenses SET trip_id = :a_trip WHERE user_id = :b"),
    ("hand own trip to another user",
     "UPDATE trips SET user_id = :a WHERE id = :b_trip"),
    ("activity log in another user's name",
     "INSERT INTO activity_logs (event_type, user_id, created_at) VALUES ('page_view', :a, now())"),
    ("refresh token outside auth flow",
     "INSERT INTO user_refresh_tokens (user_id, token_hash, family_id, created_at, expires_at) "
     "VALUES (:b, md5(random()::text), 'f', now(), now())"),
    ("admin session outside auth flow",
     "INSERT INTO admin_sessions (user_id, token_hash, state, created_at, expires_at) "
     "VALUES (:b, md5(random()::text), 'active', now(), now() + interval '1 hour')"),
    ("admin MFA outside auth flow",
     "INSERT INTO admin_mfa (user_id, secret_encrypted, created_at) VALUES (:b, 'x', now())"),
    ("audit row outside admin paths",
     "INSERT INTO admin_audit_log (action, created_at) VALUES ('forged', now())"),
    ("weather cache for another user's trip",
     "INSERT INTO weather_cache (trip_id, destination, start_date, end_date, data, fetched_at) "
     "VALUES (:a_trip, 'x', now(), now(), '{}', now())"),
])
def test_unauthorized_writes_are_rejected(rt_engine, world, label, sql):
    a, b = world["a"], world["b"]
    with rt_engine.connect() as conn:
        ctx(conn, sub=b["id"])
        try:
            result = conn.execute(text(sql), {
                "a": a["id"], "b": b["id"], "a_trip": a["trip"], "b_trip": b["trip"]})
            rejected = result.rowcount == 0  # UPDATE filtered to nothing
        except DBAPIError as error:
            rejected = "row-level security" in str(error).lower() or \
                "permission denied" in str(error).lower() or \
                "violates" in str(error).lower()
        finally:
            conn.rollback()
    assert rejected, label


# ======================================================================
# Administrative access
# ======================================================================

def test_admin_read_only_with_admin_context(rt_engine, world):
    with rt_engine.connect() as conn:
        ctx(conn, sub=world["b"]["id"])
        assert count(conn, "trips") == 1
        # Own log rows only; never other users' or anonymous rows.
        assert count(conn, "activity_logs",
                     "user_id IS DISTINCT FROM :b", b=world["b"]["id"]) == 0
        ctx(conn, admin_read=True)
        assert count(conn, "trips") >= 2
        assert count(conn, "users") >= 2
        assert count(conn, "activity_logs") >= 2
        # admin_read grants reads only: no writes to other users' rows.
        assert conn.execute(text("UPDATE trips SET destination = 'x'")).rowcount == 0
        conn.rollback()


def test_user_jwt_cannot_obtain_admin_context(world):
    client = world["client"]
    h = auth_headers(world["a"]["access"])
    for path in ("/api/admin/stats", "/api/admin/users", "/api/admin/logs"):
        assert client.get(path, headers=h).status_code == 401, path


# ======================================================================
# Connection-pool identity leakage
# ======================================================================

def test_identity_does_not_survive_commit(rt_engine, world):
    a = world["a"]
    with rt_engine.connect() as conn:
        ctx(conn, sub=a["id"])
        assert count(conn, "trips") == 1
        conn.commit()
        # Same pooled connection, new transaction, no context.
        assert count(conn, "trips") == 0
        assert conn.execute(text(
            "SELECT current_setting('request.jwt.claims.sub', true)")).scalar() in ("", None)


def test_identity_does_not_survive_rollback_or_error(rt_engine, world):
    a = world["a"]
    with rt_engine.connect() as conn:
        ctx(conn, sub=a["id"], admin_read=True)
        with pytest.raises(DBAPIError):
            conn.execute(text("SELECT 1/0"))
        conn.rollback()
        assert count(conn, "trips") == 0
        assert count(conn, "users") == 0
    # Next checkout of the single pooled connection is also clean.
    with rt_engine.connect() as conn:
        assert count(conn, "trips") == 0


def test_app_requests_do_not_leak_identity_between_requests(pg_app, world):
    """A's request followed by an anonymous request on the same app/pool."""
    from config.database import db

    client = world["client"]
    assert client.get("/api/trips", headers=auth_headers(world["a"]["access"])).status_code == 200
    # Next request, no token: the RLS context must be empty again.
    client.get("/api/health")
    with pg_app.app_context():
        assert db.session.execute(text("SELECT count(*) FROM trips")).scalar() == 0
        assert db.session.execute(text(
            "SELECT current_setting('request.jwt.claims.sub', true)")).scalar() in ("", None)
        db.session.rollback()


def test_api_input_cannot_set_the_database_identity(world):
    """Nothing the client sends (body, query, headers, refresh-type token)
    may choose the RLS subject."""
    import jwt as pyjwt
    from config.settings import Config

    client = world["client"]
    a, b = world["a"], world["b"]
    spoof_headers = {
        "X-User-Id": str(a["id"]), "X-Forwarded-User": str(a["id"]),
        "X-Request-Jwt-Claims-Sub": str(a["id"]),
    }
    spoof_headers.update(auth_headers(b["access"]))
    resp = client.get("/api/trips?user_id={}&sub={}".format(a["id"], a["id"]),
                      headers=spoof_headers)
    assert resp.status_code == 200
    assert [t["id"] for t in resp.get_json()["trips"]] == [b["trip"]]

    resp = client.patch("/api/trips/{}".format(a["trip"]), headers=auth_headers(b["access"]),
                        json={"user_id": b["id"], "destination": "x", "startDate": "2027-01-01",
                              "endDate": "2027-01-02", "travelers": 1})
    assert resp.status_code == 404

    forged = pyjwt.encode({"sub": str(a["id"]), "type": "refresh", "fresh": False,
                           "jti": "x", "iat": 0, "nbf": 0, "exp": 9999999999},
                          Config.JWT_SECRET_KEY, algorithm="HS256")
    assert client.get("/api/trips", headers=auth_headers(forged)).status_code in (401, 422)


# ======================================================================
# Background job (operator CLI) contexts
# ======================================================================

def test_cli_uses_explicit_context_and_fails_closed_without_it(pg_app, world):
    from config.database import db
    from models.user import User
    from services import db_context

    runner = pg_app.test_cli_runner()
    listing = runner.invoke(args=["admin", "list"])
    assert listing.exit_code == 0, listing.output

    with pg_app.app_context():
        # Job code that forgets to declare a context sees nothing.
        assert User.query.filter_by(email=world["a"]["email"]).first() is None
        db.session.rollback()
        with db_context.scoped(auth_flow=True):
            assert User.query.filter_by(email=world["a"]["email"]).first() is not None
        # Leaving the scope narrows the open transaction again.
        assert db.session.execute(text("SELECT count(*) FROM users")).scalar() == 0
        db.session.rollback()


# ======================================================================
# Every feature end to end under the runtime role
# ======================================================================

def test_feature_matrix_under_runtime_role(pg_app, world, monkeypatch):
    import routes.auth as auth_routes

    client = world["client"]
    a = world["a"]
    h = auth_headers(a["access"])
    results = {}

    results["trip update"] = client.patch("/api/trips/{}".format(a["trip"]), headers=h, json={
        "destination": "Porto", "startDate": (date.today() + timedelta(days=2)).isoformat(),
        "endDate": (date.today() + timedelta(days=3)).isoformat(), "travelers": 2,
    }).status_code
    results["regenerate (AI)"] = client.post(
        "/api/trips/{}/regenerate".format(a["trip"]), headers=h).status_code
    results["swap activity (AI)"] = client.post(
        "/api/trips/{}/swap-activity".format(a["trip"]), headers=h,
        json={"day": 1, "time": "Morning"}).status_code
    results["expense update"] = client.patch(
        "/api/expenses/{}".format(a["expense"]), headers=h, json={"amount": 11}).status_code
    results["expense list"] = client.get(
        "/api/trips/{}/expenses".format(a["trip"]), headers=h).status_code
    results["anonymous page view"] = client.post(
        "/api/admin/page-view", json={"path": "/anon"}).status_code
    results["refresh rotation"] = client.post(
        "/api/auth/refresh", json={"refreshToken": a["refresh"]}).status_code
    results["refresh replay rejected"] = client.post(
        "/api/auth/refresh", json={"refreshToken": a["refresh"]}).status_code
    fresh = client.post("/api/auth/login", json={
        "email": a["email"], "password": a["password"]}).get_json()
    results["logout"] = client.post(
        "/api/auth/logout", json={"refreshToken": fresh["refreshToken"]}).status_code
    results["logged-out token refresh"] = client.post(
        "/api/auth/refresh", json={"refreshToken": fresh["refreshToken"]}).status_code

    sent = {}
    monkeypatch.setattr(auth_routes, "send_password_reset_code",
                        lambda to, code: sent.setdefault("code", code) or True)
    results["forgot password"] = client.post(
        "/api/auth/forgot-password", json={"email": a["email"]}).status_code
    token = client.post("/api/auth/forgot-password/verify", json={
        "email": a["email"], "code": sent["code"]}).get_json().get("resetToken")
    results["reset password"] = client.post("/api/auth/reset-password", json={
        "resetToken": token, "password": "rls-new-pass-77"}).status_code
    relog = client.post("/api/auth/login", json={
        "email": a["email"], "password": "rls-new-pass-77"}).get_json()
    h2 = auth_headers(relog["accessToken"])
    results["password change"] = client.patch("/api/auth/me", headers=h2, json={
        "password": "rls-newer-pass-88", "currentPassword": "rls-new-pass-77"}).status_code
    relog = client.post("/api/auth/login", json={
        "email": a["email"], "password": "rls-newer-pass-88"}).get_json()
    h3 = auth_headers(relog["accessToken"])
    results["expense delete"] = client.delete(
        "/api/expenses/{}".format(a["expense"]), headers=h3).status_code
    results["trip delete"] = client.delete(
        "/api/trips/{}".format(a["trip"]), headers=h3).status_code
    results["account delete"] = client.delete("/api/auth/account", headers=h3, json={
        "currentPassword": "rls-newer-pass-88"}).status_code

    assert results == {
        "trip update": 200, "regenerate (AI)": 200, "swap activity (AI)": 200,
        "expense update": 200, "expense list": 200, "anonymous page view": 201,
        "refresh rotation": 200, "refresh replay rejected": 401, "logout": 200,
        "logged-out token refresh": 401, "forgot password": 200,
        "reset password": 200, "password change": 200, "expense delete": 200,
        "trip delete": 200, "account delete": 200,
    }, results
