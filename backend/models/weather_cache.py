from datetime import datetime

from config.database import db


class WeatherCache(db.Model):
    """Persistent store for weather forecast cache entries.

    Replaces the previous in-memory ``_cache`` dict in ``routes/weather.py`` so
    forecasts survive Render restarts/cold starts (Free tier spins the service
    down on inactivity). One row per trip, upserted on every successful fetch
    from Open-Meteo.

    Two read paths consume it:

    - **fresh hit** — the row's ``fetched_at`` is within the 30-minute TTL and
      the stored destination/date window matches the trip, so the cached
      response is served without hitting Open-Meteo.
    - **stale fallback** — when Open-Meteo answers HTTP 429 (free-tier daily
      rate limit) and a previous forecast exists for the same trip/window, that
      older forecast is returned with ``stale: true`` instead of failing the
      whole call with ``forecast_unavailable``.

    Like ``activity_logs`` this table is intentionally not under Row-Level
    Security: it is owned and written by the app role, is only ever read after
    a trip's ownership has been verified, and forecast data is not
    user-ownership scoped.
    """

    __tablename__ = "weather_cache"

    # ============================================================
    # PRIMARY KEY
    # ============================================================

    trip_id = db.Column(
        db.Integer,
        primary_key=True,
    )

    # ============================================================
    # CACHE KEY (the request that produced the cached payload)
    # ============================================================

    destination = db.Column(
        db.String(255),
        nullable=False,
    )

    start_date = db.Column(
        db.Date,
        nullable=False,
    )

    end_date = db.Column(
        db.Date,
        nullable=False,
    )

    # ============================================================
    # PAYLOAD + TIMESTAMP
    # ============================================================

    # The exact HTTP payload served for a fresh cache hit
    # (destination, location, dates, forecast).
    data = db.Column(
        db.JSON,
        nullable=False,
    )

    fetched_at = db.Column(
        db.DateTime,
        default=datetime.utcnow,
        nullable=False,
        index=True,
    )