"""F7 log retention on real PostgreSQL (opt-in, integration).

Needs the DISPOSABLE local database from SECURITY_TESTING_GUIDE.md §1b,
migrated to head and prepared with backend/db/roles.sql:

    TRIPORA_PG_RUNTIME_URL=postgresql+psycopg://tripora_runtime:...@127.0.0.1:55432/tripora_security_test
    TRIPORA_PG_OWNER_URL=postgresql+psycopg://tripora_owner:...@127.0.0.1:55432/tripora_security_test

Proves:
- the least-privilege runtime role cannot purge: RLS makes its activity-log
  DELETE affect zero rows and it has no DELETE grant on admin_audit_log; both
  are detected and the whole transaction rolls back;
- the owner (BYPASSRLS, as neondb_owner on Neon) purges only expired rows,
  records the purge in admin_audit_log, and a repeated run is a no-op;
- a failure part-way through rolls back the deletions already made.

Rows are tagged with a per-test marker so assertions ignore other data.
"""

import os
import uuid
from datetime import datetime, timedelta, timezone

import pytest
from sqlalchemy import create_engine, text

from services import log_retention
from services.log_retention import (
    PURGE_AUDIT_ACTION,
    RetentionError,
    purge_expired_logs,
)

from .test_postgres_runtime_role import RUNTIME_URL, _assert_disposable

OWNER_URL = os.getenv("TRIPORA_PG_OWNER_URL", "")

pytestmark = [
    pytest.mark.integration,
    pytest.mark.skipif(not (RUNTIME_URL and OWNER_URL),
                       reason="TRIPORA_PG_RUNTIME_URL / TRIPORA_PG_OWNER_URL not set"),
]


def _now_naive():
    return datetime.now(timezone.utc).replace(tzinfo=None)


@pytest.fixture(scope="module")
def owner_engine():
    _assert_disposable(OWNER_URL)
    eng = create_engine(OWNER_URL)
    yield eng
    eng.dispose()


@pytest.fixture
def seeded(owner_engine):
    """Expired and recent rows in both tables, inserted as the owner."""
    marker = "/f7-test-{}".format(uuid.uuid4().hex[:10])
    now = _now_naive()
    activity = [(now - timedelta(days=d)) for d in (91, 200, 1, 89)]
    audit = [(now - timedelta(days=d)) for d in (366, 700, 10, 364)]
    with owner_engine.begin() as conn:
        for created in activity:
            conn.execute(text(
                "INSERT INTO activity_logs (event_type, path, ip_address, created_at)"
                " VALUES ('api_request', :p, '203.0.113.9', :c)"), {"p": marker, "c": created})
        for created in audit:
            conn.execute(text(
                "INSERT INTO admin_audit_log (action, path, created_at)"
                " VALUES ('access', :p, :c)"), {"p": marker, "c": created})
    yield marker
    with owner_engine.begin() as conn:
        conn.execute(text("DELETE FROM activity_logs WHERE path = :p"), {"p": marker})
        conn.execute(text("DELETE FROM admin_audit_log WHERE path = :p"), {"p": marker})


def _marked(owner_engine, marker):
    with owner_engine.connect() as conn:
        return (
            conn.execute(text("SELECT count(*) FROM activity_logs WHERE path = :p"),
                         {"p": marker}).scalar(),
            conn.execute(text("SELECT count(*) FROM admin_audit_log WHERE path = :p"),
                         {"p": marker}).scalar(),
        )


def _make_app(monkeypatch, url):
    import config.settings as settings_mod
    from app import create_app

    monkeypatch.setattr(settings_mod.Config, "SQLALCHEMY_DATABASE_URI", url)
    monkeypatch.setattr(settings_mod.Config, "SQLALCHEMY_ENGINE_OPTIONS",
                        {"pool_pre_ping": True, "pool_size": 2, "max_overflow": 0})
    application = create_app()
    application.config.update(TESTING=True)
    return application


@pytest.fixture
def runtime_app(monkeypatch):
    _assert_disposable(RUNTIME_URL)
    from config.database import db
    application = _make_app(monkeypatch, RUNTIME_URL)
    with application.app_context():
        assert db.session.execute(text("SELECT current_user")).scalar() == "tripora_runtime"
        db.session.rollback()
        yield application
        db.session.remove()
        db.engine.dispose()


@pytest.fixture
def owner_app(monkeypatch):
    _assert_disposable(OWNER_URL)
    from config.database import db
    application = _make_app(monkeypatch, OWNER_URL)
    with application.app_context():
        yield application
        db.session.remove()
        db.engine.dispose()


def _purge_record_count(owner_engine):
    with owner_engine.connect() as conn:
        return conn.execute(text(
            "SELECT count(*) FROM admin_audit_log WHERE action = :a"),
            {"a": PURGE_AUDIT_ACTION}).scalar()


# ----------------------------------------------------------------------
# Runtime role: refused, nothing changes
# ----------------------------------------------------------------------

def test_runtime_dry_run_sees_counts(runtime_app, seeded, owner_engine):
    report = purge_expired_logs()
    assert report.tables[0].eligible >= 2
    assert report.tables[1].eligible >= 2
    assert _marked(owner_engine, seeded) == (4, 4)


def test_runtime_activity_delete_is_blocked_by_rls(runtime_app, seeded,
                                                   owner_engine):
    before = _purge_record_count(owner_engine)
    with pytest.raises(RetentionError) as info:
        purge_expired_logs(execute=True)
    assert "activity_logs" in str(info.value)
    assert "could not be deleted" in str(info.value)
    assert _marked(owner_engine, seeded) == (4, 4)
    assert _purge_record_count(owner_engine) == before


def test_runtime_has_no_delete_grant_on_audit_log(runtime_app, seeded,
                                                  owner_engine):
    # Make activity_logs have nothing eligible so the audit DELETE runs.
    with pytest.raises(RetentionError) as info:
        purge_expired_logs(execute=True, activity_days=100000)
    assert "rolled back" in str(info.value)
    cause = info.value.__cause__
    assert getattr(getattr(cause, "orig", None), "sqlstate", None) == "42501"  # insufficient_privilege
    assert _marked(owner_engine, seeded) == (4, 4)


def test_runtime_cli_exits_non_zero(runtime_app, seeded, owner_engine):
    result = runtime_app.test_cli_runner().invoke(
        args=["logs", "purge", "--execute"])
    assert result.exit_code == 1
    assert "203.0.113.9" not in result.output and seeded not in result.output
    assert _marked(owner_engine, seeded) == (4, 4)


# ----------------------------------------------------------------------
# Owner role: purges correctly and atomically
# ----------------------------------------------------------------------

def test_owner_failure_midway_rolls_back(owner_app, seeded, owner_engine,
                                         monkeypatch):
    real_delete = log_retention._delete_expired

    def failing(table, cutoff, batch_size):
        if table.name == "admin_audit_log":
            raise RuntimeError("simulated")
        return real_delete(table, cutoff, batch_size)

    monkeypatch.setattr(log_retention, "_delete_expired", failing)
    before = _purge_record_count(owner_engine)
    with pytest.raises(RetentionError):
        purge_expired_logs(execute=True)
    assert _marked(owner_engine, seeded) == (4, 4)
    assert _purge_record_count(owner_engine) == before


def test_owner_purge_deletes_only_expired_and_is_repeatable(owner_app, seeded,
                                                            owner_engine):
    before = _purge_record_count(owner_engine)
    result = owner_app.test_cli_runner().invoke(
        args=["logs", "purge", "--execute", "--batch-size", "1"])
    assert result.exit_code == 0, result.output
    # 91/200-day activity and 366/700-day audit rows gone; recent rows kept.
    assert _marked(owner_engine, seeded) == (2, 2)
    assert _purge_record_count(owner_engine) == before + 1

    again = purge_expired_logs(execute=True)
    assert again.total_deleted == 0
    assert _marked(owner_engine, seeded) == (2, 2)
