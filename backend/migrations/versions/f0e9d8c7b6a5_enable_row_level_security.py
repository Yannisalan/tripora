"""enable row level security (defense-in-depth ownership)

Revision ID: f0e9d8c7b6a5
Revises: a5b6c7d8e9f0
Create Date: 2026-08-30 00:00:00.000000

Every app query for user-owned rows already filters by the JWT user id at the
application layer (ORM ``filter_by`` / ``db.session.get``). This migration adds
PostgreSQL Row-Level Security as defense-in-depth so the database itself also
enforces ownership.

The authenticated user id is made available to the database on each connection
as the custom GUC ``request.jwt.claims.sub`` (set by the app in ``app.py`` for
authenticated requests, e.g. ``SET LOCAL request.jwt.claims.sub TO '42'``).
Policies below read that value and only allow rows whose ``user_id``/``id``
matches.

Notes:
- ``trips`` and ``subscriptions`` are only ever touched through authenticated
  routes, so they are FORCEd on (the owning role is subject to RLS too).
- ``users`` is read/inserted by unauthenticated flows (register, login,
  verify-email, resend) before a JWT/sub exists, so it is enabled WITHOUT
  FORCE. The per-user policy protects ``users`` against any non-owner role,
  while the owning app role keeps its normal access (its own-row access is
  already enforced in the application layer).
- ``current_setting(..., true)`` returns NULL when the GUC is unset, and any
  comparison with NULL is false, so RLS fails closed for unauthenticated
  connections.
"""
from alembic import op


# revision identifiers, used by Alembic.
revision = 'f0e9d8c7b6a5'
down_revision = 'a5b6c7d8e9f0'
branch_labels = None
depends_on = None


_RLS_SUB = "current_setting('request.jwt.claims.sub', true)::integer"


def upgrade():
    # ---------------------------------------------------------------
    # TRIPS  (force)
    # ---------------------------------------------------------------
    op.execute("ALTER TABLE trips ENABLE ROW LEVEL SECURITY")
    op.execute("ALTER TABLE trips FORCE ROW LEVEL SECURITY")

    op.execute(
        "CREATE POLICY trips_select_owner ON trips "
        "FOR SELECT USING (user_id = %s)" % _RLS_SUB
    )
    op.execute(
        "CREATE POLICY trips_insert_owner ON trips "
        "FOR INSERT WITH CHECK (user_id = %s)" % _RLS_SUB
    )
    op.execute(
        "CREATE POLICY trips_update_owner ON trips "
        "FOR UPDATE USING (user_id = %s) "
        "WITH CHECK (user_id = %s)" % (_RLS_SUB, _RLS_SUB)
    )
    op.execute(
        "CREATE POLICY trips_delete_owner ON trips "
        "FOR DELETE USING (user_id = %s)" % _RLS_SUB
    )

    # ---------------------------------------------------------------
    # SUBSCRIPTIONS  (force)
    # ---------------------------------------------------------------
    op.execute("ALTER TABLE subscriptions ENABLE ROW LEVEL SECURITY")
    op.execute("ALTER TABLE subscriptions FORCE ROW LEVEL SECURITY")

    op.execute(
        "CREATE POLICY subscriptions_select_owner ON subscriptions "
        "FOR SELECT USING (user_id = %s)" % _RLS_SUB
    )
    op.execute(
        "CREATE POLICY subscriptions_insert_owner ON subscriptions "
        "FOR INSERT WITH CHECK (user_id = %s)" % _RLS_SUB
    )
    op.execute(
        "CREATE POLICY subscriptions_update_owner ON subscriptions "
        "FOR UPDATE USING (user_id = %s) "
        "WITH CHECK (user_id = %s)" % (_RLS_SUB, _RLS_SUB)
    )
    op.execute(
        "CREATE POLICY subscriptions_delete_owner ON subscriptions "
        "FOR DELETE USING (user_id = %s)" % _RLS_SUB
    )

    # ---------------------------------------------------------------
    # USERS  (enabled, not forced)
    # ---------------------------------------------------------------
    op.execute("ALTER TABLE users ENABLE ROW LEVEL SECURITY")
    # NOTE: intentionally NOT FORCE — leave the table owner/unauth flows
    # (register, login, verify, resend) untouched.

    op.execute(
        "CREATE POLICY users_select_owner ON users "
        "FOR SELECT USING (id = %s)" % _RLS_SUB
    )
    op.execute(
        "CREATE POLICY users_update_owner ON users "
        "FOR UPDATE USING (id = %s) "
        "WITH CHECK (id = %s)" % (_RLS_SUB, _RLS_SUB)
    )


def downgrade():
    op.execute("DROP POLICY IF EXISTS users_update_owner ON users")
    op.execute("DROP POLICY IF EXISTS users_select_owner ON users")
    op.execute("ALTER TABLE users DISABLE ROW LEVEL SECURITY")

    op.execute("DROP POLICY IF EXISTS subscriptions_delete_owner ON subscriptions")
    op.execute("DROP POLICY IF EXISTS subscriptions_update_owner ON subscriptions")
    op.execute("DROP POLICY IF EXISTS subscriptions_insert_owner ON subscriptions")
    op.execute("DROP POLICY IF EXISTS subscriptions_select_owner ON subscriptions")
    op.execute("ALTER TABLE subscriptions DISABLE ROW LEVEL SECURITY")

    op.execute("DROP POLICY IF EXISTS trips_delete_owner ON trips")
    op.execute("DROP POLICY IF EXISTS trips_update_owner ON trips")
    op.execute("DROP POLICY IF EXISTS trips_insert_owner ON trips")
    op.execute("DROP POLICY IF EXISTS trips_select_owner ON trips")
    op.execute("ALTER TABLE trips DISABLE ROW LEVEL SECURITY")
