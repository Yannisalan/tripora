"""F7 - Log retention purge for activity_logs (90 days) and admin_audit_log
(365 days).

Runs against the isolated in-memory SQLite test database only. Real
PostgreSQL behaviour under the least-privilege runtime role (RLS, missing
DELETE grant) is covered by the opt-in test_log_retention_postgres.py.
"""

from datetime import datetime, timedelta, timezone

import pytest
from sqlalchemy import func, select, text

from config.database import db
from models.activity_log import ActivityLog
from models.admin_security import AdminAuditLog
from services import log_retention
from services.log_retention import (
    ACTIVITY_LOG_RETENTION_DAYS,
    ADMIN_AUDIT_RETENTION_DAYS,
    PURGE_AUDIT_ACTION,
    RetentionError,
    purge_expired_logs,
    utc_cutoff,
)

NOW = datetime(2026, 11, 13, 12, 0, 0, tzinfo=timezone.utc)
NOW_NAIVE = NOW.replace(tzinfo=None)

# Planted in every row so tests can prove contents never reach output.
SENSITIVE_IP = "203.0.113.77"
SENSITIVE_PATH = "/api/private/secret-path"


def _activity(created_at, **kw):
    row = ActivityLog(
        event_type="api_request", path=SENSITIVE_PATH, method="GET",
        status_code=200, ip_address=SENSITIVE_IP, created_at=created_at, **kw)
    db.session.add(row)
    return row


def _audit(created_at, action="access"):
    row = AdminAuditLog(action=action, path=SENSITIVE_PATH,
                        ip_address=SENSITIVE_IP, created_at=created_at)
    db.session.add(row)
    return row


def _ago(days, **extra):
    return NOW_NAIVE - timedelta(days=days, **extra)


def _count(model, *conditions):
    stmt = select(func.count()).select_from(model)
    for c in conditions:
        stmt = stmt.where(c)
    return db.session.execute(stmt).scalar()


def _non_purge_audit_count():
    return _count(AdminAuditLog, AdminAuditLog.action != PURGE_AUDIT_ACTION)


def _purge_records():
    return AdminAuditLog.query.filter_by(action=PURGE_AUDIT_ACTION).all()


@pytest.fixture
def mixed_rows(app):
    """Old and recent rows in both tables (committed)."""
    for days in (91, 120, 400):
        _activity(_ago(days))
    for days in (0, 1, 89):
        _activity(_ago(days))
    for days in (366, 500):
        _audit(_ago(days))
    for days in (0, 100, 364):
        _audit(_ago(days))
    db.session.commit()


# ----------------------------------------------------------------------
# Cutoffs, UTC and boundaries
# ----------------------------------------------------------------------

class TestCutoffs:

    def test_policy_values(self):
        assert ACTIVITY_LOG_RETENTION_DAYS == 90
        assert ADMIN_AUDIT_RETENTION_DAYS == 365

    def test_cutoff_is_naive_utc(self):
        cutoff = utc_cutoff(90, now=NOW)
        assert cutoff == datetime(2026, 8, 15, 12, 0, 0)
        assert cutoff.tzinfo is None

    def test_non_utc_reference_is_converted(self):
        plus5 = timezone(timedelta(hours=5))
        minus8 = timezone(timedelta(hours=-8))
        same_instant_plus5 = NOW.astimezone(plus5)
        same_instant_minus8 = NOW.astimezone(minus8)
        assert utc_cutoff(90, now=same_instant_plus5) == utc_cutoff(90, now=NOW)
        assert utc_cutoff(365, now=same_instant_minus8) == utc_cutoff(365, now=NOW)

    def test_naive_reference_is_rejected(self):
        with pytest.raises(ValueError):
            utc_cutoff(90, now=NOW_NAIVE)
        with pytest.raises(ValueError):
            purge_expired_logs(now=NOW_NAIVE)

    def test_default_reference_time_is_current_utc(self, app):
        before = datetime.now(timezone.utc).replace(tzinfo=None, microsecond=0)
        report = purge_expired_logs()
        after = datetime.now(timezone.utc).replace(tzinfo=None)
        assert before <= report.reference_time <= after
        # Whole seconds: the printed cutoff is exactly the applied cutoff.
        assert report.reference_time.microsecond == 0
        assert all(t.cutoff.microsecond == 0 for t in report.tables)

    def test_boundary_is_strictly_before_cutoff(self, app):
        activity_cutoff = utc_cutoff(90, now=NOW)
        audit_cutoff = utc_cutoff(365, now=NOW)
        one_us = timedelta(microseconds=1)
        _activity(activity_cutoff)
        _activity(activity_cutoff - one_us)
        _audit(audit_cutoff)
        _audit(audit_cutoff - one_us)
        db.session.commit()

        report = purge_expired_logs(execute=True, now=NOW)

        assert [t.deleted for t in report.tables] == [1, 1]
        # (Compared by timestamp: SQLite may reuse a deleted rowid for the
        # purge's own audit record.)
        assert [r.created_at for r in ActivityLog.query.all()] == [activity_cutoff]
        assert [r.created_at for r in AdminAuditLog.query.filter(
            AdminAuditLog.action != PURGE_AUDIT_ACTION)] == [audit_cutoff]


# ----------------------------------------------------------------------
# Eligibility and preservation
# ----------------------------------------------------------------------

class TestRetentionRules:

    def test_dry_run_counts_without_deleting(self, mixed_rows):
        report = purge_expired_logs(now=NOW)

        assert report.executed is False
        activity, audit = report.tables
        assert (activity.table, activity.eligible, activity.deleted) == (
            "activity_logs", 3, None)
        assert (audit.table, audit.eligible, audit.deleted) == (
            "admin_audit_log", 2, None)
        # Nothing deleted, and no purge audit record for a dry run.
        assert _count(ActivityLog) == 6
        assert _count(AdminAuditLog) == 5
        assert _purge_records() == []

    def test_default_is_dry_run(self, mixed_rows):
        report = purge_expired_logs(now=NOW)
        assert report.executed is False
        assert _count(ActivityLog) == 6

    def test_execute_deletes_only_expired_rows(self, mixed_rows):
        report = purge_expired_logs(execute=True, now=NOW)

        assert [t.deleted for t in report.tables] == [3, 2]
        assert report.total_deleted == 5
        # Recent rows survive (0, 1, 89 days / 0, 100, 364 days).
        remaining_activity = sorted(
            (NOW_NAIVE - r.created_at).days for r in ActivityLog.query.all())
        assert remaining_activity == [0, 1, 89]
        remaining_audit = sorted(
            (NOW_NAIVE - r.created_at).days
            for r in AdminAuditLog.query.filter(
                AdminAuditLog.action != PURGE_AUDIT_ACTION))
        assert remaining_audit == [0, 100, 364]

    def test_audit_rows_use_their_own_longer_policy(self, app):
        # 100-200 day-old audit rows are past the ACTIVITY window but must
        # stay: admin_audit_log keeps a full year.
        for days in (100, 200, 300):
            _audit(_ago(days))
        db.session.commit()
        report = purge_expired_logs(execute=True, now=NOW)
        assert report.tables[1].deleted == 0
        assert _non_purge_audit_count() == 3

    def test_purge_is_recorded_in_audit_log_without_contents(self, mixed_rows):
        purge_expired_logs(execute=True, now=NOW)

        records = _purge_records()
        assert len(records) == 1
        detail = records[0].detail
        assert detail["tables"]["activity_logs"]["deleted"] == 3
        assert detail["tables"]["admin_audit_log"]["deleted"] == 2
        assert detail["tables"]["activity_logs"]["retentionDays"] == 90
        assert detail["tables"]["admin_audit_log"]["cutoffUtc"].endswith("Z")
        flat = repr(detail)
        assert SENSITIVE_IP not in flat and SENSITIVE_PATH not in flat
        # The new record is recent, so it is never itself purge-eligible.
        assert records[0].created_at > utc_cutoff(365, now=NOW)

    def test_repeated_execution_is_safe(self, mixed_rows):
        first = purge_expired_logs(execute=True, now=NOW)
        second = purge_expired_logs(execute=True, now=NOW)

        assert first.total_deleted == 5
        assert second.total_eligible == 0
        assert second.total_deleted == 0
        assert _count(ActivityLog) == 3
        assert _non_purge_audit_count() == 3
        assert len(_purge_records()) == 2

    def test_empty_tables(self, app):
        dry = purge_expired_logs(now=NOW)
        run = purge_expired_logs(execute=True, now=NOW)
        assert [t.eligible for t in dry.tables] == [0, 0]
        assert [t.deleted for t in run.tables] == [0, 0]
        assert _count(ActivityLog) == 0

    def test_large_dataset_is_deleted_in_batches(self, app, monkeypatch):
        db.session.execute(
            ActivityLog.__table__.insert(),
            [{"event_type": "api_request", "ip_address": SENSITIVE_IP,
              "created_at": _ago(200)} for _ in range(2500)]
            + [{"event_type": "api_request", "ip_address": None,
                "created_at": _ago(1)} for _ in range(10)],
        )
        db.session.commit()

        statements = []
        real_execute = db.session.execute

        def counting_execute(stmt, *a, **k):
            if getattr(stmt, "is_delete", False):
                statements.append(stmt)
            return real_execute(stmt, *a, **k)

        monkeypatch.setattr(db.session, "execute", counting_execute)
        report = purge_expired_logs(execute=True, now=NOW, batch_size=1000)

        assert report.tables[0].deleted == 2500
        # 3 activity batches (1000, 1000, 500) + 1 empty check, and the audit
        # table's single empty check: rows are never loaded into Python.
        assert len(statements) == 5
        assert _count(ActivityLog) == 10


# ----------------------------------------------------------------------
# NULL timestamps (schema drift safety)
# ----------------------------------------------------------------------

class TestNullTimestamps:

    def test_null_created_at_rows_are_reported_and_kept(self, app):
        # The model declares created_at NOT NULL. Simulate a drifted/legacy
        # table that allows NULL to prove the purge never deletes such rows.
        db.session.execute(text("DROP TABLE activity_logs"))
        db.session.execute(text(
            "CREATE TABLE activity_logs ("
            " id INTEGER PRIMARY KEY, event_type VARCHAR(30) NOT NULL,"
            " path VARCHAR(255), method VARCHAR(10), status_code INTEGER,"
            " user_id INTEGER, detail JSON, ip_address VARCHAR(64),"
            " created_at DATETIME)"
        ))
        db.session.execute(text(
            "INSERT INTO activity_logs (event_type, created_at) VALUES "
            "('api_request', NULL), ('api_request', NULL), "
            "('api_request', :old), ('api_request', :new)"
        ), {"old": _ago(200), "new": _ago(1)})
        db.session.commit()

        dry = purge_expired_logs(now=NOW)
        assert dry.tables[0].eligible == 1
        assert dry.tables[0].null_timestamps == 2

        run = purge_expired_logs(execute=True, now=NOW)
        assert run.tables[0].deleted == 1
        remaining = db.session.execute(text(
            "SELECT count(*) FROM activity_logs WHERE created_at IS NULL"
        )).scalar()
        assert remaining == 2
        assert db.session.execute(
            text("SELECT count(*) FROM activity_logs")).scalar() == 3


# ----------------------------------------------------------------------
# Transactions and failure handling
# ----------------------------------------------------------------------

class TestTransactions:

    def test_failure_in_second_table_rolls_back_first(self, mixed_rows,
                                                      monkeypatch):
        real_delete = log_retention._delete_expired

        def failing_delete(table, cutoff, batch_size):
            if table.name == "admin_audit_log":
                raise RuntimeError("simulated failure " + SENSITIVE_IP)
            return real_delete(table, cutoff, batch_size)

        monkeypatch.setattr(log_retention, "_delete_expired", failing_delete)

        with pytest.raises(RetentionError) as info:
            purge_expired_logs(execute=True, now=NOW)

        assert "rolled back" in str(info.value)
        assert SENSITIVE_IP not in str(info.value)
        # activity_logs deletions (already executed) were rolled back.
        assert _count(ActivityLog) == 6
        assert _count(AdminAuditLog) == 5
        assert _purge_records() == []

    def test_silent_zero_delete_is_detected(self, mixed_rows, monkeypatch):
        # Under RLS a DELETE can match rows yet affect none. The purge must
        # fail rather than report success.
        monkeypatch.setattr(log_retention, "_delete_expired",
                            lambda table, cutoff, batch_size: 0)

        with pytest.raises(RetentionError) as info:
            purge_expired_logs(execute=True, now=NOW)

        assert "activity_logs: 3 expired row(s) could not be deleted" in str(
            info.value)
        assert _count(ActivityLog) == 6
        assert _purge_records() == []

    def test_failure_while_recording_purge_rolls_back(self, mixed_rows,
                                                      monkeypatch):
        real_add = db.session.add

        def failing_add(obj, *a, **k):
            if isinstance(obj, AdminAuditLog) and obj.action == PURGE_AUDIT_ACTION:
                raise RuntimeError("audit write failed")
            return real_add(obj, *a, **k)

        monkeypatch.setattr(db.session, "add", failing_add)
        with pytest.raises(RetentionError):
            purge_expired_logs(execute=True, now=NOW)
        monkeypatch.undo()

        # A purge never commits without its own audit record.
        assert _count(ActivityLog) == 6
        assert _count(AdminAuditLog) == 5

    @pytest.mark.parametrize("kwargs", [
        {"activity_days": 89},
        {"activity_days": 1},
        {"audit_days": 364},
        {"audit_days": 90},
        {"batch_size": 0},
        {"batch_size": 10001},
    ])
    def test_invalid_arguments_touch_nothing(self, mixed_rows, kwargs):
        with pytest.raises(ValueError):
            purge_expired_logs(execute=True, now=NOW, **kwargs)
        assert _count(ActivityLog) == 6
        assert _count(AdminAuditLog) == 5

    def test_longer_retention_is_allowed(self, mixed_rows):
        report = purge_expired_logs(execute=True, now=NOW,
                                    activity_days=180, audit_days=450)
        # 91/120 kept now; only 400 (activity) and 500 (audit) go.
        assert [t.deleted for t in report.tables] == [1, 1]


# ----------------------------------------------------------------------
# CLI: explicit authorization and safe output
# ----------------------------------------------------------------------

def _real_now_rows():
    real_now = datetime.now(timezone.utc).replace(tzinfo=None)
    _activity(real_now - timedelta(days=200))
    _activity(real_now - timedelta(days=1))
    _audit(real_now - timedelta(days=400))
    _audit(real_now - timedelta(days=10))
    db.session.commit()


class TestCli:

    def _run(self, app, *args):
        return app.test_cli_runner().invoke(args=["logs", "purge", *args])

    def test_without_flag_is_a_dry_run(self, app):
        _real_now_rows()
        result = self._run(app)

        assert result.exit_code == 0, result.output
        out = result.output
        assert "DRY RUN" in out
        assert "activity_logs: retention 90 days, cutoff " in out
        assert "admin_audit_log: retention 365 days, cutoff " in out
        assert "Reference time (UTC): " in out and out.count("Z") >= 3
        assert "eligible: 1" in out
        assert "Dry run complete: 2 row(s) would be deleted" in out
        assert "deleted:" not in out
        assert _count(ActivityLog) == 2
        assert _count(AdminAuditLog) == 2
        # Record contents never printed.
        assert SENSITIVE_IP not in out and SENSITIVE_PATH not in out

    def test_execute_flag_deletes(self, app):
        _real_now_rows()
        result = self._run(app, "--execute")

        assert result.exit_code == 0, result.output
        assert "EXECUTE" in result.output
        assert "deleted: 1" in result.output
        assert "Committed: 2 row(s) deleted" in result.output
        assert _count(ActivityLog) == 1
        assert _non_purge_audit_count() == 1
        assert len(_purge_records()) == 1
        assert SENSITIVE_IP not in result.output

    @pytest.mark.parametrize("args", [
        ("--activity-days", "30"),
        ("--audit-days", "90"),
        ("--batch-size", "0"),
        ("--execute", "--activity-days", "1"),
        ("--force",),
        ("-y",),
        ("--execute", "yes"),
        ("--dry-run=false",),
    ])
    def test_unsafe_or_unknown_arguments_are_rejected(self, app, args):
        _real_now_rows()
        result = self._run(app, *args)
        assert result.exit_code != 0
        assert _count(ActivityLog) == 2
        assert _count(AdminAuditLog) == 2

    def test_failure_exits_non_zero_and_keeps_rows(self, app, monkeypatch):
        _real_now_rows()

        def boom(table, cutoff, batch_size):
            raise RuntimeError("db exploded " + SENSITIVE_PATH)

        monkeypatch.setattr(log_retention, "_delete_expired", boom)
        result = self._run(app, "--execute")

        assert result.exit_code == 1
        assert "rolled back" in result.output
        assert SENSITIVE_PATH not in result.output
        assert _count(ActivityLog) == 2

    def test_help_documents_the_flag(self, app):
        result = self._run(app, "--help")
        assert result.exit_code == 0
        flat = " ".join(result.output.split())
        assert "--execute" in flat
        assert "Without it nothing is deleted" in flat
