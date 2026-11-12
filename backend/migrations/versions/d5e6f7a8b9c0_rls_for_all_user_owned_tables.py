"""row-level security for every user-associated table

Revision ID: d5e6f7a8b9c0
Revises: a9b8c7d6e5f4
Create Date: 2026-11-10 00:00:00.000000

Extends RLS from ``users`` / ``trips`` / ``trip_expenses`` to every table that
holds user-associated rows. Policies are table-specific, derived from how the
application legitimately reaches each table (see SECURITY_HARDENING_REPORT.md
§P3). They read only server-established, transaction-local settings
(``services/db_context.py``):

  sub         = NULLIF(current_setting('request.jwt.claims.sub', true), '')::int
                (verified JWT subject)
  auth_flow   = current_setting('app.auth_flow', true) = 'on'
                (login/register/refresh/reset/admin-login endpoints, admin CLI)
  admin_read  = current_setting('app.admin_read', true) = 'on'
                (after admin authorization)

Notes
-----
* INSERT ... RETURNING requires the new row to pass a SELECT policy too.
  ``activity_logs`` and ``admin_audit_log`` are inserted WITHOUT RETURNING
  (``implicit_returning=False``), so their SELECT policies stay admin-only.
* UPDATE/DELETE with a WHERE clause must also pass the table's SELECT policy.
* Referential actions (ON DELETE CASCADE / SET NULL) run as the table owner
  and are not filtered by RLS: account deletion relies on the cascades for
  admin_mfa / admin_recovery_codes / admin_sessions (no owner SELECT there)
  and on SET NULL for admin_audit_log.
* The owner role (``neondb_owner``) has BYPASSRLS on Neon: none of this
  applies to it. It applies to ``tripora_runtime``.
* Backward compatible for the currently deployed code, which connects as the
  owner (policies are ignored for it).
"""

from alembic import op


revision = "d5e6f7a8b9c0"
down_revision = "a9b8c7d6e5f4"
branch_labels = None
depends_on = None


SUB = "NULLIF(current_setting('request.jwt.claims.sub', true), '')::integer"
AUTH_FLOW = "current_setting('app.auth_flow', true) = 'on'"
ADMIN_READ = "current_setting('app.admin_read', true) = 'on'"

OWNS_TRIP = (
    "EXISTS (SELECT 1 FROM trips t WHERE t.id = {col} AND t.user_id = " + SUB + ")"
)

# (table, policy name, command, USING, WITH CHECK)
POLICIES = [
    # ---- trip_expenses: also require the parent trip to be the caller's --
    ("trip_expenses", "trip_expenses_insert_owner", "INSERT", None,
     "user_id = {sub} AND " + OWNS_TRIP.format(col="trip_id")),
    ("trip_expenses", "trip_expenses_update_owner", "UPDATE",
     "user_id = {sub}",
     "user_id = {sub} AND " + OWNS_TRIP.format(col="trip_id")),

    # ---- weather_cache: keyed by trip id (no user column) -----------------
    ("weather_cache", "weather_cache_owner", "ALL",
     OWNS_TRIP.format(col="weather_cache.trip_id"),
     OWNS_TRIP.format(col="weather_cache.trip_id")),

    # ---- user_refresh_tokens: looked up by token hash before any JWT ------
    ("user_refresh_tokens", "refresh_tokens_select", "SELECT",
     "{auth_flow} OR user_id = {sub}", None),
    ("user_refresh_tokens", "refresh_tokens_insert", "INSERT",
     None, "{auth_flow}"),
    ("user_refresh_tokens", "refresh_tokens_update", "UPDATE",
     "{auth_flow} OR user_id = {sub}", "{auth_flow} OR user_id = {sub}"),
    ("user_refresh_tokens", "refresh_tokens_delete_owner", "DELETE",
     "user_id = {sub}", None),

    # ---- activity_logs: anyone may log their OWN request; admins read -----
    # (models/activity_log.py inserts without RETURNING, so no self-read
    # policy is needed; anonymous rows stay invisible to anonymous callers.)
    # Own rows readable by their (authenticated) owner: required because a
    # DELETE ... WHERE must also pass the SELECT policy (account deletion).
    # `=` (not IS NOT DISTINCT FROM) keeps anonymous rows (user_id NULL)
    # invisible to anonymous callers.
    ("activity_logs", "activity_logs_select", "SELECT",
     "{admin_read} OR user_id = {sub}", None),
    ("activity_logs", "activity_logs_insert_self", "INSERT",
     None, "user_id IS NOT DISTINCT FROM {sub}"),
    ("activity_logs", "activity_logs_delete_owner", "DELETE",
     "user_id = {sub}", None),

    # ---- admin MFA / recovery codes / sessions: admin-auth flows only -----
    ("admin_mfa", "admin_mfa_auth_flow", "ALL", "{auth_flow}", "{auth_flow}"),
    ("admin_mfa", "admin_mfa_delete_owner", "DELETE", "user_id = {sub}", None),
    ("admin_recovery_codes", "admin_recovery_codes_auth_flow", "ALL",
     "{auth_flow}", "{auth_flow}"),
    ("admin_recovery_codes", "admin_recovery_codes_delete_owner", "DELETE",
     "user_id = {sub}", None),
    ("admin_sessions", "admin_sessions_auth_flow", "ALL",
     "{auth_flow}", "{auth_flow}"),
    ("admin_sessions", "admin_sessions_delete_owner", "DELETE",
     "user_id = {sub}", None),

    # ---- admin_audit_log: append from admin paths; no UPDATE/DELETE grant -
    ("admin_audit_log", "admin_audit_log_insert", "INSERT",
     None, "{auth_flow} OR {admin_read}"),
    ("admin_audit_log", "admin_audit_log_select_admin", "SELECT",
     "{admin_read}", None),
]

NEW_RLS_TABLES = [
    "weather_cache",
    "user_refresh_tokens",
    "activity_logs",
    "admin_mfa",
    "admin_recovery_codes",
    "admin_sessions",
    "admin_audit_log",
]

# Previous definitions (a9b8c7d6e5f4) restored on downgrade.
OLD_EXPENSE_POLICIES = [
    ("trip_expenses_insert_owner",
     "FOR INSERT WITH CHECK (user_id = {sub})"),
    ("trip_expenses_update_owner",
     "FOR UPDATE USING (user_id = {sub}) WITH CHECK (user_id = {sub})"),
]


def _fmt(expr):
    return expr.format(sub=SUB, auth_flow=AUTH_FLOW, admin_read=ADMIN_READ)


def _is_postgres():
    return op.get_bind().dialect.name == "postgresql"


def upgrade():
    if not _is_postgres():
        return

    for table in NEW_RLS_TABLES:
        op.execute("ALTER TABLE {} ENABLE ROW LEVEL SECURITY".format(table))
        op.execute("ALTER TABLE {} FORCE ROW LEVEL SECURITY".format(table))

    for table, name, command, using, check in POLICIES:
        op.execute("DROP POLICY IF EXISTS {} ON {}".format(name, table))
        sql = "CREATE POLICY {} ON {} FOR {}".format(name, table, command)
        if using:
            sql += " USING ({})".format(_fmt(using))
        if check:
            sql += " WITH CHECK ({})".format(_fmt(check))
        op.execute(sql)


def downgrade():
    if not _is_postgres():
        return

    for table, name, _command, _using, _check in POLICIES:
        op.execute("DROP POLICY IF EXISTS {} ON {}".format(name, table))

    for name, body in OLD_EXPENSE_POLICIES:
        op.execute("CREATE POLICY {} ON trip_expenses {}".format(
            name, body.format(sub=SUB)))

    for table in NEW_RLS_TABLES:
        op.execute("ALTER TABLE {} NO FORCE ROW LEVEL SECURITY".format(table))
        op.execute("ALTER TABLE {} DISABLE ROW LEVEL SECURITY".format(table))
