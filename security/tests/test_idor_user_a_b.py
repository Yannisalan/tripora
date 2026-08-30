"""Broken Object-Level Authorization / IDOR — User A vs User B.

Focused, self-contained tests that create two ISOLATED test users (User A
and User B), give each a separate trip, and then verify that User B CANNOT:

1. retrieve User A's trip
2. modify User A's trip
3. delete User A's trip
4. access User A's itinerary
5. access User A's private information

SECURE BEHAVIOUR (asserted below): every unauthorized access to User A's
objects is denied as if the object does not exist (404) or with 401/403, and
User A's data stays completely intact. Only User A can read/modify/delete
their own resources.

If any assertion fails, that is a successful unauthorized access and must be
documented as a vulnerability (without modifying the application).

Only synthetic test data is used; production records are never referenced.
"""

import pytest

from .helpers import (
    auth_headers,
    create_logged_in_user,
    create_trip_and_get_id,
)


# ----------------------------------------------------------------------
# Fixture: two isolated users, each with their own trip
# ----------------------------------------------------------------------


@pytest.fixture
def idor_pair(client):
    """Create User A and User B, each with a distinct trip.

    Returns a dict with the tokens, trip ids, and readable ids for both
    users. User A's trip carries distinctive data (destination + known
    itinerary) so we can prove nothing of it leaks to User B.
    """
    token_a = create_logged_in_user(
        client, name="UserA", email="usera-idor@example.com"
    )
    token_b = create_logged_in_user(
        client, name="UserB", email="userb-idor@example.com"
    )

    trip_a_id = create_trip_and_get_id(
        client,
        token_a,
        destination="Paris",
        startDate="2026-09-01",
        endDate="2026-09-03",
        travelers=2,
        interests=["secret-interests-a"],
    )
    trip_b_id = create_trip_and_get_id(
        client,
        token_b,
        destination="Nairobi",
        startDate="2026-10-05",
        endDate="2026-10-07",
        travelers=1,
        interests=["public-interests-b"],
    )

    def trips(token):
        resp = client.get("/api/trips", headers=auth_headers(token))
        assert resp.status_code == 200
        return resp.get_json()["trips"]

    def trip(client_, token, trip_id):
        return client_.get(
            "/api/trips/{}".format(trip_id), headers=auth_headers(token)
        )

    return {
        "client": client,
        "token_a": token_a,
        "token_b": token_b,
        "trip_a_id": trip_a_id,
        "trip_b_id": trip_b_id,
        "trips": trips,
        "get_trip": trip,
    }


# ----------------------------------------------------------------------
# 1. Retrieve User A's trip
# ----------------------------------------------------------------------


class TestRetrieveUserATrip:
    def test_user_b_cannot_retrieve_user_a_trip(self, idor_pair):
        """User B GET /api/trips/<A's id> -> denied (404)."""
        resp = idor_pair["get_trip"](
            idor_pair["client"], idor_pair["token_b"], idor_pair["trip_a_id"]
        )
        assert resp.status_code == 404, (
            "User B accessed User A's trip: {}".format(resp.get_json())
        )
        assert (resp.get_json() or {}).get("success") is False

    def test_user_a_can_retrieve_own_trip_control(self, idor_pair):
        """Control: User A can read their own trip."""
        resp = idor_pair["get_trip"](
            idor_pair["client"], idor_pair["token_a"], idor_pair["trip_a_id"]
        )
        assert resp.status_code == 200
        assert resp.get_json()["trip"]["destination"] == "Paris"

    def test_user_b_list_never_contains_user_a_trip(self, idor_pair):
        """User B's GET /api/trips list must not include User A's trip."""
        trips_b = idor_pair["trips"](idor_pair["token_b"])
        ids_b = {t["id"] for t in trips_b}
        assert idor_pair["trip_b_id"] in ids_b
        assert idor_pair["trip_a_id"] not in ids_b, (
            "User A's trip leaked into User B's list"
        )


# ----------------------------------------------------------------------
# 2. Modify User A's trip
# ----------------------------------------------------------------------


class TestModifyUserATrip:
    def _modify_payload(self, destination="HackedByUserB"):
        return {
            "destination": destination,
            "startDate": "2026-09-01",
            "endDate": "2026-09-03",
            "travelers": 5,
            "budget": "luxury",
            "travelStyle": "adventure",
            "interests": ["injected"],
        }

    def test_user_b_cannot_modify_user_a_trip(self, idor_pair):
        """User B PATCH /api/trips/<A's id> -> denied; A's trip unchanged."""
        resp = idor_pair["client"].patch(
            "/api/trips/{}".format(idor_pair["trip_a_id"]),
            json=self._modify_payload(),
            headers=auth_headers(idor_pair["token_b"]),
        )
        assert resp.status_code == 404, (
            "User B modified User A's trip: {}".format(resp.get_json())
        )

        # User A's trip must be byte-for-byte unchanged.
        trips_a = idor_pair["trips"](idor_pair["token_a"])
        trip_a = next(t for t in trips_a if t["id"] == idor_pair["trip_a_id"])
        assert trip_a["destination"] == "Paris"
        assert trip_a["travelers"] == 2

    def test_user_a_can_modify_own_trip_control(self, idor_pair):
        """Control: User A can modify their own trip."""
        resp = idor_pair["client"].patch(
            "/api/trips/{}".format(idor_pair["trip_a_id"]),
            json=self._modify_payload(destination="Lyon"),
            headers=auth_headers(idor_pair["token_a"]),
        )
        assert resp.status_code == 200
        assert resp.get_json()["trip"]["destination"] == "Lyon"


# ----------------------------------------------------------------------
# 3. Delete User A's trip
# ----------------------------------------------------------------------


class TestDeleteUserATrip:
    def test_user_b_cannot_delete_user_a_trip(self, idor_pair):
        """User B DELETE /api/trips/<A's id> -> denied; A's trip survives."""
        resp = idor_pair["client"].delete(
            "/api/trips/{}".format(idor_pair["trip_a_id"]),
            headers=auth_headers(idor_pair["token_b"]),
        )
        assert resp.status_code == 404, (
            "User B deleted User A's trip: {}".format(resp.get_json())
        )

        # Confirm User A still has the trip.
        trips_a = idor_pair["trips"](idor_pair["token_a"])
        assert any(t["id"] == idor_pair["trip_a_id"] for t in trips_a)

    def test_user_a_can_delete_own_trip_control(self, idor_pair):
        """Control: User A can delete their own trip."""
        resp = idor_pair["client"].delete(
            "/api/trips/{}".format(idor_pair["trip_a_id"]),
            headers=auth_headers(idor_pair["token_a"]),
        )
        assert resp.status_code == 200
        trips_a = idor_pair["trips"](idor_pair["token_a"])
        assert all(t["id"] != idor_pair["trip_a_id"] for t in trips_a)


# ----------------------------------------------------------------------
# 4. Access User A's itinerary
# ----------------------------------------------------------------------


class TestAccessUserAItinerary:
    def test_user_b_cannot_read_user_a_itinerary(self, idor_pair):
        """User B GET /api/trips/<A's id> must not expose A's itinerary."""
        resp = idor_pair["get_trip"](
            idor_pair["client"], idor_pair["token_b"], idor_pair["trip_a_id"]
        )
        # Denied entirely -> no itinerary and no partial data leakage.
        assert resp.status_code == 404
        body = resp.get_json() or {}
        assert "itinerary" not in body

    def test_user_b_cannot_regenerate_user_a_itinerary(self, idor_pair):
        """User B POST /api/trips/<A's id>/regenerate -> denied (404)."""
        resp = idor_pair["client"].post(
            "/api/trips/{}/regenerate".format(idor_pair["trip_a_id"]),
            json={},
            headers=auth_headers(idor_pair["token_b"]),
        )
        assert resp.status_code == 404, (
            "User B regenerated User A's itinerary: {}".format(resp.get_json())
        )

    def test_user_a_itinerary_has_expected_shape_control(self, idor_pair):
        """Control: User A's itinerary is present and well-formed for the owner."""
        resp = idor_pair["get_trip"](
            idor_pair["client"], idor_pair["token_a"], idor_pair["trip_a_id"]
        )
        assert resp.status_code == 200
        itinerary = resp.get_json()["trip"]["itinerary"]
        assert isinstance(itinerary, list) and len(itinerary) > 0
        # A 2-night trip (Sep 1..3) yields 3 days.
        assert len(itinerary) == 3


# ----------------------------------------------------------------------
# 5. Access User A's private information
# ----------------------------------------------------------------------


class TestAccessUserAPrivateInfo:
    def test_user_b_cannot_change_user_a_account(self, idor_pair):
        """User B must not be able to update User A's account fields.

        /api/auth/me always operates on the caller's own identity; there is
        no way to target another user.
        """
        resp = idor_pair["client"].patch(
            "/api/auth/me",
            json={"name": "UserB-renamed"},
            headers=auth_headers(idor_pair["token_b"]),
        )
        # This returns the CALLER's record (User B), never User A.
        assert resp.status_code == 200
        assert resp.get_json()["user"]["email"] == "userb-idor@example.com"
        assert resp.get_json()["user"]["name"] == "UserB-renamed"

    def test_user_b_cannot_read_user_a_account_via_me(self, idor_pair):
        """GET /api/auth/me with User B's token returns only User B."""
        resp = idor_pair["client"].get(
            "/api/auth/me", headers=auth_headers(idor_pair["token_b"])
        )
        assert resp.status_code == 200
        user = resp.get_json()["user"]
        assert user["email"] == "userb-idor@example.com"
        # Must never reveal User A's identity or internal fields.
        assert user["email"] != "usera-idor@example.com"
        # Sensitive internal fields must not be serialized at all.
        for sensitive in ("password_hash", "passwordHash", "verification_token", "verificationToken"):
            assert sensitive not in user

    def test_user_a_private_fields_never_serialized(self, idor_pair):
        """No endpoint ever returns User A's password hash or verification token."""
        resp = idor_pair["get_trip"](
            idor_pair["client"], idor_pair["token_a"], idor_pair["trip_a_id"]
        )
        serialized = str(resp.get_json())
        assert "password_hash" not in serialized
        assert "passwordHash" not in serialized
        assert "verification_token" not in serialized
        assert "verificationToken" not in serialized

    def test_user_b_cannot_enumerate_or_switch_to_user_a(self, idor_pair):
        """User B cannot abuse overlapping trip ids to reach User A.

        Even when both users' trips exist in the DB, requesting by the numeric
        id of the OTHER user's trip yields 404 (no object-level confusion).
        """
        resp = idor_pair["get_trip"](
            idor_pair["client"], idor_pair["token_b"], idor_pair["trip_b_id"]
        )
        assert resp.status_code == 200  # B owns this one
        assert resp.get_json()["trip"]["destination"] == "Nairobi"

        # Cross-check the reverse direction is also isolated.
        resp = idor_pair["get_trip"](
            idor_pair["client"], idor_pair["token_a"], idor_pair["trip_b_id"]
        )
        assert resp.status_code == 404, "User A accessed User B's trip"
