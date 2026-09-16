"""drop trip_documents table (Trip Vault removed)

Revision ID: a7b8c9d0e1f2
Revises: c7d8e9f0a5b6
Create Date: 2026-09-16 00:00:00.000000

The Trip Vault feature is gone, along with its object-storage wiring. This
migration removes the accompanying ``trip_documents`` table.

The original feature migration (``b2c3d4e5f6a7``) was removed from the chain,
so a from-scratch database never creates this table; ``DROP TABLE IF EXISTS``
keeps both paths working (fresh rewrite DBs AND any DB created by the old
chain).
"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = 'a7b8c9d0e1f2'
down_revision = 'c7d8e9f0a5b6'
branch_labels = None
depends_on = None


_RLS_SUB = "current_setting('request.jwt.claims.sub', true)::integer"


def upgrade():
    # Dropping the table also removes its indexes and any RLS policies.
    op.execute("DROP TABLE IF EXISTS trip_documents")


def downgrade():
    # Recreate exactly what ``b2c3d4e5f6a7`` originally created, including its
    # Row-Level Security policies, so ``upgrade``/``downgrade`` round-tripping
    # stays reversible.
    op.create_table(
        'trip_documents',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('trip_id', sa.Integer(), nullable=False),
        sa.Column('user_id', sa.Integer(), nullable=False),
        sa.Column('name', sa.String(length=255), nullable=False),
        sa.Column('document_type', sa.String(length=30), nullable=False),
        sa.Column('file_name', sa.String(length=255), nullable=False),
        sa.Column('storage_key', sa.String(length=255), nullable=False),
        sa.Column('mime_type', sa.String(length=100), nullable=False),
        sa.Column('file_size', sa.BigInteger(), nullable=False),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.Column('updated_at', sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(['trip_id'], ['trips.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index(
        op.f('ix_trip_documents_trip_id'),
        'trip_documents',
        ['trip_id'],
        unique=False,
    )
    op.create_index(
        op.f('ix_trip_documents_user_id'),
        'trip_documents',
        ['user_id'],
        unique=False,
    )

    op.execute("ALTER TABLE trip_documents ENABLE ROW LEVEL SECURITY")
    op.execute("ALTER TABLE trip_documents FORCE ROW LEVEL SECURITY")

    op.execute(
        "CREATE POLICY trip_documents_select_owner ON trip_documents "
        "FOR SELECT USING (user_id = %s)" % _RLS_SUB
    )
    op.execute(
        "CREATE POLICY trip_documents_insert_owner ON trip_documents "
        "FOR INSERT WITH CHECK (user_id = %s)" % _RLS_SUB
    )
    op.execute(
        "CREATE POLICY trip_documents_update_owner ON trip_documents "
        "FOR UPDATE USING (user_id = %s) "
        "WITH CHECK (user_id = %s)" % (_RLS_SUB, _RLS_SUB)
    )
    op.execute(
        "CREATE POLICY trip_documents_delete_owner ON trip_documents "
        "FOR DELETE USING (user_id = %s)" % _RLS_SUB
    )