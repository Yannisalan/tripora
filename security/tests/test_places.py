"""Tests for the travel-map geocoding + routing API.

The real Nominatim / OSRM upstreams are NEVER called here: the module-level
``_geo_geocode_via_nominatim`` / ``_geo_route_via_osrm`` functions are patched,
keeping the suite hermetic. The tests verify auth, validation, the cache
behaviour (hits and misses both cache), and graceful degradation when an
upstream fails.
"""

import pytest

import routes.places as places_module
from config.database import db
from models.place_coordinate import PlaceCoordinate

from .helpers import auth_headers, create_logged_in_user

PARIS = {
    "name": "Paris",
    "display_name": "Paris, France",
    "latitude": 48.85341,
    "longitude": 2.3488,
}


class TestGeocode:
    def test_requires_auth(self, client):
        resp = client.get("/api/places/geocode?query=Paris")
        assert resp.status_code == 401

    def test_empty_query_rejected(self, client):
        token = create_logged_in_user(client, name="MapA", email="mapa@example.com")
        resp = client.get("/api/places/geocode?query=", headers=auth_headers(token))
        assert resp.status_code == 400

    def test_too_long_query_rejected(self, client):
        token = create_logged_in_user(client, name="MapB", email="mapb@example.com")
        resp = client.get(
            "/api/places/geocode?query={}".format("x" * 300),
            headers=auth_headers(token),
        )
        assert resp.status_code == 400

    def test_geocodes_and_caches(self, client, monkeypatch):
        calls = []

        def fake_geocode(query):
            calls.append(query)
            return dict(PARIS)

        monkeypatch.setattr(places_module, "_geo_geocode_via_nominatim", fake_geocode)
        token = create_logged_in_user(client, name="MapC", email="mapc@example.com")

        resp = client.get(
            "/api/places/geocode?query=Paris", headers=auth_headers(token)
        )
        assert resp.status_code == 200
        body = resp.get_json()
        assert body["success"] is True
        assert body["geocoded"] is True
        coord = body["coordinate"]
        assert round(coord["latitude"], 4) == 48.8534
        assert round(coord["longitude"], 4) == 2.3488

        # Same normalized query second time -> served from cache.
        resp2 = client.get(
            "/api/places/geocode?query=  paris  ", headers=auth_headers(token)
        )
        assert resp2.status_code == 200
        assert resp2.get_json()["geocoded"] is True
        assert len(calls) == 1

    def test_miss_is_cached(self, client, monkeypatch):
        calls = []

        def fake_geocode(query):
            calls.append(query)
            return None

        monkeypatch.setattr(places_module, "_geo_geocode_via_nominatim", fake_geocode)
        token = create_logged_in_user(client, name="MapD", email="mapd@example.com")

        resp = client.get(
            "/api/places/geocode?query=nonexistent-place-xyz",
            headers=auth_headers(token),
        )
        assert resp.status_code == 200
        body = resp.get_json()
        assert body["geocoded"] is False
        assert body["coordinate"] is None

        # A repeated miss must NOT hit the upstream again.
        resp2 = client.get(
            "/api/places/geocode?query=nonexistent-place-xyz",
            headers=auth_headers(token),
        )
        assert resp2.get_json()["geocoded"] is False
        assert len(calls) == 1

    def test_upstream_error_degrades_gracefully(self, client, monkeypatch):
        def boom(query):
            raise RuntimeError("nominatim down")

        monkeypatch.setattr(places_module, "_geo_geocode_via_nominatim", boom)
        token = create_logged_in_user(client, name="MapE", email="mape@example.com")

        resp = client.get(
            "/api/places/geocode?query=Paris", headers=auth_headers(token)
        )
        assert resp.status_code == 503
        assert resp.get_json()["success"] is False


class TestRoute:
    def test_requires_auth(self, client):
        resp = client.get("/api/places/route")
        assert resp.status_code == 401

    def test_routes_and_returns_lat_lng_pairs(self, client, monkeypatch):
        fake_polyline = [
            [48.8566, 2.3522],
            [48.8570, 2.3526],
            [48.8590, 2.3530],
        ]

        monkeypatch.setattr(
            places_module, "_geo_route_via_osrm", lambda *a: fake_polyline
        )
        token = create_logged_in_user(client, name="MapF", email="mapf@example.com")

        resp = client.get(
            "/api/places/route?from_lat=48.8566&from_lng=2.3522"
            "&to_lat=48.8590&to_lng=2.3530",
            headers=auth_headers(token),
        )
        assert resp.status_code == 200
        body = resp.get_json()
        assert body["success"] is True
        assert body["routed"] is True
        assert body["coordinates"] == fake_polyline

    def test_upstream_failure_returns_empty_route(self, client, monkeypatch):
        def boom(*args):
            raise RuntimeError("osrm down")

        monkeypatch.setattr(places_module, "_geo_route_via_osrm", boom)
        token = create_logged_in_user(client, name="MapG", email="mapg@example.com")

        resp = client.get(
            "/api/places/route?from_lat=1&from_lng=1&to_lat=2&to_lng=2",
            headers=auth_headers(token),
        )
        # The map keeps working without a polyline (200, not 500).
        assert resp.status_code == 200
        body = resp.get_json()
        assert body["routed"] is False
        assert body["coordinates"] == []

    def test_invalid_coordinates_rejected(self, client):
        token = create_logged_in_user(client, name="MapH", email="maph@example.com")
        resp = client.get(
            "/api/places/route?from_lat=999&from_lng=1&to_lat=2&to_lng=2",
            headers=auth_headers(token),
        )
        assert resp.status_code == 400

        resp = client.get(
            "/api/places/route?from_lat=abc&from_lng=1&to_lat=2&to_lng=2",
            headers=auth_headers(token),
        )
        assert resp.status_code == 400