"""Add user verification and preferences

Revision ID: a1b2c3d4e5f6
Revises: 868ba3ede438
Create Date: 2026-08-29 00:00:00.000000

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = 'a1b2c3d4e5f6'
down_revision = '868ba3ede438'
branch_labels = None
depends_on = None


def upgrade():
    with op.batch_alter_table('users', schema=None) as batch_op:
        batch_op.add_column(sa.Column('email_verified', sa.Boolean(), nullable=False, server_default=sa.false()))
        batch_op.add_column(sa.Column('verification_token', sa.String(length=255), nullable=True))
        batch_op.add_column(sa.Column('preferred_language', sa.String(length=10), nullable=False, server_default='en'))
        batch_op.add_column(sa.Column('preferred_currency', sa.String(length=10), nullable=False, server_default='USD'))
        batch_op.create_index(batch_op.f('ix_users_verification_token'), ['verification_token'], unique=True)


def downgrade():
    with op.batch_alter_table('users', schema=None) as batch_op:
        batch_op.drop_index(batch_op.f('ix_users_verification_token'))
        batch_op.drop_column('preferred_currency')
        batch_op.drop_column('preferred_language')
        batch_op.drop_column('verification_token')
        batch_op.drop_column('email_verified')
