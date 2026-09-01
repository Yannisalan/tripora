"""Add verification token expiry

Revision ID: a0dd384f0147
Revises: c9d8e7f6a5b4
Create Date: 2026-09-01 19:39:19.072360

"""

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = "a0dd384f0147"
down_revision = "c9d8e7f6a5b4"
branch_labels = None
depends_on = None


def upgrade():
    # Add verification-code expiration timestamp.
    op.add_column(
        "users",
        sa.Column(
            "verification_token_expires_at",
            sa.DateTime(),
            nullable=True,
        ),
    )

    # Replace the old unique index with a unique constraint.
    op.drop_index(
        "ix_users_verification_token",
        table_name="users",
    )

    op.create_unique_constraint(
        "uq_users_verification_token",
        "users",
        ["verification_token"],
    )


def downgrade():
    # Remove the unique constraint.
    op.drop_constraint(
        "uq_users_verification_token",
        "users",
        type_="unique",
    )

    # Restore the unique index.
    op.create_index(
        "ix_users_verification_token",
        "users",
        ["verification_token"],
        unique=True,
    )

    # Remove expiration column.
    op.drop_column(
        "users",
        "verification_token_expires_at",
    )