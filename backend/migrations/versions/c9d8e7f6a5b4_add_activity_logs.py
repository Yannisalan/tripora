"""add activity_logs table

Revision ID: c9d8e7f6a5b4
Revises: f0e9d8c7b6a5
Create Date: 2026-09-01 00:00:00.000000

Adds the ``activity_logs`` table used by the admin analytics surface to record
page views and API requests.

Unlike ``trips`` and ``subscriptions`` this table is intentionally NOT put under
Row-Level Security: it is owned by the app role and only ever written by the
app itself (request/after-request hooks and the public page-view beacon), and
only ever read back through the token-gated admin endpoints. App-level scoping
is not needed here since the data is analytics, not per-user ownership.
"""
from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = 'c9d8e7f6a5b4'
down_revision = 'f0e9d8c7b6a5'
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        'activity_logs',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('event_type', sa.String(length=30), nullable=False),
        sa.Column('path', sa.String(length=255), nullable=True),
        sa.Column('method', sa.String(length=10), nullable=True),
        sa.Column('status_code', sa.Integer(), nullable=True),
        sa.Column('user_id', sa.Integer(), nullable=True),
        sa.Column('detail', sa.JSON(), nullable=True),
        sa.Column('ip_address', sa.String(length=64), nullable=True),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index(op.f('ix_activity_logs_event_type'), 'activity_logs', ['event_type'], unique=False)
    op.create_index(op.f('ix_activity_logs_path'), 'activity_logs', ['path'], unique=False)
    op.create_index(op.f('ix_activity_logs_user_id'), 'activity_logs', ['user_id'], unique=False)
    op.create_index(op.f('ix_activity_logs_created_at'), 'activity_logs', ['created_at'], unique=False)


def downgrade():
    op.drop_index(op.f('ix_activity_logs_created_at'), table_name='activity_logs')
    op.drop_index(op.f('ix_activity_logs_user_id'), table_name='activity_logs')
    op.drop_index(op.f('ix_activity_logs_path'), table_name='activity_logs')
    op.drop_index(op.f('ix_activity_logs_event_type'), table_name='activity_logs')
    op.drop_table('activity_logs')
