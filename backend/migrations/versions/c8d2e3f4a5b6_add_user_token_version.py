"""add user token version

Revision ID: c8d2e3f4a5b6
Revises: b7c1d2e3f4a5
Create Date: 2026-10-21 00:00:00.000000

Adds ``users.token_version``. The value is embedded in every issued access
token as the ``ver`` claim; bumping it revokes every access token that was
minted earlier (used after a password change / password reset).

Existing rows are initialised to 1 so that tokens issued before the upgrade
(no ``ver`` claim) keep working until they expire, while every new token
carries the claim and is revocable.
"""

from alembic import op
import sqlalchemy as sa


# Revision identifiers, used by Alembic.
revision = "c8d2e3f4a5b6"
down_revision = "b7c1d2e3f4a5"
branch_labels = None
depends_on = None


def upgrade():
    op.add_column(
        "users",
        sa.Column(
            "token_version",
            sa.Integer(),
            nullable=False,
            server_default="1",
        ),
    )


def downgrade():
    op.drop_column("users", "token_version")
