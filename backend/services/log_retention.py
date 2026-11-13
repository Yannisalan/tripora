"""Retention for ``activity_logs`` and ``admin_audit_log`` (finding F7).

Policy (SECURITY_HARDENING_REPORT.md P5.3 / P12):

- ``activity_logs``    keep 90 days   (IP addresses, paths, user ids)
- ``admin_audit_log``  keep 365 days  (administrator authentication/access trail)

A row is expired when its ``created_at`` is strictly before the cutoff
``now_utc - retention``. Both columns are written with ``datetime.utcnow()``
(naive UTC), so the cutoff is computed from a timezone-aware UTC instant and
then made naive for the comparison. Rows whose ``created_at`` is NULL never
match ``created_at < cutoff`` and are therefore always kept (and reported).

Safety properties:

- Read-only unless ``execute=True`` (the CLI default is a dry run).
- One database transaction for the whole run. Deletions in both tables and the
  audit record of the purge itself commit together, or not at all.
- Deletes in id-ordered batches (``DELETE ... WHERE id IN (SELECT id ...
  LIMIT n)``); no row is ever loaded into Python.
- After deleting, the eligible rows are recounted. If any are left (for example
  because Row-Level Security or missing privileges made a DELETE affect zero
  rows), the run fails and rolls back instead of silently reporting success.
- Retention can only be lengthened, never shortened below the policy.
- Output and logs contain counts, retention periods and cutoffs only, never
  record contents.

Nothing here schedules itself: the purge runs only when an operator invokes
``flask --app wsgi logs purge --execute``.
"""

import logging
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone

from sqlalchemy import delete, func, select

from config.database import db
from models.activity_log import ActivityLog
from models.admin_security import AdminAuditLog
from services import db_context

logger = logging.getLogger(__name__)

ACTIVITY_LOG_RETENTION_DAYS = 90
ADMIN_AUDIT_RETENTION_DAYS = 365

DEFAULT_BATCH_SIZE = 1000
MAX_BATCH_SIZE = 10000

PURGE_AUDIT_ACTION = "log_retention_purge"


class RetentionError(RuntimeError):
    """The purge could not complete; the transaction was rolled back.

    Messages carry table names and counts only.
    """


@dataclass
class TableReport:
    table: str
    retention_days: int
    cutoff: datetime          # naive UTC
    eligible: int = 0         # rows with created_at < cutoff, before deletion
    null_timestamps: int = 0  # rows with created_at IS NULL (always kept)
    deleted: int = None       # None in a dry run


@dataclass
class PurgeReport:
    executed: bool
    reference_time: datetime  # naive UTC
    tables: list = field(default_factory=list)

    @property
    def total_eligible(self):
        return sum(t.eligible for t in self.tables)

    @property
    def total_deleted(self):
        return sum(t.deleted or 0 for t in self.tables)


def utc_now():
    return datetime.now(timezone.utc)


def _naive_utc(moment):
    """Convert an aware datetime to naive UTC; reject naive input."""
    if moment.tzinfo is None or moment.tzinfo.utcoffset(moment) is None:
        raise ValueError("The reference time must be timezone-aware.")
    return moment.astimezone(timezone.utc).replace(tzinfo=None)


def utc_cutoff(retention_days, now=None):
    """Naive-UTC cutoff: rows strictly older than this are expired."""
    reference = _naive_utc(now if now is not None else utc_now())
    return reference - timedelta(days=int(retention_days))


def _validate(activity_days, audit_days, batch_size):
    if int(activity_days) < ACTIVITY_LOG_RETENTION_DAYS:
        raise ValueError(
            "activity_logs retention cannot be shorter than "
            "{} days.".format(ACTIVITY_LOG_RETENTION_DAYS)
        )
    if int(audit_days) < ADMIN_AUDIT_RETENTION_DAYS:
        raise ValueError(
            "admin_audit_log retention cannot be shorter than "
            "{} days.".format(ADMIN_AUDIT_RETENTION_DAYS)
        )
    if not 1 <= int(batch_size) <= MAX_BATCH_SIZE:
        raise ValueError(
            "batch size must be between 1 and {}.".format(MAX_BATCH_SIZE)
        )


def _count(table, condition):
    return int(db.session.execute(
        select(func.count()).select_from(table).where(condition)
    ).scalar() or 0)


def _delete_expired(table, cutoff, batch_size):
    """Delete rows with created_at < cutoff in id-ordered batches."""
    deleted = 0
    while True:
        batch_ids = (
            select(table.c.id)
            .where(table.c.created_at < cutoff)
            .order_by(table.c.id)
            .limit(batch_size)
            .scalar_subquery()
        )
        result = db.session.execute(
            delete(table).where(table.c.id.in_(batch_ids))
        )
        affected = result.rowcount or 0
        if affected <= 0:
            return deleted
        deleted += affected


def purge_expired_logs(
    *,
    execute=False,
    now=None,
    activity_days=ACTIVITY_LOG_RETENTION_DAYS,
    audit_days=ADMIN_AUDIT_RETENTION_DAYS,
    batch_size=DEFAULT_BATCH_SIZE,
):
    """Report (and with ``execute=True`` delete) expired log rows.

    Must be called inside an application context. Returns a ``PurgeReport``.
    Raises ``ValueError`` for invalid arguments (nothing touched) and
    ``RetentionError`` when an executed purge fails (everything rolled back).
    """
    _validate(activity_days, audit_days, batch_size)

    # Whole seconds, so the cutoffs printed, applied and audited are identical.
    reference = _naive_utc(
        now if now is not None else utc_now()).replace(microsecond=0)
    targets = (
        (ActivityLog.__table__, int(activity_days)),
        (AdminAuditLog.__table__, int(audit_days)),
    )
    report = PurgeReport(executed=bool(execute), reference_time=reference)

    # Operator context: admin_read lets the counts see every row under RLS;
    # auth_flow lets the purge append its own audit record.
    with db_context.scoped(auth_flow=True, admin_read=True):
        try:
            # Start from a clean transaction so the RLS context and the
            # all-or-nothing guarantee cover every statement below.
            db.session.rollback()

            for table, days in targets:
                cutoff = reference - timedelta(days=days)
                report.tables.append(TableReport(
                    table=table.name,
                    retention_days=days,
                    cutoff=cutoff,
                    eligible=_count(table, table.c.created_at < cutoff),
                    null_timestamps=_count(table, table.c.created_at.is_(None)),
                ))

            if not execute:
                db.session.rollback()
                return report

            for (table, _days), entry in zip(targets, report.tables):
                entry.deleted = _delete_expired(table, entry.cutoff, batch_size)
                remaining = _count(table, table.c.created_at < entry.cutoff)
                if remaining:
                    raise RetentionError(
                        "{}: {} expired row(s) could not be deleted "
                        "(insufficient privileges or row-level security?)."
                        .format(table.name, remaining)
                    )

            # The purge is itself an audited administrative action, committed
            # atomically with the deletions. Counts and cutoffs only.
            db.session.add(AdminAuditLog(
                admin_user_id=None,
                action=PURGE_AUDIT_ACTION,
                detail={
                    "referenceTimeUtc": reference.isoformat() + "Z",
                    "tables": {
                        t.table: {
                            "retentionDays": t.retention_days,
                            "cutoffUtc": t.cutoff.isoformat() + "Z",
                            "eligible": t.eligible,
                            "deleted": t.deleted,
                        }
                        for t in report.tables
                    },
                },
            ))
            db.session.commit()
        except Exception as error:
            db.session.rollback()
            if isinstance(error, RetentionError):
                raise
            # Type only: DB exception text can include SQL; bind values are
            # hidden by the engine (hide_parameters), but keep logs minimal.
            logger.error(
                "Log retention purge failed (%s); rolled back.",
                type(error).__name__,
            )
            raise RetentionError(
                "Log retention purge failed ({}); the transaction was "
                "rolled back and no rows were deleted.".format(
                    type(error).__name__)
            ) from error

    logger.info(
        "Log retention purge committed: %s",
        ", ".join(
            "{} deleted={} eligible={}".format(t.table, t.deleted, t.eligible)
            for t in report.tables
        ),
    )
    return report
