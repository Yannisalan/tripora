"""Tests for the Smart Trip Expense Tracker API.

Covers the create/list/get/update/delete life cycle, date/currency/category
validation, ownership isolation (IDOR) between users, and the numeric trip
budget that backs the remaining-budget math.
"""

from .helpers import (
    auth_headers,
    create_logged_in_user,
    create_trip_and_get_id,
)

# sample payload for a valid expense
EXPENSE_PAYLOAD = {
    "amount": 42.5,
    "currency": "USD",
    "category": "food",
    "description": "Dinner",
    "date": "2026-09-02",
    "paymentMethod": "card",
}


def _create(client, token, trip_id, **overrides):
    payload = dict(EXPENSE_PAYLOAD)
    payload.update(overrides)
    return client.post(
        "/api/trips/{}/expenses".format(trip_id),
        json=payload,
        headers=auth_headers(token),
    )


def _create_and_get_id(client, token, trip_id, **overrides):
    resp = _create(client, token, trip_id, **overrides)
    body = resp.get_json()
    assert resp.status_code == 201, body
    return body["expense"]["id"], resp


class TestExpenseLifecycle:
    def test_create_list_get_update_delete(self, client):
        alice = create_logged_in_user(client, name="ExpAlice", email="expalice@example.com")
        trip_id = create_trip_and_get_id(client, alice)

        exp_id, resp = _create_and_get_id(client, alice, trip_id)
        created = resp.get_json()["expense"]
        assert created["tripId"] == trip_id
        assert created["amount"] == 42.5
        assert created["currency"] == "USD"
        assert created["category"] == "food"
        assert created["date"] == "2026-09-02"
        assert created["paymentMethod"] == "card"
        assert created["description"] == "Dinner"

        # list
        lst = client.get(
            "/api/trips/{}/expenses".format(trip_id),
            headers=auth_headers(alice),
        )
        assert lst.status_code == 200
        body = lst.get_json()
        assert body["success"] is True
        assert body["count"] == 1
        assert body["expenses"][0]["id"] == exp_id
        assert body["budgetAmount"] is None  # no numeric budget yet
        assert body["budgetCurrency"] == "USD"

        # get single
        got = client.get(
            "/api/expenses/{}".format(exp_id),
            headers=auth_headers(alice),
        )
        assert got.status_code == 200
        assert got.get_json()["expense"]["amount"] == 42.5

        # update (partial)
        upd = client.patch(
            "/api/expenses/{}".format(exp_id),
            json={"amount": 55.0, "category": "transport"},
            headers=auth_headers(alice),
        )
        assert upd.status_code == 200
        updated = upd.get_json()["expense"]
        assert updated["amount"] == 55.0
        assert updated["category"] == "transport"
        # untouched fields preserved
        assert updated["currency"] == "USD"

        # delete
        dele = client.delete(
            "/api/expenses/{}".format(exp_id),
            headers=auth_headers(alice),
        )
        assert dele.status_code == 200

        lst = client.get(
            "/api/trips/{}/expenses".format(trip_id),
            headers=auth_headers(alice),
        )
        assert lst.get_json()["count"] == 0

    def test_defaults_currency_and_payment_method(self, client):
        alice = create_logged_in_user(client, name="ExpDef", email="expdef@example.com")
        trip_id = create_trip_and_get_id(client, alice)

        resp = _create(
            client, alice, trip_id,
            amount=20, description=None, paymentMethod=None, currency=None,
        )
        assert resp.status_code == 201
        expense = resp.get_json()["expense"]
        assert expense["currency"] == "USD"
        assert expense["paymentMethod"] == "other"

    def test_accepts_numeric_string_amount_and_day_boundary(self, client):
        alice = create_logged_in_user(client, name="ExpNum", email="expnum@example.com")
        trip_id = create_trip_and_get_id(client, alice)

        resp = _create(client, alice, trip_id, amount="10.50")
        assert resp.status_code == 201
        assert resp.get_json()["expense"]["amount"] == 10.5

        # today's date is allowed
        from datetime import date
        resp = _create(client, alice, trip_id, amount=5.0, date=date.today().isoformat())
        assert resp.status_code == 201


class TestExpenseValidation:
    def _trip(self, client):
        alice = create_logged_in_user(client, name="ExpVal", email="expval@example.com")
        return alice, create_trip_and_get_id(client, alice)

    def test_amount_required(self, client):
        token, trip = self._trip(client)
        resp = _create(client, token, trip, amount=None)
        assert resp.status_code == 400

    def test_negative_and_zero_amount_rejected(self, client):
        token, trip = self._trip(client)
        assert _create(client, token, trip, amount=-5).status_code == 400
        assert _create(client, token, trip, amount=0).status_code == 400

    def test_non_numeric_amount_rejected(self, client):
        token, trip = self._trip(client)
        resp = _create(client, token, trip, amount="abc")
        assert resp.status_code == 400

    def test_invalid_category_rejected(self, client):
        token, trip = self._trip(client)
        resp = _create(client, token, trip, category="crypto")
        assert resp.status_code == 400

    def test_invalid_currency_rejected(self, client):
        token, trip = self._trip(client)
        resp = _create(client, token, trip, currency="XXX")
        assert resp.status_code == 400

    def test_future_date_rejected(self, client):
        token, trip = self._trip(client)
        from datetime import date, timedelta
        future = (date.today() + timedelta(days=1)).isoformat()
        resp = _create(client, token, trip, date=future)
        assert resp.status_code == 400

    def test_malformed_date_rejected(self, client):
        token, trip = self._trip(client)
        resp = _create(client, token, trip, date="not-a-date")
        assert resp.status_code == 400

    def test_trip_not_found_for_expense(self, client):
        alice = create_logged_in_user(client, name="ExpNoTrip", email="expnotrip@example.com")
        resp = _create(client, alice, 999999, amount=10)
        assert resp.status_code == 404


class TestExpenseOwnership:
    def test_bob_cannot_see_or_touch_alice_expenses(self, client):
        alice = create_logged_in_user(client, name="ExpAlice2", email="expalice2@example.com")
        bob = create_logged_in_user(client, name="ExpBob", email="expbob@example.com")

        trip_id = create_trip_and_get_id(client, alice)
        exp_id, _ = _create_and_get_id(client, alice, trip_id)

        # Bob cannot list Alice's trip expenses.
        resp = client.get(
            "/api/trips/{}/expenses".format(trip_id),
            headers=auth_headers(bob),
        )
        assert resp.status_code == 404

        # Bob cannot create against Alice's trip.
        assert _create(client, bob, trip_id).status_code == 404

        # Bob cannot read / update / delete Alice's expense.
        assert client.get(
            "/api/expenses/{}".format(exp_id),
            headers=auth_headers(bob),
        ).status_code == 404

        assert client.patch(
            "/api/expenses/{}".format(exp_id),
            json={"amount": 1}, headers=auth_headers(bob),
        ).status_code == 404

        assert client.delete(
            "/api/expenses/{}".format(exp_id),
            headers=auth_headers(bob),
        ).status_code == 404

    def test_expense_requires_auth(self, client):
        resp = client.get("/api/trips/1/expenses")
        assert resp.status_code == 401
        resp = client.post("/api/trips/1/expenses", json=EXPENSE_PAYLOAD)
        assert resp.status_code == 401


class TestBudgetAmount:
    def test_trip_budget_amount_roundtrips_through_patch(self, client):
        alice = create_logged_in_user(client, name="ExpBdg", email="expbdg@example.com")
        trip_id = create_trip_and_get_id(client, alice)

        # PATCH the full trip payload, adding a numeric budget.
        resp = client.patch(
            "/api/trips/{}".format(trip_id),
            json={
                "destination": "Paris",
                "startDate": "2026-09-01",
                "endDate": "2026-09-04",
                "travelers": 2,
                "budget": "moderate",
                "budgetAmount": 1500.00,
                "travelStyle": "balanced",
                "interests": ["food", "culture"],
            },
            headers=auth_headers(alice),
        )
        assert resp.status_code == 200, resp.get_json()
        assert resp.get_json()["trip"]["budgetAmount"] == 1500.0

        # The expense list reflects the numeric budget for remaining math.
        lst = client.get(
            "/api/trips/{}/expenses".format(trip_id),
            headers=auth_headers(alice),
        )
        assert lst.status_code == 200
        assert lst.get_json()["budgetAmount"] == 1500.0

    def test_invalid_budget_amount_rejected(self, client):
        alice = create_logged_in_user(client, name="ExpBdg2", email="expbdg2@example.com")
        trip_id = create_trip_and_get_id(client, alice)

        resp = client.patch(
            "/api/trips/{}".format(trip_id),
            json={
                "destination": "Paris",
                "startDate": "2026-09-01",
                "endDate": "2026-09-04",
                "travelers": 2,
                "budget": "moderate",
                "budgetAmount": -50,
                "travelStyle": "balanced",
                "interests": ["food"],
            },
            headers=auth_headers(alice),
        )
        assert resp.status_code == 400
        assert resp.get_json()["message"] == "Budget amount must be a positive number."

    def test_generate_accepts_budget_amount(self, client):
        alice = create_logged_in_user(client, name="ExpBdg3", email="expbdg3@example.com")
        resp = client.post(
            "/api/trips/generate",
            json={
                "destination": "Rome",
                "startDate": "2026-10-01",
                "endDate": "2026-10-05",
                "travelers": 2,
                "budget": "luxury",
                "budgetAmount": 5000,
                "travelStyle": "relaxed",
                "interests": ["history"],
            },
            headers=auth_headers(alice),
        )
        assert resp.status_code == 200, resp.get_json()
        assert resp.get_json()["trip"]["budgetAmount"] == 5000.0