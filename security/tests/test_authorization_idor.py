"""Broken authorization / IDOR tests (P2).

Verifies that trip resources and account data are scoped to the owning user
and can never be read, modified, or deleted by another authenticated user or
via resource-id guessing.

Expected secure behaviour for every test: a resource belonging to another
user is reported as though it does not exist (404) — never returned, never
mutated, never deleted.

All users and trips are synthetic test data created within each test.
"""

from .helpers import (
    auth_headers,
    create_logged_in_user,
    create_trip,
    create_trip_and_get_id,
)


def _trips_for(client, token):
    resp = client.get("/api/trips", headers=auth_headers(token))
    assert resp.status_code == 200
    return resp.get_json()["trips"]


class TestTripIDORRead:
    """Cross-user reads of /api/trips/<id>."""

    def test_user_b_cannot_get_user_a_trip(self, client):
        """User B requesting user A's trip id -> 404, no trip data."""
        token_a = create_logged_in_user(client, name="Alice")
        token_b = create_logged_in_user(client, name="Bob")
        trip_id_a = create_trip_and_get_id(client, token_a, destination="Paris")

        resp = client.get(
            "/api/trips/{}".format(trip_id_a), headers=auth_headers(token_b)
        )
        assert resp.status_code == 404
        assert (resp.get_json() or {}).get("success") is False

    def test_owner_can_get_own_trip(self, client):
        """The owner can always read their own trip (control group)."""
        token_a = create_logged_in_user(client, name="Alice")
        trip_id = create_trip_and_get_id(client, token_a, destination="Tokyo")
        resp = client.get(
            "/api/trips/{}".format(trip_id), headers=auth_headers(token_a)
        )
        assert resp.status_code == 200
        assert resp.get_json()["trip"]["destination"] == "Tokyo"

    def test_nonexistent_and_out_of_range_ids_return_404(self, client):
        """Non-existent / extreme / negative ids -> 404 (no crash, no leak)."""
        token_a = create_logged_in_user(client, name="Alice")
        for bogus in ("999999", "-1", "0"):
            resp = client.get(
                "/api/trips/{}".format(bogus), headers=auth_headers(token_a)
            )
            assert resp.status_code == 404


class TestTripIDORModify:
    """Cross-user modifications of /api/trips/<id>."""

    def test_user_b_cannot_update_user_a_trip(self, client):
        """User B PATCHing user A's trip -> 404; user A's trip unchanged."""
        token_a = create_logged_in_user(client, name="Alice")
        token_b = create_logged_in_user(client, name="Bob")
        trip_id_a = create_trip_and_get_id(client, token_a, destination="Paris")

        payload = {
            "destination": "HackedByBob",
            "startDate": "2026-09-01",
            "endDate": "2026-09-04",
            "travelers": 3,
            "budget": "luxury",
            "travelStyle": "relaxed",
            "interests": ["spa"],
        }
        resp = client.patch(
            "/api/trips/{}".format(trip_id_a),
            json=payload,
            headers=auth_headers(token_b),
        )
        assert resp.status_code == 404

        # Owner still sees the original, unmodified trip.
        trips = _trips_for(client, token_a)
        target = next(t for t in trips if t["id"] == trip_id_a)
        assert target["destination"] == "Paris"

    def test_user_b_cannot_regenerate_user_a_trip(self, client):
        """User B POST regenerate on user A's trip -> 404; not regenerated."""
        token_a = create_logged_in_user(client, name="Alice")
        token_b = create_logged_in_user(client, name="Bob")
        trip_id_a = create_trip_and_get_id(client, token_a, destination="Paris")

        resp = client.post(
            "/api/trips/{}/regenerate".format(trip_id_a),
            json={},
            headers=auth_headers(token_b),
        )
        assert resp.status_code == 404

        trips = _trips_for(client, token_a)
        assert any(t["id"] == trip_id_a for t in trips)


class TestTripIDORDelete:
    """Cross-user deletion of /api/trips/<id>."""

    def test_user_b_cannot_delete_user_a_trip(self, client):
        """User B DELETE on user A's trip -> 404; user A keeps the trip."""
        token_a = create_logged_in_user(client, name="Alice")
        token_b = create_logged_in_user(client, name="Bob")
        trip_id_a = create_trip_and_get_id(client, token_a, destination="Paris")

        resp = client.delete(
            "/api/trips/{}".format(trip_id_a), headers=auth_headers(token_b)
        )
        assert resp.status_code == 404

        # The trip still exists for the owner.
        trips = _trips_for(client, token_a)
        assert any(t["id"] == trip_id_a for t in trips)

    def test_owner_can_delete_own_trip(self, client):
        """The owner can delete their own trip (control group)."""
        token_a = create_logged_in_user(client, name="Alice")
        trip_id = create_trip_and_get_id(client, token_a)
        resp = client.delete(
            "/api/trips/{}".format(trip_id), headers=auth_headers(token_a)
        )
        assert resp.status_code == 200
        assert _trips_for(client, token_a) == []


class TestTripListScoping:
    """GET /api/trips must only return the authenticated user's trips."""

    def test_trips_list_is_isolated_per_user(self, client):
        """Each user's trip list contains only their own trips."""
        token_a = create_logged_in_user(client, name="Alice")
        token_b = create_logged_in_user(client, name="Bob")

        create_trip_and_get_id(client, token_a, destination="Paris")
        create_trip_and_get_id(client, token_a, destination="Tokyo")
        create_trip_and_get_id(client, token_b, destination="Delhi")

        trips_a = _trips_for(client, token_a)
        trips_b = _trips_for(client, token_b)

        assert {t["destination"] for t in trips_a} == {"Paris", "Tokyo"}
        assert {t["destination"] for t in trips_b} == {"Delhi"}


class TestAccountScoping:
    """Account management (/api/auth/me) must operate only on the caller."""

    def test_patch_me_does_not_have_cross_user_effect(self, client):
        """Updating one user's prefs must not alter another user."""
        token_a = create_logged_in_user(client, name="Alice", currency="USD")
        token_b = create_logged_in_user(client, name="Bob", currency="GBP")

        resp = client.patch(
            "/api/auth/me",
            json={"preferredCurrency": "EUR"},
            headers=auth_headers(token_a),
        )
        assert resp.status_code == 200
        assert resp.get_json()["user"]["preferredCurrency"] == "EUR"

        # Bob's currency must be untouched.
        me_b = client.get("/api/auth/me", headers=auth_headers(token_b))
        assert me_b.status_code == 200
        assert me_b.get_json()["user"]["preferredCurrency"] == "GBP"

    def test_no_foreign_user_id_field_in_me(self, client):
        """PATCH /api/auth/me ignores any injected 'id'/'user_id' field.

        The target is always taken from the JWT identity, never from the
        request body.
        """
        token_a = create_logged_in_user(
            client, name="Alice", email="alice-me@example.com"
        )
        # Attempt to change a different user's email by injecting ids.
        resp = client.patch(
            "/api/auth/me",
            json={
                "name": "Alice2",
                "id": 999999,
                "user_id": 12345,
                "email": "alice-me@example.com",
            },
            headers=auth_headers(token_a),
        )
        assert resp.status_code == 200
        assert resp.get_json()["user"]["id"] != 999999
        assert resp.get_json()["user"]["email"] == "alice-me@example.com"
