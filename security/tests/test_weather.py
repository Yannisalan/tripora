"""Tests for the Tripora weather forecast endpoint.

``GET /api/trips/<id>/weather`` proxies Open-Meteo (geocoding + forecast).
These tests stub ``requests.get`` so the suite stays hermetic and fast, and
they simulate Open-Meteo's real behaviour: daily data is only served inside
the 16-day forecast horizon, and a request whose end date exceeds that
horizon is rejected with HTTP 400 (the root cause of the original
"Forecast unavailable" bug). The route must clamp its requested window to
the available portion instead of failing the whole trip.
"""

import json
from datetime import date, timedelta

import pytest

import routes.weather as weather_module
from .helpers import (
    auth_headers,
    create_logged_in_user,
    create_trip_and_get_id,
)

# Fixed "today" so date arithmetic in the route is deterministic in tests.
FIXED_TODAY = date(2026, 9, 16)
HORIZON_DAYS = 16
MAX_END = FIXED_TODAY + timedelta(days=HORIZON_DAYS - 1)  # 2026-10-01

TRIP_PAYLOAD = {
    "destination": "Cotonou",
    "startDate": "2026-09-15",
    "endDate": "2026-09-22",
    "travelers": 2,
    "budget": "moderate",
    "travelStyle": "balanced",
    "interests": ["food", "culture"],
}

_GEOCODE_PAYLOAD = {
    "results": [
        {
            "name": "Cotonou",
            "country": "Benin",
            "latitude": 6.36536,
            "longitude": 2.41833,
        }
    ]
}


class _FakeResponse:
    def __init__(self, status_code, payload):
        self.status_code = status_code
        self._payload = payload
        self.url = "https://api.open-meteo.com/v1/forecast?from=test"
        self.text = json.dumps(payload) if payload is not None else ""

    def json(self):
        return self._payload


def _daily_payload(start, end):
    """Build a realistic Open-Meteo ``daily`` dict for every day in range."""
    days = []
    cur = start
    n = 0
    while cur <= end:
        days.append(cur.isoformat())
        cur += timedelta(days=1)
        n += 1
    return {
        "time": days,
        "weather_code": [51] * n,
        "temperature_2m_max": [28.9] * n,
        "temperature_2m_min": [26.1] * n,
        "precipitation_probability_max": [78] * n,
        "wind_speed_10m_max": [23.5] * n,
    }


def _install_fakes(monkeypatch, geocode_payload=_GEOCODE_PAYLOAD):
    """Patch geocoding + forecast calls; return the captured forecast params."""
    forecast_calls = []

    def fake_get(url, params=None, timeout=None):
        if url.startswith(
            "https://geocoding-api.open-meteo.com/"
        ):
            return _FakeResponse(200, geocode_payload)

        forecast_calls.append(dict(params or {}))
        start = date.fromisoformat(params["start_date"])
        end = date.fromisoformat(params["end_date"])
        if end > MAX_END:
            return _FakeResponse(
                400,
                {
                    "reason": (
                        "Parameter 'end_date' is out of allowed range "
                        "from {start} to {max_end}".format(
                            start=start, max_end=MAX_END
                        )
                    ),
                    "error": True,
                },
            )
        return _FakeResponse(
            200,
            {"daily": _daily_payload(start, end)},
        )

    monkeypatch.setattr(
        weather_module, "_utc_today", lambda: FIXED_TODAY
    )
    monkeypatch.setattr(weather_module.requests, "get", fake_get)
    return forecast_calls


@pytest.fixture(autouse=True)
def _clear_weather_cache():
    """The in-memory forecast cache is process-global; isolate per test."""
    weather_module._cache.clear()
    yield
    weather_module._cache.clear()


def _weather(client, token, trip_id):
    return client.get(
        "/api/trips/{}/weather".format(trip_id),
        headers=auth_headers(token),
    )


# ------------------------------------------------------------
# The reported bug scenario: ongoing trip with a passed start date
# ------------------------------------------------------------

def test_ongoing_trip_requests_only_available_portion(client, monkeypatch):
    """Cotonou 09-15 -> 09-22 should clamp start to today (09-16) and return
    exactly 09-16..09-22, never rejecting the trip because 09-15 passed."""
    alice = create_logged_in_user(
        client, name="WxAlice", email="wxalice@example.com"
    )
    forecast_calls = _install_fakes(monkeypatch)
    trip_id = create_trip_and_get_id(client, alice, **TRIP_PAYLOAD)

    resp = _weather(client, alice, trip_id)
    assert resp.status_code == 200
    body = resp.get_json()

    assert body["success"] is True
    assert body["available"] is True

    dates = body["dates"]
    assert dates["start"] == "2026-09-15"
    assert dates["end"] == "2026-09-22"
    assert dates["forecastStart"] == "2026-09-16"
    assert dates["forecastEnd"] == "2026-09-22"

    # The backend must only ask Open-Meteo for the available portion.
    assert forecast_calls
    requested = forecast_calls[0]
    assert requested["start_date"] == "2026-09-16"
    assert requested["end_date"] == "2026-09-22"
    assert requested["latitude"] == 6.36536
    assert requested["longitude"] == 2.41833

    days = body["forecast"]
    assert len(days) == 7
    assert days[0]["date"] == "2026-09-16"
    assert days[-1]["date"] == "2026-09-22"


# ------------------------------------------------------------
# End-of-horizon: must return partial forecast, not "unavailable"
# ------------------------------------------------------------

def test_trip_end_beyond_horizon_returns_partial_forecast(
    client, monkeypatch
):
    """A trip ending +20 days out must return the 16 available days instead
    of being treated as entirely unavailable."""
    alice = create_logged_in_user(
        client, name="WxBob", email="wxbob@example.com"
    )
    forecast_calls = _install_fakes(monkeypatch)
    payload = dict(TRIP_PAYLOAD)
    payload["startDate"] = "2026-09-16"
    payload["endDate"] = "2026-10-20"
    trip_id = create_trip_and_get_id(client, alice, **payload)

    resp = _weather(client, alice, trip_id)
    assert resp.status_code == 200
    body = resp.get_json()

    assert body["available"] is True
    assert body["dates"]["forecastEnd"] == "2026-10-01"

    requested = forecast_calls[0]
    assert requested["end_date"] == "2026-10-01"

    days = body["forecast"]
    assert len(days) == HORIZON_DAYS
    assert days[0]["date"] == "2026-09-16"
    assert days[-1]["date"] == "2026-10-01"


def test_trip_fully_beyond_horizon_reports_unavailable(client, monkeypatch):
    """A trip that starts after the 16-day horizon has nothing to show."""
    alice = create_logged_in_user(
        client, name="WxCara", email="wxcara@example.com"
    )
    _install_fakes(monkeypatch)
    payload = dict(TRIP_PAYLOAD)
    payload["startDate"] = "2026-10-05"
    payload["endDate"] = "2026-10-10"
    trip_id = create_trip_and_get_id(client, alice, **payload)

    resp = _weather(client, alice, trip_id)
    body = resp.get_json()
    assert resp.status_code == 200
    assert body["available"] is False
    assert body["reason"] == "forecast_unavailable"


# ------------------------------------------------------------
# Guard rails (preserved behaviour)
# ------------------------------------------------------------

def test_ended_trip_reports_trip_ended(client, monkeypatch):
    alice = create_logged_in_user(
        client, name="WxDee", email="wxdee@example.com"
    )
    _install_fakes(monkeypatch)
    payload = dict(TRIP_PAYLOAD)
    payload["startDate"] = "2026-09-01"
    payload["endDate"] = "2026-09-10"
    trip_id = create_trip_and_get_id(client, alice, **payload)

    resp = _weather(client, alice, trip_id)
    body = resp.get_json()
    assert resp.status_code == 200
    assert body["success"] is True
    assert body["available"] is False
    assert body["reason"] == "trip_ended"


def test_geocoding_failure_reports_geocoding_failed(client, monkeypatch):
    alice = create_logged_in_user(
        client, name="WxEve", email="wxeve@example.com"
    )
    _install_fakes(monkeypatch, geocode_payload={"results": []})
    trip_id = create_trip_and_get_id(client, alice, **TRIP_PAYLOAD)

    resp = _weather(client, alice, trip_id)
    body = resp.get_json()
    assert body["available"] is False
    assert body["reason"] == "geocoding_failed"


def test_forecast_provider_failure_reports_unavailable(client, monkeypatch):
    alice = create_logged_in_user(
        client, name="WxFred", email="wxfred@example.com"
    )
    forecast_calls = []

    def boom(url, params=None, timeout=None):
        if url.startswith("https://geocoding-api.open-meteo.com/"):
            return _FakeResponse(200, _GEOCODE_PAYLOAD)
        forecast_calls.append(dict(params or {}))
        raise OSError("network down")

    monkeypatch.setattr(weather_module, "_utc_today", lambda: FIXED_TODAY)
    monkeypatch.setattr(weather_module.requests, "get", boom)
    trip_id = create_trip_and_get_id(client, alice, **TRIP_PAYLOAD)

    resp = _weather(client, alice, trip_id)
    body = resp.get_json()
    assert body["available"] is False
    assert body["reason"] == "forecast_unavailable"


def test_trip_ownership_enforced(client, monkeypatch):
    """User B must not see user A's weather (404)."""
    alice = create_logged_in_user(
        client, name="WxOwAl", email="wxowal@example.com"
    )
    bob = create_logged_in_user(
        client, name="WxOwBo", email="wxowbo@example.com"
    )
    _install_fakes(monkeypatch)
    trip_id = create_trip_and_get_id(client, alice, **TRIP_PAYLOAD)

    resp = _weather(client, bob, trip_id)
    assert resp.status_code == 404
    assert resp.get_json()["success"] is False