"""expenses, password reset, and numeric trip budget

Revision ID: 3e2d1c0b9a87
Revises: b2c3d4e5f6a7
Create Date: 2026-09-13 00:00:00.000000

Supported features added by this migration:

- ``users``: password-reset columns (hashed one-time code + hashed one-time
  token + attempt counter). All four expiry/fields are cleared after a
  successful reset, so nothing is ever stored in plaintext.
- ``trips``: ``budget_amount`` numeric budget backing the Smart Trip Expense
  Tracker. ``trips.budget`` remains the categorical label for existing API
  clients.
- ``trip_expenses``: per-expense records (amount, currency, category, date,
  payment method) owned by a user and attached to a trip. Protected by RLS
  (``FORCE``) exactly like ``trip_documents``.

Ownership is enforced at the application layer (every route filters by the
JWT user id) AND at the database layer with Row-Level Security, mirroring the
``trips`` / ``trip_documents`` pattern.
"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = '3e2d1c0b9a87'
down_revision = 'b2c3d4e5f6a7'
branch_labels = None
depends_on = None


_RLS_SUB = "current_setting('request.jwt.claims.sub', true)::integer"


def upgrade():
    # ---------------------------------------------------------------
    # USERS — password reset columns
    # ---------------------------------------------------------------
    op.add_column(
        'users',
        sa.Column('reset_code_hash', sa.String(length=255), nullable=True),
    )
    op.add_column(
        'users',
        sa.Column('reset_code_expires_at', sa.DateTime(), nullable=True),
    )
    op.add_column(
        'users',
        sa.Column(
            'reset_attempts',
            sa.Integer(),
            nullable=False,
            server_default='0',
        ),
    )
    op.add_column(
        'users',
        sa.Column('reset_token_hash', sa.String(length=255), nullable=True),
    )
    op.add_column(
        'users',
        sa.Column('reset_token_expires_at', sa.DateTime(), nullable=True),
    )
    op.create_index(
        op.f('ix_users_reset_token_hash'),
        'users',
        ['reset_token_hash'],
        unique=False,
    )

    # ---------------------------------------------------------------
    # TRIPS — numeric budget
    # ---------------------------------------------------------------
    op.add_column(
        'trips',
        sa.Column('budget_amount', sa.Numeric(precision=12, scale=2), nullable=True),
    )

    # ---------------------------------------------------------------
    # TRIP EXPENSES
    # ---------------------------------------------------------------
    op.create_table(
        'trip_expenses',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('trip_id', sa.Integer(), nullable=False),
        sa.Column('user_id', sa.Integer(), nullable=False),
        sa.Column('amount', sa.Numeric(precision=12, scale=2), nullable=False),
        sa.Column('currency', sa.String(length=10), nullable=False),
        sa.Column('category', sa.String(length=30), nullable=False),
        sa.Column('description', sa.String(length=255), nullable=True),
        sa.Column('date', sa.Date(), nullable=False),
        sa.Column('payment_method', sa.String(length=30), nullable=True),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.Column('updated_at', sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(['trip_id'], ['trips.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index(
        op.f('ix_trip_expenses_trip_id_date'),
        'trip_expenses',
        ['trip_id', 'date'],
        unique=False,
    )
    op.create_index(
        op.f('ix_trip_expenses_user_id'),
        'trip_expenses',
        ['user_id'],
        unique=False,
    )

    op.execute("ALTER TABLE trip_expenses ENABLE ROW LEVEL SECURITY")
    op.execute("ALTER TABLE trip_expenses FORCE ROW LEVEL SECURITY")

    op.execute(
        "CREATE POLICY trip_expenses_select_owner ON trip_expenses "
        "FOR SELECT USING (user_id = %s)" % _RLS_SUB
    )
    op.execute(
        "CREATE POLICY trip_expenses_insert_owner ON trip_expenses "
        "FOR INSERT WITH CHECK (user_id = %s)" % _RLS_SUB
    )
    op.execute(
        "CREATE POLICY trip_expenses_update_owner ON trip_expenses "
        "FOR UPDATE USING (user_id = %s) "
        "WITH CHECK (user_id = %s)" % (_RLS_SUB, _RLS_SUB)
    )
    op.execute(
        "CREATE POLICY trip_expenses_delete_owner ON trip_expenses "
        "FOR DELETE USING (user_id = %s)" % _RLS_SUB
    )


def downgrade():
    op.execute(
        "DROP POLICY IF EXISTS trip_expenses_delete_owner ON trip_expenses"
    )
    op.execute(
        "DROP POLICY IF EXISTS trip_expenses_update_owner ON trip_expenses"
    )
    op.execute(
        "DROP POLICY IF EXISTS trip_expenses_insert_owner ON trip_expenses"
    )
    op.execute(
        "DROP POLICY IF EXISTS trip_expenses_select_owner ON trip_expenses"
    )
    op.execute("ALTER TABLE trip_expenses DISABLE ROW LEVEL SECURITY")

    op.drop_index(
        op.f('ix_trip_expenses_user_id'),
        table_name='trip_expenses',
    )
    op.drop_index(
        op.f('ix_trip_expenses_trip_id_date'),
        table_name='trip_expenses',
    )
    op.drop_table('trip_expenses')

    op.drop_column('trips', 'budget_amount')

    op.drop_index(
        op.f('ix_users_reset_token_hash'),
        table_name='users',
    )
    op.drop_column('users', 'reset_token_expires_at')
    op.drop_column('users', 'reset_token_hash')
    op.drop_column('users', 'reset_attempts')
    op.drop_column('users', 'reset_code_expires_at')
    op.drop_column('users', 'reset_code_hash')