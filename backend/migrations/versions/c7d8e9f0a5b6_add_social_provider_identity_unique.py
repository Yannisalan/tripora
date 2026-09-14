"""Enforce uniqueness on social provider identities

Revision ID: c7d8e9f0a5b6
Revises: 3e2d1c0b9a87
Create Date: 2026-09-13 00:00:00.000000

Account uniqueness is already guaranteed for email/password accounts by the
unique ``email`` column. Social identities carry a second, provider-owned
identifier (``provider_id`` — Google's ``sub``, Apple's ``sub``), so add a
partial unique index on ``(auth_provider, provider_id)`` to make it
impossible for a single Google/Apple identity to map to two Tripora rows,
even under a race between two concurrent sign-in requests.

Regular users (auth_provider IS NULL) are excluded by the partial index so
the ``NULL`` provider_id of conventional accounts does not collide.
"""
from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = 'c7d8e9f0a5b6'
down_revision = '3e2d1c0b9a87'
branch_labels = None
depends_on = None


def upgrade():
    op.create_index(
        'ix_users_social_identity',
        'users',
        ['auth_provider', 'provider_id'],
        unique=True,
        postgresql_where=sa.text('auth_provider IS NOT NULL'),
    )


def downgrade():
    op.drop_index(
        'ix_users_social_identity',
        table_name='users',
        postgresql_where=sa.text('auth_provider IS NOT NULL'),
    )