"""add weather_cache table

Revision ID: b2f7a91c4e35
Revises: f3e4d5c6b7a8
Create Date: 2026-09-23 00:00:00.000000

Adds the ``weather_cache`` table used to persist Open-Meteo forecasts so they
survive Render restarts/cold starts (Free tier spins the service down on
inactivity, wiping any in-memory cache) and so a 429 daily-rate-limit response
can still serve a stale forecast instead of failing.

Like ``activity_logs`` this table is intentionally NOT put under
Row-Level Security: it is owned by the app role, written only by the weather
endpoint after trip ownership has been verified, and the payload is not
user-ownership scoped.
"""
from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = 'b2f7a91c4e35'
down_revision = 'f3e4d5c6b7a8'
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        'weather_cache',
        sa.Column('trip_id', sa.Integer(), nullable=False),
        sa.Column('destination', sa.String(length=255), nullable=False),
        sa.Column('start_date', sa.Date(), nullable=False),
        sa.Column('end_date', sa.Date(), nullable=False),
        sa.Column('data', sa.JSON(), nullable=False),
        sa.Column('fetched_at', sa.DateTime(), nullable=False),
        sa.PrimaryKeyConstraint('trip_id'),
    )
    op.create_index(op.f('ix_weather_cache_fetched_at'), 'weather_cache', ['fetched_at'], unique=False)


def downgrade():
    op.drop_index(op.f('ix_weather_cache_fetched_at'), table_name='weather_cache')
    op.drop_table('weather_cache')