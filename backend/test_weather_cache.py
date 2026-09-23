"""Tests for the persistent weather cache and the HTTP-429 stale fallback.

Covers the three behaviours introduced for the Open-Meteo free-tier daily
rate-limit problem:

1. A successful forecast is persisted to the ``weather_cache`` table and a
   fresh (<= 30 min) cache hit serves the stored payload without calling
   Open-Meteo again.
2. When Open-Meteo answers HTTP 429 and a prior forecast exists for the same
   trip/window (even an older one), the endpoint serves it with
   ``available: true`` + ``stale: true`` instead of ``forecast_unavailable``.
3. A 429 with no prior forecast still returns the original
   ``forecast_unavailable`` response unchanged.
4. The cache survives a process restart (new engine/session over the same
   database file), unlike the old in-memory ``_cache`` dict.

The routes decorate their view with ``@jwt_required()`` (a factory) and look
the trip up through the ORM, so - following the pattern in
``test_travel_routes.py`` - the JWT factory is replaced with a pass-through
before importing ``routes.weather`` and the trip lookup / geocoder are stubbed
with in-process fakes. ``requests.get`` (the only Open-Meteo call) is stubbed
per test.
"""

import sys
from datetime import date, datetime, timedelta
from types import SimpleNamespace

import flask_jwt_extended
import pytest
from flask import Flask

from config.database import db
from models.weather_cache import WeatherCache


# ------------------------------------------------------------
# Fixtures / helpers
# ------------------------------------------------------------

class FakeResponse:
    """Stand-in for a ``requests.Response`` from Open-Meteo."""

    def __init__(self, status_code, payload=None, text="", url=""):
        self.status_code = status_code
        self._payload = payload
        self.text = text
        self.url = url

    def json(self):
        if self._payload is None:
            raise ValueError("No JSON")
        return self._payload


def _success_payload():
    return {
        "daily": {
            "time": ["2026-09-24"],
            "weather_code": [1],
            "temperature_2m_max": [25.0],
            "temperature_2m_min": [18.0],
            "precipitation_probability_max": [10],
            "wind_speed_10m_max": [12.0],
        }
    }


def _fake_trip(start=None, end=None, destination="Tokyo, Japan"):
    return SimpleNamespace(
        destination=destination,
        start_date=start or date(2026, 9, 24),
        end_date=end or date(2026, 9, 24),
    )


def _build_app(monkeypatch, uri):
    """Create a minimal Flask app backed by ``uri`` and register the weather
    blueprint with JWT + trip-lookup guards stubbed out."""
    # jwt_required is used as a factory in the route, so replace it with a
    # lambda whose factory returns a pass-through decorator.
    monkeypatch.setattr(
        flask_jwt_extended,
        "jwt_required",
        lambda: (lambda fn: fn),
    )
    monkeypatch.setattr(
        flask_jwt_extended,
        "get_jwt_identity",
        lambda: "9",
    )

    # Import fresh (dropping any cached copy) so the patched decorators get
    # bound to the view on every test.
    sys.modules.pop("routes.weather", None)
    import routes.weather as weather_module

    # Stub the trip lookup (would need the real ORM + RLS context) and the
    # geocoder (no network in tests).
    monkeypatch.setattr(
        weather_module,
        "_get_owned_trip",
        lambda trip_id, user_id: _fake_trip(),
    )
    monkeypatch.setattr(
        weather_module,
        "_geocode_destination",
        lambda destination: ("Tokyo", "Japan", 35.6895, 139.69171),
    )

    app = Flask(__name__)
    app.config["TESTING"] = True
    app.config["SQLALCHEMY_DATABASE_URI"] = uri
    db.init_app(app)
    app.register_blueprint(weather_module.weather_bp)

    with app.app_context():
        db.create_all()

    return app, weather_module


def _seed_cache(app, weather_module, trip_id=23):
    """Persist a successful forecast the way the endpoint does after a 200."""
    trip = _fake_trip()
    forecast_start = trip.start_date
    forecast_end = trip.end_date
    data = {
        "destination": trip.destination,
        "location": {
            "name": "Tokyo",
            "country": "Japan",
            "latitude": 35.6895,
            "longitude": 139.69171,
        },
        "dates": {
            "start": trip.start_date.isoformat(),
            "end": trip.end_date.isoformat(),
            "forecastStart": forecast_start.isoformat(),
            "forecastEnd": forecast_end.isoformat(),
        },
        "forecast": [
            {
                "date": "2026-09-24",
                "weatherCode": 1,
                "label": "Mainly clear",
                "icon": "mostly_clear",
                "tempMax": 25.0,
                "tempMin": 18.0,
                "precipitationProbability": 10,
                "windSpeedMax": 12.0,
            }
        ],
    }
    with app.app_context():
        weather_module._cache_put(
            trip_id, trip.destination, trip.start_date, trip.end_date, data
        )
    return data


@pytest.fixture
def app_and_weather(monkeypatch):
    return _build_app(monkeypatch, "sqlite:///:memory:")


# ------------------------------------------------------------
# Fresh cache hit (persistence-backed, no provider call)
# ------------------------------------------------------------

def test_fresh_cache_hit_serves_stored_payload_without_provider(
    app_and_weather, monkeypatch
):
    app, weather_module = app_and_weather
    stored = _seed_cache(app, weather_module)

    def _no_network(*args, **kwargs):  # pragma: no cover - guard
        raise AssertionError("Open-Meteo must not be called on a fresh cache hit")

    monkeypatch.setattr(weather_module, "_geocode_destination", _no_network)
    monkeypatch.setattr(weather_module.requests, "get", _no_network)

    client = app.test_client()
    resp = client.get("/api/trips/23/weather")
    body = resp.get_json()

    assert resp.status_code == 200
    assert body["available"] is True
    assert body["cached"] is True
    assert body["forecast"] == stored["forecast"]


# ------------------------------------------------------------
# 429 with a prior forecast -> stale success
# ------------------------------------------------------------

def test_429_serves_stale_forecast_with_stale_flag(app_and_weather, monkeypatch):
    app, weather_module = app_and_weather
    stored = _seed_cache(app, weather_module)

    # Age the row beyond the 30-minute TTL: the fallback must ignore TTL.
    with app.app_context():
        row = weather_module._cache_row(23)
        row.fetched_at = datetime.utcnow() - timedelta(hours=6)
        db.session.commit()

    monkeypatch.setattr(
        weather_module.requests,
        "get",
        lambda *args, **kwargs: FakeResponse(429, text="Daily API request limit exceeded"),
    )

    client = app.test_client()
    resp = client.get("/api/trips/23/weather")
    body = resp.get_json()

    assert resp.status_code == 200
    assert body["available"] is True
    assert body["stale"] is True
    assert body["forecast"] == stored["forecast"]


def test_429_without_prior_forecast_returns_forecast_unavailable(
    app_and_weather, monkeypatch
):
    app, weather_module = app_and_weather

    monkeypatch.setattr(
        weather_module.requests,
        "get",
        lambda *args, **kwargs: FakeResponse(429, text="Daily API request limit exceeded"),
    )

    client = app.test_client()
    resp = client.get("/api/trips/23/weather")
    body = resp.get_json()

    assert resp.status_code == 200
    assert body["available"] is False
    assert body["reason"] == "forecast_unavailable"
    assert body["message"] == "Weather forecast is temporarily unavailable."
    assert "stale" not in body


def test_429_with_forecast_for_a_different_window_is_not_served(
    app_and_weather, monkeypatch
):
    """Stale fallback only applies when the cached window matches, so a
    different trip window must not be served."""
    app, weather_module = app_and_weather
    _seed_cache(app, weather_module)

    # Trip now has a different date range than the cached entry.
    monkeypatch.setattr(
        weather_module,
        "_get_owned_trip",
        lambda trip_id, user_id: _fake_trip(
            start=date(2026, 9, 25), end=date(2026, 9, 25)
        ),
    )
    monkeypatch.setattr(
        weather_module.requests,
        "get",
        lambda *args, **kwargs: FakeResponse(429, text="Daily API request limit exceeded"),
    )

    client = app.test_client()
    resp = client.get("/api/trips/23/weather")
    body = resp.get_json()

    assert body["available"] is False
    assert body["reason"] == "forecast_unavailable"


# ------------------------------------------------------------
# Successful fetch persists, and persists across a "restart"
# ------------------------------------------------------------

def test_successful_fetch_persists_forecast(app_and_weather, monkeypatch):
    app, weather_module = app_and_weather

    monkeypatch.setattr(
        weather_module.requests,
        "get",
        lambda *args, **kwargs: FakeResponse(200, payload=_success_payload()),
    )

    client = app.test_client()
    resp = client.get("/api/trips/23/weather")
    body = resp.get_json()

    assert resp.status_code == 200
    assert body["available"] is True
    assert body["cached"] is False
    assert "stale" not in body  # fresh fetch, not stale
    assert len(body["forecast"]) == 1

    row = None
    with app.app_context():
        row = weather_module._cache_row(23)
    assert row is not None
    assert row.data["forecast"] == body["forecast"]


def test_cache_survives_restart(tmp_path, monkeypatch):
    """A forecast written by one process (engine/session) is readable by a
    brand-new engine over the same database file - i.e. a Render restart no
    longer loses the cache."""
    db_file = tmp_path / "cache.db"
    uri = f"sqlite:///{db_file}"

    app1, weather1 = _build_app(monkeypatch, uri)
    with app1.app_context():
        weather1._cache_put(
            23,
            "Tokyo, Japan",
            date(2026, 9, 24),
            date(2026, 9, 24),
            {"dates": {"forecastStart": "2026-09-24",
                       "forecastEnd": "2026-09-24"},
             "forecast": [{"date": "2026-09-24"}]},
        )
        db.session.remove()
        db.engine.dispose()

    # Simulated restart: fresh app, fresh engine, same on-disk database.
    app2, weather2 = _build_app(monkeypatch, uri)
    with app2.app_context():
        cached = weather2._cache_get_fresh(
            23, "Tokyo, Japan", date(2026, 9, 24), date(2026, 9, 24)
        )
        stale = weather2._cache_get_stale_forecast(
            23, date(2026, 9, 24), date(2026, 9, 24)
        )

    assert cached is not None
    assert cached["forecast"] == [{"date": "2026-09-24"}]
    assert stale == [{"date": "2026-09-24"}]


# ------------------------------------------------------------
# Itinerary generation path uses the same persistent backing
# ------------------------------------------------------------

def test_generation_reads_persistent_cache_without_provider(
    app_and_weather, monkeypatch
):
    app, weather_module = app_and_weather
    stored = _seed_cache(app, weather_module)

    def _no_network(*args, **kwargs):  # pragma: no cover - guard
        raise AssertionError("generation must be served from the cache")

    monkeypatch.setattr(weather_module, "_geocode_destination", _no_network)
    monkeypatch.setattr(weather_module.requests, "get", _no_network)

    with app.app_context():
        forecast = weather_module.get_forecast_for_generation(
            "Tokyo, Japan",
            date(2026, 9, 24),
            date(2026, 9, 24),
            trip_id=23,
        )

    assert forecast == stored["forecast"]


def test_generation_429_falls_back_to_stale_forecast(
    app_and_weather, monkeypatch
):
    app, weather_module = app_and_weather
    stored = _seed_cache(app, weather_module)

    monkeypatch.setattr(
        weather_module.requests,
        "get",
        lambda *args, **kwargs: FakeResponse(429, text="Daily API request limit exceeded"),
    )

    with app.app_context():
        forecast = weather_module.get_forecast_for_generation(
            "Tokyo, Japan",
            date(2026, 9, 24),
            date(2026, 9, 24),
            trip_id=23,
        )

    assert forecast == stored["forecast"]
