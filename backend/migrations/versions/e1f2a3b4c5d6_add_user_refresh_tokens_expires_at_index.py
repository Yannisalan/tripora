"""add user refresh tokens expires_at index

Revision ID: e1f2a3b4c5d6
Revises: c8d2e3f4a5b6
Create Date: 2026-11-06 00:00:00.000000

The ``UserRefreshToken`` model declares ``expires_at`` with ``index=True``,
which SQLAlchemy names ``ix_user_refresh_tokens_expires_at``. The migration
that created ``user_refresh_tokens`` (``b7c1d2e3f4a5``) omitted that index, so
add it here to bring the migrated schema back in line with the model.

Expired-token cleanup queries filter on ``expires_at``; the index keeps those
scans from degrading into a full table scan as the table grows.
"""

from alembic import op


# Revision identifiers, used by Alembic.
revision = "e1f2a3b4c5d6"
down_revision = "c8d2e3f4a5b6"
branch_labels = None
depends_on = None


def upgrade():
    op.create_index(
        "ix_user_refresh_tokens_expires_at",
        "user_refresh_tokens",
        ["expires_at"],
        unique=False,
    )


def downgrade():
    op.drop_index(
        "ix_user_refresh_tokens_expires_at",
        table_name="user_refresh_tokens",
    )
