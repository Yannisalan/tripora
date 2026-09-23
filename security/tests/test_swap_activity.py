"""Tests for single-activity swaps (POST /api/trips/<id>/swap-activity).

The swap must replace ONLY the targeted slot, keep the rest of the trip
intact, persist server-side, refresh derived data, and never leave the
trip half-updated when the AI call fails.
"""

import routes.trips as trips_module

from .helpers import (
    auth_headers,
    create_logged_in_user,
    create_trip_and_get_id,
)


class TestSwapActivity:
    def _swap(self, client, token, trip_id, day=1, time_slot="Morning"):
        return client.post(
            "/api/trips/{}/swap-activity".format(trip_id),
            json={"day": day, "time": time_slot},
            headers=auth_headers(token),
        )

    def test_swap_replaces_only_the_target_activity(self, client):
        token = create_logged_in_user(
            client, name="SwapUser", email="swap@example.com"
        )
        trip_id = create_trip_and_get_id(
            client, token,
            destination="Paris",
            startDate="2026-09-01", endDate="2026-09-02",
        )

        resp = self._swap(client, token, trip_id, day=1, time_slot="Morning")
        assert resp.status_code == 200, resp.get_json()
        trip = resp.get_json()["trip"]

        # Target slot replaced, order and other slots untouched.
        day1 = trip["itinerary"][0]
        assert [a["time"] for a in day1["activities"]] == [
            "Morning",
            "Afternoon",
            "Evening",
        ]
        morning = next(a for a in day1["activities"] if a["time"] == "Morning")
        assert morning["title"] == "Fusee Museum Tour"
        assert morning["category"] == "Sightseeing"
        assert next(
            a for a in day1["activities"] if a["time"] == "Afternoon"
        )["title"] == "Afternoon activity"

        # Other days untouched.
        day2 = trip["itinerary"][1]
        assert any(
            a["title"] == "Morning activity" for a in day2["activities"]
        )

        # Persisted server-side.
        got = client.get(
            "/api/trips/{}".format(trip_id), headers=auth_headers(token)
        )
        saved_morning = next(
            a
            for a in got.get_json()["trip"]["itinerary"][0]["activities"]
            if a["time"] == "Morning"
        )
        assert saved_morning["title"] == "Fusee Museum Tour"

    def test_swap_failure_keeps_original_trip_unchanged(
        self, client, monkeypatch
    ):
        token = create_logged_in_user(
            client, name="SwapFailUser", email="swapfail@example.com"
        )
        trip_id = create_trip_and_get_id(
            client, token, destination="Rome",
            startDate="2026-09-01", endDate="2026-09-02",
        )

        def _boom(**kwargs):
            raise RuntimeError("swap generation failed")

        monkeypatch.setattr(trips_module, "generate_activity_swap", _boom)

        before = client.get(
            "/api/trips/{}".format(trip_id), headers=auth_headers(token)
        )

        resp = self._swap(client, token, trip_id, day=1, time_slot="Afternoon")
        assert resp.status_code == 500

        after = client.get(
            "/api/trips/{}".format(trip_id), headers=auth_headers(token)
        )
        assert (
            after.get_json()["trip"]["itinerary"]
            == before.get_json()["trip"]["itinerary"]
        )

    def test_swap_other_users_trip_is_404(self, client):
        token_a = create_logged_in_user(
            client, name="SwapOwner", email="swapowner@example.com"
        )
        trip_id = create_trip_and_get_id(
            client, token_a, destination="Berlin",
            startDate="2026-09-01", endDate="2026-09-02",
        )

        token_b = create_logged_in_user(
            client, name="SwapIntruder", email="swapintruder@example.com"
        )
        resp = self._swap(client, token_b, trip_id, day=1, time_slot="Morning")
        assert resp.status_code == 404

    def test_swap_rejects_invalid_requests(self, client):
        token = create_logged_in_user(
            client, name="SwapBad", email="swapbad@example.com"
        )
        trip_id = create_trip_and_get_id(
            client, token, destination="Lisbon",
            startDate="2026-09-01", endDate="2026-09-02",
        )

        # Unknown day -> 404 (no modification).
        assert self._swap(client, token, trip_id, day=99).status_code == 404

        # Invalid time slot -> 400 (no modification).
        resp = client.post(
            "/api/trips/{}/swap-activity".format(trip_id),
            json={"day": 1, "time": "Midnight"},
            headers=auth_headers(token),
        )
        assert resp.status_code == 400

        # Missing time slot -> 400.
        resp = client.post(
            "/api/trips/{}/swap-activity".format(trip_id),
            json={"day": 1},
            headers=auth_headers(token),
        )
        assert resp.status_code == 400

        # Trip still intact.
        current = client.get(
            "/api/trips/{}".format(trip_id), headers=auth_headers(token)
        )
        assert any(
            a["title"] == "Morning activity"
            for a in current.get_json()["trip"]["itinerary"][0]["activities"]
        )