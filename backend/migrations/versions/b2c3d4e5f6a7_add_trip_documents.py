"""add trip_documents table for the Trip Vault

Revision ID: b2c3d4e5f6a7
Revises: a0dd384f0147
Create Date: 2026-09-13 00:00:00.000000

Adds the ``trip_documents`` table backing the Trip Vault feature: metadata
for each stored travel document (flights, hotels, visas, insurance, ...).
The actual file bytes live in S3-compatible object storage; this table only
keeps the metadata plus the ``storage_key`` used to reach the object.

Ownership is enforced at the application layer (every route filters by the
JWT user id) AND at the database layer with Row-Level Security, mirroring the
way ``trips`` and ``subscriptions`` are protected in the previous migration
(``f0e9d8c7b6a5``).

- ``trip_id`` keeps documents attached to their trip and cascades on delete.
- ``user_id`` is a denormalised copy of the owner so RLS/authorization is a
  single-column check, exactly like the other ownership tables, and needs no
  join through ``trips`` at query time.

Notes:
- The table is FORCEd because every read/write path is authenticated.
- ``current_setting('request.jwt.claims.sub', true)`` is NULL for
  unauthenticated connections, so RLS fails closed automatically.
"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = 'b2c3d4e5f6a7'
down_revision = 'a0dd384f0147'
branch_labels = None
depends_on = None


_RLS_SUB = "current_setting('request.jwt.claims.sub', true)::integer"


def upgrade():
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

    # ---------------------------------------------------------------
    # ROW LEVEL SECURITY (defense-in-depth ownership)
    # ---------------------------------------------------------------
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


def downgrade():
    op.execute("DROP POLICY IF EXISTS trip_documents_delete_owner ON trip_documents")
    op.execute("DROP POLICY IF EXISTS trip_documents_update_owner ON trip_documents")
    op.execute("DROP POLICY IF EXISTS trip_documents_insert_owner ON trip_documents")
    op.execute("DROP POLICY IF EXISTS trip_documents_select_owner ON trip_documents")
    op.execute("ALTER TABLE trip_documents DISABLE ROW LEVEL SECURITY")

    op.drop_index(op.f('ix_trip_documents_user_id'), table_name='trip_documents')
    op.drop_index(op.f('ix_trip_documents_trip_id'), table_name='trip_documents')
    op.drop_table('trip_documents')