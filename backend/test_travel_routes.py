"""Tests for the premium-only travel search endpoints.

The routes decorate their views with ``@jwt_required()`` (a factory) and
``@require_premium`` at import time, so we patch the *source* symbols before
importing ``routes.travel``. That lets us exercise the validation and
response-shaping logic in isolation, plus the premium-gating contract
(free user -> 403 PREMIUM_REQUIRED, unauthenticated -> 401 handled by the
real JWT decorator when not patched).
"""

import sys

import flask_jwt_extended
import pytest
from flask import Flask
import services.duffel_service as duffel_module
import services.subscription_service as subscription_module


def _stub_results(kind):
    return {"count": 1, kind: [{"id": "x"}], "disclaimer": "d"}


def _load_app_with_guards(monkeypatch, premium_decorator, flights=None,
                          stays=None, cars=None):
    """Build a fresh Flask app with the patrol-guard seams replaced.

    ``premium_decorator`` is the function used in place of ``require_premium``
    (the real one needs a DB). ``flights/stays/cars`` stub the Duffel calls.
    """
    # jwt_required is used as a *factory* in the routes (``@jwt_required()``),
    # so replacing it with ``lambda: (lambda fn: fn)`` makes the factory return
    # a pass-through decorator.
    monkeypatch.setattr(
        flask_jwt_extended,
        "jwt_required",
        lambda: (lambda fn: fn),
    )
    monkeypatch.setattr(subscription_module, "require_premium", premium_decorator)

    monkeypatch.setattr(
        duffel_module,
        "search_flights",
        flights or (lambda **kwargs: _stub_results("flights")),
    )
    monkeypatch.setattr(
        duffel_module,
        "search_stays",
        stays or (lambda **kwargs: _stub_results("stays")),
    )
    monkeypatch.setattr(
        duffel_module,
        "search_cars",
        cars or (lambda **kwargs: _stub_results("cars")),
    )

    # Import fresh (dropping any cached copy) so the patched decorators get
    # bound to the views on every test.
    sys.modules.pop("routes.travel", None)
    import routes.travel as travel_module

    app = Flask(__name__)
    app.config["TESTING"] = True
    app.register_blueprint(travel_module.travel_bp)
    return app.test_client()


def _pass_through(fn):
    return fn


@pytest.fixture
def client(monkeypatch):
    return _load_app_with_guards(monkeypatch, _pass_through)


# ------------------------------------------------------------
# Flights
# ------------------------------------------------------------

def test_flights_search_success(client):
    resp = client.post("/api/travel/flights/search", json={
        "origin": "JFK", "destination": "LHR", "departDate": "2026-10-01",
        "passengers": 2,
    })
    assert resp.status_code == 200
    body = resp.get_json()
    assert body["success"] is True
    assert body["results"]["count"] == 1


def test_flights_requires_origin_and_destination(client):
    resp = client.post("/api/travel/flights/search", json={"departDate": "2026-10-01"})
    assert resp.status_code == 400
    assert resp.get_json()["success"] is False


def test_flights_rejects_bad_iata(client):
    resp = client.post("/api/travel/flights/search", json={
        "origin": "NEWY", "destination": "LHR", "departDate": "2026-10-01",
    })
    assert resp.status_code == 400


def test_flights_rejects_same_airport(client):
    resp = client.post("/api/travel/flights/search", json={
        "origin": "JFK", "destination": "JFK", "departDate": "2026-10-01",
    })
    assert resp.status_code == 400


def test_flights_requires_depart_date(client):
    resp = client.post("/api/travel/flights/search", json={
        "origin": "JFK", "destination": "LHR",
    })
    assert resp.status_code == 400


def test_flights_rejects_return_before_depart(client):
    resp = client.post("/api/travel/flights/search", json={
        "origin": "JFK", "destination": "LHR",
        "departDate": "2026-10-05", "returnDate": "2026-10-01",
    })
    assert resp.status_code == 400


def test_flights_rejects_bad_cabin(client):
    resp = client.post("/api/travel/flights/search", json={
        "origin": "JFK", "destination": "LHR", "departDate": "2026-10-01",
        "cabinClass": "spaceship",
    })
    assert resp.status_code == 400


# ------------------------------------------------------------
# Stays
# ------------------------------------------------------------

def test_stays_search_success(client):
    resp = client.post("/api/travel/stays/search", json={
        "location": "Paris",
        "checkIn": "2026-10-01", "checkOut": "2026-10-05",
        "guests": 2, "rooms": 1,
    })
    assert resp.status_code == 200
    assert resp.get_json()["results"]["count"] == 1


def test_stays_requires_location(client):
    resp = client.post("/api/travel/stays/search", json={
        "checkIn": "2026-10-01", "checkOut": "2026-10-05",
    })
    assert resp.status_code == 400


def test_stays_requires_dates(client):
    resp = client.post("/api/travel/stays/search", json={"location": "Paris"})
    assert resp.status_code == 400


def test_stays_rejects_checkout_before_checkin(client):
    resp = client.post("/api/travel/stays/search", json={
        "location": "Paris",
        "checkIn": "2026-10-05", "checkOut": "2026-10-01",
    })
    assert resp.status_code == 400


# ------------------------------------------------------------
# Cars
# ------------------------------------------------------------

def test_cars_search_success(client):
    resp = client.post("/api/travel/cars/search", json={
        "pickup": "LHR", "dropoff": "CDG",
        "pickupDateTime": "2026-10-01T10:00:00",
        "dropoffDateTime": "2026-10-05T18:00:00",
        "driverAge": 30,
    })
    assert resp.status_code == 200
    assert resp.get_json()["results"]["count"] == 1


def test_cars_requires_pickup_and_dropoff(client):
    resp = client.post("/api/travel/cars/search", json={})
    assert resp.status_code == 400


def test_cars_requires_datetimes(client):
    resp = client.post("/api/travel/cars/search", json={
        "pickup": "LHR", "dropoff": "CDG",
    })
    assert resp.status_code == 400


def test_cars_rejects_invalid_datetime(client):
    resp = client.post("/api/travel/cars/search", json={
        "pickup": "LHR", "dropoff": "CDG",
        "pickupDateTime": "not-a-date",
        "dropoffDateTime": "2026-10-05T18:00:00",
    })
    assert resp.status_code == 400


# ------------------------------------------------------------
# Provider failure -> clean 502, not a crash
# ------------------------------------------------------------

def test_flights_provider_error_maps_to_502(monkeypatch):
    from services.duffel_service import DuffelError

    def boom(**kwargs):
        raise DuffelError("provider down")

    client = _load_app_with_guards(monkeypatch, _pass_through, flights=boom)

    resp = client.post("/api/travel/flights/search", json={
        "origin": "JFK", "destination": "LHR", "departDate": "2026-10-01",
    })
    assert resp.status_code == 502
    assert resp.get_json()["code"] == "PROVIDER_ERROR"


# ------------------------------------------------------------
# Premium gating
# ------------------------------------------------------------

def test_free_user_receives_403(monkeypatch):
    import functools
    from flask import jsonify

    def deny(fn):
        @functools.wraps(fn)
        def wrapper(*args, **kwargs):
            return jsonify({
                "success": False,
                "error": "premium_required",
                "code": "PREMIUM_REQUIRED",
            }), 403
        return wrapper

    client = _load_app_with_guards(monkeypatch, deny)

    resp = client.post("/api/travel/flights/search", json={
        "origin": "JFK", "destination": "LHR", "departDate": "2026-10-01",
    })
    assert resp.status_code == 403
    body = resp.get_json()
    assert body["success"] is False
    assert body["code"] == "PREMIUM_REQUIRED"
