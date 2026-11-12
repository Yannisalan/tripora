"""create user refresh tokens table

Revision ID: b7c1d2e3f4a5
Revises: 0922f2fc8de9
Create Date: 2026-10-17 00:00:00.000000

Adds the rotating-refresh-token store used for persistent sessions. Only the
SHA-256 hash of each token is stored; ``family_id`` groups the tokens issued
from a single login so a replayed (already-rotated) token can revoke the whole
chain. Purely additive: no existing table is modified.
"""

from alembic import op
import sqlalchemy as sa


# Revision identifiers, used by Alembic.
revision = "b7c1d2e3f4a5"
down_revision = "0922f2fc8de9"
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        "user_refresh_tokens",
        sa.Column(
            "id",
            sa.Integer(),
            autoincrement=True,
            nullable=False,
        ),
        sa.Column("user_id", sa.Integer(), nullable=False),
        sa.Column("token_hash", sa.String(length=64), nullable=False),
        sa.Column("family_id", sa.String(length=32), nullable=False),
        sa.Column(
            "replaced_by_hash",
            sa.String(length=64),
            nullable=True,
        ),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("expires_at", sa.DateTime(), nullable=False),
        sa.Column("last_used_at", sa.DateTime(), nullable=True),
        sa.Column("revoked_at", sa.DateTime(), nullable=True),
        sa.Column("user_agent", sa.String(length=255), nullable=True),
        sa.ForeignKeyConstraint(
            ["user_id"],
            ["users.id"],
            name="user_refresh_tokens_user_id_fkey",
        ),
        sa.PrimaryKeyConstraint(
            "id",
            name="user_refresh_tokens_pkey",
        ),
    )

    op.create_index(
        "ix_user_refresh_tokens_user_id",
        "user_refresh_tokens",
        ["user_id"],
        unique=False,
    )
    op.create_index(
        "ix_user_refresh_tokens_token_hash",
        "user_refresh_tokens",
        ["token_hash"],
        unique=True,
    )
    op.create_index(
        "ix_user_refresh_tokens_family_id",
        "user_refresh_tokens",
        ["family_id"],
        unique=False,
    )


def downgrade():
    op.drop_index(
        "ix_user_refresh_tokens_family_id",
        table_name="user_refresh_tokens",
    )
    op.drop_index(
        "ix_user_refresh_tokens_token_hash",
        table_name="user_refresh_tokens",
    )
    op.drop_index(
        "ix_user_refresh_tokens_user_id",
        table_name="user_refresh_tokens",
    )
    op.drop_table("user_refresh_tokens")
