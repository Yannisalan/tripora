"""email verification, user roles, admin MFA/sessions/audit, runtime-role RLS

Revision ID: a9b8c7d6e5f4
Revises: e1f2a3b4c5d6
Create Date: 2026-11-10 00:00:00.000000

Backward compatible:

* New ``users`` columns are nullable or have server defaults. Existing rows
  keep ``email_verified`` exactly as stored (existing accounts are NOT forced
  to re-verify) and get ``role = 'user'`` (nobody becomes an admin).
* ``user_refresh_tokens.user_id`` gains ``ON DELETE CASCADE`` (constraint is
  dropped and re-created under the same name).
* New admin tables only.
* RLS: adds policies so a NON-owner runtime role (see
  ``backend/db/roles.sql``) can run the pre-authentication flows and the admin
  views. The owner role is unaffected (``users`` RLS is not FORCEd; ``trips``
  keeps its owner policies). The GUCs are set per transaction by the app
  (``services/db_context.py``), never from client input:

  - ``request.jwt.claims.sub``  verified JWT subject (existing)
  - ``app.auth_flow``           'on' only inside register/login/refresh/reset
                                 and admin-login endpoints and the admin CLI
  - ``app.admin_read``          'on' only after admin authorization
"""

import sqlalchemy as sa
from alembic import op


revision = "a9b8c7d6e5f4"
down_revision = "e1f2a3b4c5d6"
branch_labels = None
depends_on = None


# NULLIF: once a custom GUC has been set on a pooled connection it reverts to
# '' (not NULL) after the transaction, and ''::integer raises. NULLIF maps the
# empty value to NULL so every comparison is simply false (fail closed).
_SUB = "NULLIF(current_setting('request.jwt.claims.sub', true), '')::integer"

# Owner policies from f0e9d8c7b6a5, recreated with the NULL-safe subject.
_OWNER_POLICIES = (
    ("trips_select_owner", "trips",
     "FOR SELECT USING (user_id = {sub})"),
    ("trips_insert_owner", "trips",
     "FOR INSERT WITH CHECK (user_id = {sub})"),
    ("trips_update_owner", "trips",
     "FOR UPDATE USING (user_id = {sub}) WITH CHECK (user_id = {sub})"),
    ("trips_delete_owner", "trips",
     "FOR DELETE USING (user_id = {sub})"),
    ("users_select_owner", "users",
     "FOR SELECT USING (id = {sub})"),
    ("users_update_owner", "users",
     "FOR UPDATE USING (id = {sub}) WITH CHECK (id = {sub})"),
    # trip_expenses (FORCEd RLS, from 3e2d1c0b9a87)
    ("trip_expenses_select_owner", "trip_expenses",
     "FOR SELECT USING (user_id = {sub})"),
    ("trip_expenses_insert_owner", "trip_expenses",
     "FOR INSERT WITH CHECK (user_id = {sub})"),
    ("trip_expenses_update_owner", "trip_expenses",
     "FOR UPDATE USING (user_id = {sub}) WITH CHECK (user_id = {sub})"),
    ("trip_expenses_delete_owner", "trip_expenses",
     "FOR DELETE USING (user_id = {sub})"),
)
_OLD_SUB = "current_setting('request.jwt.claims.sub', true)::integer"
_AUTH_FLOW = "current_setting('app.auth_flow', true) = 'on'"
_ADMIN_READ = "current_setting('app.admin_read', true) = 'on'"


def _is_postgres():
    return op.get_bind().dialect.name == "postgresql"


def upgrade():
    # ------------------------------------------------------------------
    # users: email verification + role
    # ------------------------------------------------------------------
    with op.batch_alter_table("users") as batch:
        batch.add_column(sa.Column(
            "email_verification_code_hash", sa.String(255), nullable=True))
        batch.add_column(sa.Column(
            "email_verification_expires_at", sa.DateTime(), nullable=True))
        batch.add_column(sa.Column(
            "email_verification_attempts", sa.Integer(), nullable=False,
            server_default="0"))
        batch.add_column(sa.Column(
            "email_verification_sent_at", sa.DateTime(), nullable=True))
        batch.add_column(sa.Column(
            "role", sa.String(20), nullable=False, server_default="user"))

    if _is_postgres():
        op.execute(
            "ALTER TABLE users ADD CONSTRAINT ck_users_role "
            "CHECK (role IN ('user', 'admin'))"
        )

        # --------------------------------------------------------------
        # user_refresh_tokens.user_id -> ON DELETE CASCADE
        # --------------------------------------------------------------
        op.execute(
            "ALTER TABLE user_refresh_tokens "
            "DROP CONSTRAINT IF EXISTS user_refresh_tokens_user_id_fkey"
        )
        op.execute(
            "ALTER TABLE user_refresh_tokens "
            "ADD CONSTRAINT user_refresh_tokens_user_id_fkey "
            "FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE"
        )

    # ------------------------------------------------------------------
    # admin tables
    # ------------------------------------------------------------------
    op.create_table(
        "admin_mfa",
        sa.Column("user_id", sa.Integer(), nullable=False),
        sa.Column("secret_encrypted", sa.Text(), nullable=False),
        sa.Column("enabled_at", sa.DateTime(), nullable=True),
        sa.Column("last_used_step", sa.BigInteger(), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(
            ["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("user_id"),
    )

    op.create_table(
        "admin_recovery_codes",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("user_id", sa.Integer(), nullable=False),
        sa.Column("code_hash", sa.String(64), nullable=False),
        sa.Column("used_at", sa.DateTime(), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(
            ["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("code_hash"),
    )
    op.create_index(
        "ix_admin_recovery_codes_user_id",
        "admin_recovery_codes", ["user_id"])

    op.create_table(
        "admin_sessions",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("user_id", sa.Integer(), nullable=False),
        sa.Column("token_hash", sa.String(64), nullable=False),
        sa.Column("state", sa.String(20), nullable=False),
        sa.Column("mfa_attempts", sa.Integer(), nullable=False,
                  server_default="0"),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("expires_at", sa.DateTime(), nullable=False),
        sa.Column("last_seen_at", sa.DateTime(), nullable=True),
        sa.Column("revoked_at", sa.DateTime(), nullable=True),
        sa.Column("token_version", sa.Integer(), nullable=False,
                  server_default="1"),
        sa.Column("ip_address", sa.String(64), nullable=True),
        sa.Column("user_agent", sa.String(255), nullable=True),
        sa.ForeignKeyConstraint(
            ["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("token_hash"),
    )
    op.create_index(
        "ix_admin_sessions_user_id", "admin_sessions", ["user_id"])
    op.create_index(
        "ix_admin_sessions_expires_at", "admin_sessions", ["expires_at"])

    op.create_table(
        "admin_audit_log",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("admin_user_id", sa.Integer(), nullable=True),
        sa.Column("action", sa.String(40), nullable=False),
        sa.Column("method", sa.String(10), nullable=True),
        sa.Column("path", sa.String(255), nullable=True),
        sa.Column("status_code", sa.Integer(), nullable=True),
        sa.Column("ip_address", sa.String(64), nullable=True),
        sa.Column("detail", sa.JSON(), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(
            ["admin_user_id"], ["users.id"], ondelete="SET NULL"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_admin_audit_log_admin_user_id",
        "admin_audit_log", ["admin_user_id"])
    op.create_index(
        "ix_admin_audit_log_action", "admin_audit_log", ["action"])
    op.create_index(
        "ix_admin_audit_log_created_at", "admin_audit_log", ["created_at"])

    if not _is_postgres():
        return

    # ------------------------------------------------------------------
    # RLS: NULL-safe owner policies
    # ------------------------------------------------------------------
    for name, table, body in _OWNER_POLICIES:
        op.execute("DROP POLICY IF EXISTS %s ON %s" % (name, table))
        op.execute("CREATE POLICY %s ON %s %s" % (
            name, table, body.format(sub=_SUB)))

    # ------------------------------------------------------------------
    # RLS policies for a non-owner runtime role
    # ------------------------------------------------------------------
    op.execute(
        "CREATE POLICY users_auth_flow_select ON users FOR SELECT "
        "USING (%s OR %s)" % (_AUTH_FLOW, _ADMIN_READ)
    )
    op.execute(
        "CREATE POLICY users_auth_flow_insert ON users FOR INSERT "
        "WITH CHECK (%s)" % _AUTH_FLOW
    )
    op.execute(
        "CREATE POLICY users_auth_flow_update ON users FOR UPDATE "
        "USING (%s) WITH CHECK (%s)" % (_AUTH_FLOW, _AUTH_FLOW)
    )
    op.execute(
        "CREATE POLICY users_delete_owner ON users FOR DELETE "
        "USING (id = %s)" % _SUB
    )
    op.execute(
        "CREATE POLICY trips_admin_select ON trips FOR SELECT "
        "USING (%s)" % _ADMIN_READ
    )


def downgrade():
    if _is_postgres():
        op.execute("DROP POLICY IF EXISTS trips_admin_select ON trips")
        op.execute("DROP POLICY IF EXISTS users_delete_owner ON users")
        op.execute("DROP POLICY IF EXISTS users_auth_flow_update ON users")
        op.execute("DROP POLICY IF EXISTS users_auth_flow_insert ON users")
        op.execute("DROP POLICY IF EXISTS users_auth_flow_select ON users")
        for name, table, body in _OWNER_POLICIES:
            op.execute("DROP POLICY IF EXISTS %s ON %s" % (name, table))
            op.execute("CREATE POLICY %s ON %s %s" % (
                name, table, body.format(sub=_OLD_SUB)))

    op.drop_index("ix_admin_audit_log_created_at", "admin_audit_log")
    op.drop_index("ix_admin_audit_log_action", "admin_audit_log")
    op.drop_index("ix_admin_audit_log_admin_user_id", "admin_audit_log")
    op.drop_table("admin_audit_log")
    op.drop_index("ix_admin_sessions_expires_at", "admin_sessions")
    op.drop_index("ix_admin_sessions_user_id", "admin_sessions")
    op.drop_table("admin_sessions")
    op.drop_index(
        "ix_admin_recovery_codes_user_id", "admin_recovery_codes")
    op.drop_table("admin_recovery_codes")
    op.drop_table("admin_mfa")

    if _is_postgres():
        op.execute(
            "ALTER TABLE user_refresh_tokens "
            "DROP CONSTRAINT IF EXISTS user_refresh_tokens_user_id_fkey"
        )
        op.execute(
            "ALTER TABLE user_refresh_tokens "
            "ADD CONSTRAINT user_refresh_tokens_user_id_fkey "
            "FOREIGN KEY (user_id) REFERENCES users (id)"
        )
        op.execute("ALTER TABLE users DROP CONSTRAINT IF EXISTS ck_users_role")

    with op.batch_alter_table("users") as batch:
        batch.drop_column("role")
        batch.drop_column("email_verification_sent_at")
        batch.drop_column("email_verification_attempts")
        batch.drop_column("email_verification_expires_at")
        batch.drop_column("email_verification_code_hash")
