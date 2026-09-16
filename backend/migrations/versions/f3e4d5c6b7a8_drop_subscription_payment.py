"""drop subscriptions table (monetization removed)

Revision ID: f3e4d5c6b7a8
Revises: a7b8c9d0e1f2
Create Date: 2026-09-16 00:00:00.000000

All monetization is gone: there is no premium plan, no IAP/payment provider and
no subscription tiering. This migration removes the ``subscriptions`` table.

The original table was created by ``a5b6c7d8e9f0``; that migration has been
reworked to only add the ``users.region_country`` column, so a from-scratch
database never creates this table. ``DROP TABLE IF EXISTS`` keeps both paths
working (fresh rewrite DBs AND any DB created by the old chain).
"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = 'f3e4d5c6b7a8'
down_revision = 'a7b8c9d0e1f2'
branch_labels = None
depends_on = None


def upgrade():
    # Dropping the table also removes its indexes and any RLS policies.
    op.execute("DROP TABLE IF EXISTS subscriptions")


def downgrade():
    # Recreate exactly what ``a5b6c7d8e9f0`` originally created, so
    # ``upgrade``/``downgrade`` round-tripping stays reversible.
    op.create_table(
        'subscriptions',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('user_id', sa.Integer(), nullable=False),
        sa.Column('tier', sa.String(length=20), nullable=False),
        sa.Column('period', sa.String(length=20), nullable=False),
        sa.Column('status', sa.String(length=20), nullable=False),
        sa.Column('store', sa.String(length=20), nullable=True),
        sa.Column('store_product_id', sa.String(length=255), nullable=True),
        sa.Column('store_transaction_id', sa.String(length=255), nullable=True),
        sa.Column('active_until', sa.DateTime(), nullable=True),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.Column('updated_at', sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('user_id'),
    )
    op.create_index(op.f('ix_subscriptions_store_transaction_id'), 'subscriptions', ['store_transaction_id'], unique=False)