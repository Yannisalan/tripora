"""Extended cross-user (IDOR) coverage for the remaining trip-scoped routes.

``test_authorization_idor.py`` and ``test_idor_user_a_b.py`` already cover the
core trip CRUD routes. This module closes the remaining gaps:

* ``POST /api/trips/<id>/swap-activity``  (mutates a trip's itinerary)
* ``GET  /api/trips/<id>/weather``        (reads a trip's destination/dates)
* ``GET  /api/trips/<id>/expenses``      (reads a trip's expense list)
* ``POST /api/trips/<id>/expenses``       (writes into a trip)

For every one of them, user B must not be able to read or mutate user A's
resource: the resource has to be reported as non-existent (404) and the
owner's copy must be unchanged afterwards.
"""

from .helpers import (
    auth_headers,
    create_logged_in_user,
    create_trip_and_get_id,
)


def _trips_for(client, token):
    resp = client.get("/api/trips", headers=auth_headers(token))
    assert resp.status_code == 200
    return resp.get_json()["trips"]


class TestSwapActivityScoping:
    """POST /api/trips/<id>/swap-activity must be owner-only."""

    def test_user_b_cannot_swap_an_activity_in_user_a_trip(self, client):
        token_a = create_logged_in_user(client, name="Alice")
        token_b = create_logged_in_user(client, name="Bob")
        trip_id_a = create_trip_and_get_id(client, token_a, destination="Paris")

        resp = client.post(
            "/api/trips/{}/swap-activity".format(trip_id_a),
            json={"day": 1, "time": "Morning"},
            headers=auth_headers(token_b),
        )
        assert resp.status_code == 404
        body = resp.get_json() or {}
        assert body.get("success") is False

        # The owner's itinerary is untouched.
        owner_trip = client.get(
            "/api/trips/{}".format(trip_id_a), headers=auth_headers(token_a)
        ).get_json()["trip"]
        first_day = owner_trip["itinerary"][0]
        morning = next(
            a for a in first_day["activities"] if a["time"] == "Morning"
        )
        assert morning["title"] == "Morning activity"

    def test_user_b_cannot_swap_into_a_trip_that_does_not_exist(self, client):
        token_b = create_logged_in_user(client, name="Bob")

        resp = client.post(
            "/api/trips/999999/swap-activity",
            json={"day": 1, "time": "Morning"},
            headers=auth_headers(token_b),
        )
        assert resp.status_code == 404

    def test_owner_can_swap_in_own_trip(self, client):
        token_a = create_logged_in_user(client, name="Alice")
        trip_id_a = create_trip_and_get_id(client, token_a, destination="Paris")

        resp = client.post(
            "/api/trips/{}/swap-activity".format(trip_id_a),
            json={"day": 1, "time": "Morning"},
            headers=auth_headers(token_a),
        )
        assert resp.status_code == 200, resp.get_json()


class TestWeatherScoping:
    """GET /api/trips/<id>/weather must be owner-only."""

    def test_user_b_cannot_read_user_a_trip_weather(self, client):
        token_a = create_logged_in_user(client, name="Alice")
        token_b = create_logged_in_user(client, name="Bob")
        trip_id_a = create_trip_and_get_id(client, token_a, destination="Paris")

        resp = client.get(
            "/api/trips/{}/weather".format(trip_id_a),
            headers=auth_headers(token_b),
        )
        assert resp.status_code == 404
        body = resp.get_json() or {}
        assert body.get("success") is False
        # No destination or forecast detail leaks through the error body.
        assert "destination" not in body
        assert "Paris" not in str(body)

    def test_user_b_cannot_read_weather_of_a_foreign_trip_id(self, client):
        token_b = create_logged_in_user(client, name="Bob")

        resp = client.get(
            "/api/trips/424242/weather",
            headers=auth_headers(token_b),
        )
        assert resp.status_code == 404


class TestTripExpenseScoping:
    """The trip-scoped expense endpoints must be owner-only."""

    def test_user_b_cannot_list_user_a_trip_expenses(self, client):
        token_a = create_logged_in_user(client, name="Alice")
        token_b = create_logged_in_user(client, name="Bob")
        trip_id_a = create_trip_and_get_id(client, token_a, destination="Paris")

        created = client.post(
            "/api/trips/{}/expenses".format(trip_id_a),
            json={
                "title": "Dinner",
                "amount": 42.5,
                "category": "food",
                "date": "2026-09-01",
            },
            headers=auth_headers(token_a),
        )
        assert created.status_code == 201, created.get_json()

        resp = client.get(
            "/api/trips/{}/expenses".format(trip_id_a),
            headers=auth_headers(token_b),
        )
        assert resp.status_code == 404
        body = resp.get_json() or {}
        assert body.get("expenses") is None
        assert "Dinner" not in str(body)

    def test_user_b_cannot_add_an_expense_to_user_a_trip(self, client):
        token_a = create_logged_in_user(client, name="Alice")
        token_b = create_logged_in_user(client, name="Bob")
        trip_id_a = create_trip_and_get_id(client, token_a, destination="Paris")

        resp = client.post(
            "/api/trips/{}/expenses".format(trip_id_a),
            json={
                "title": "Injected",
                "amount": 10,
                "category": "food",
                "date": "2026-09-01",
            },
            headers=auth_headers(token_b),
        )
        assert resp.status_code == 404

        # The owner's expense list is still empty.
        owner_view = client.get(
            "/api/trips/{}/expenses".format(trip_id_a),
            headers=auth_headers(token_a),
        )
        assert owner_view.status_code == 200
        assert owner_view.get_json().get("expenses") == []

    def test_expense_ids_cannot_be_probed_across_users(self, client):
        token_a = create_logged_in_user(client, name="Alice")
        token_b = create_logged_in_user(client, name="Bob")
        trip_id_a = create_trip_and_get_id(client, token_a, destination="Paris")

        created = client.post(
            "/api/trips/{}/expenses".format(trip_id_a),
            json={
                "title": "Museum",
                "amount": 20,
                "category": "activities",
                "date": "2026-09-01",
            },
            headers=auth_headers(token_a),
        )
        assert created.status_code == 201, created.get_json()
        expense_id = created.get_json()["expense"]["id"]

        for method, kwargs in (
            ("get", {}),
            ("patch", {"json": {"amount": 1}}),
            ("delete", {}),
        ):
            resp = getattr(client, method)(
                "/api/expenses/{}".format(expense_id),
                headers=auth_headers(token_b),
                **kwargs
            )
            assert resp.status_code == 404, method

        # Still there for the owner, with the original amount.
        owner_view = client.get(
            "/api/expenses/{}".format(expense_id),
            headers=auth_headers(token_a),
        )
        assert owner_view.status_code == 200
        assert owner_view.get_json()["expense"]["amount"] == 20


class TestTripListNeverLeaksOtherUsers:
    """The trip list is scoped to the caller, including regenerated trips."""

    def test_list_only_contains_own_trips(self, client):
        token_a = create_logged_in_user(client, name="Alice")
        token_b = create_logged_in_user(client, name="Bob")

        create_trip_and_get_id(client, token_a, destination="Paris")
        create_trip_and_get_id(client, token_b, destination="Tokyo")

        trips_b = _trips_for(client, token_b)
        assert {t["destination"] for t in trips_b} == {"Tokyo"}
        assert all(t["destination"] != "Paris" for t in trips_b)
