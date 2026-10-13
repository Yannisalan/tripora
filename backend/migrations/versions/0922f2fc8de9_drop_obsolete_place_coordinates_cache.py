"""Drop obsolete place coordinates cache.

Revision ID: 0922f2fc8de9
Revises: b2f7a91c4e35
"""

from alembic import op
import sqlalchemy as sa

# Revision identifiers, used by Alembic.
revision = "0922f2fc8de9"
down_revision = "b2f7a91c4e35"
branch_labels = None
depends_on = None


def upgrade():
    """Remove the obsolete geocoding-cache table."""
    op.drop_table("place_coordinates")


def downgrade():
    """Recreate the table structure if the migration is rolled back."""
    op.create_table(
        "place_coordinates",
        sa.Column(
            "id",
            sa.Integer(),
            autoincrement=True,
            nullable=False,
        ),
        sa.Column("query", sa.String(length=255), nullable=False),
        sa.Column("name", sa.String(length=255), nullable=True),
        sa.Column("display_name", sa.String(length=512), nullable=True),
        sa.Column(
            "latitude",
            sa.Numeric(precision=9, scale=6),
            nullable=True,
        ),
        sa.Column(
            "longitude",
            sa.Numeric(precision=9, scale=6),
            nullable=True,
        ),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
        sa.PrimaryKeyConstraint(
            "id",
            name="place_coordinates_pkey",
        ),
    )

    op.create_index(
        "ix_place_coordinates_query",
        "place_coordinates",
        ["query"],
        unique=True,
    )
