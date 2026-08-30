"""Functional smoke test: verifies the core Tripora happy-path still works
after the security fixes. Uses only synthetic data and the isolated test DB."""

from .helpers import (
    auth_headers,
    create_logged_in_user,
    create_trip,
    get_user_by_email,
    login,
    register,
    verify_email,
)


class TestCoreFlow:
    def test_full_trip_lifecycle(self, client):
        token = create_logged_in_user(client, name="FlowUser", email="flow@example.com")

        # /api/auth/me
        me = client.get("/api/auth/me", headers=auth_headers(token))
        assert me.status_code == 200
        assert me.get_json()["user"]["email"] == "flow@example.com"

        # generate
        resp = create_trip(
            client, token,
            destination="Kyoto",
            startDate="2026-10-01", endDate="2026-10-03",
            travelers=2, budget="moderate",
            travelStyle="balanced", interests=["food", "temples"],
        )
        assert resp.status_code == 200, resp.get_json()
        trip = resp.get_json()["trip"]
        trip_id = trip["id"]
        assert trip["destination"] == "Kyoto"
        assert trip["itinerary"]  # stub produced a non-empty itinerary

        # list
        lst = client.get("/api/trips", headers=auth_headers(token))
        assert lst.status_code == 200
        assert any(t["id"] == trip_id for t in lst.get_json()["trips"])

        # get one
        one = client.get("/api/trips/{}".format(trip_id), headers=auth_headers(token))
        assert one.status_code == 200
        assert one.get_json()["trip"]["destination"] == "Kyoto"

        # update (change destination + dates so itinerary regenerates)
        patch = client.patch(
            "/api/trips/{}".format(trip_id),
            json={
                "destination": "Osaka",
                "startDate": "2026-11-01", "endDate": "2026-11-02",
                "travelers": 1, "budget": "luxury",
                "travelStyle": "foodie", "interests": ["food"],
            },
            headers=auth_headers(token),
        )
        assert patch.status_code == 200, patch.get_json()
        assert patch.get_json()["trip"]["destination"] == "Osaka"

        # regenerate itinerary
        regen = client.post(
            "/api/trips/{}/regenerate".format(trip_id),
            headers=auth_headers(token), json={},
        )
        assert regen.status_code == 200, regen.get_json()

        # delete
        dele = client.delete("/api/trips/{}".format(trip_id), headers=auth_headers(token))
        assert dele.status_code == 200
        gone = client.get("/api/trips/{}".format(trip_id), headers=auth_headers(token))
        assert gone.status_code == 404

    def test_update_account_preferences(self, client):
        token = create_logged_in_user(client, name="PrefUser", email="pref@example.com")
        patch = client.patch(
            "/api/auth/me",
            json={"preferredLanguage": "es", "preferredCurrency": "EUR"},
            headers=auth_headers(token),
        )
        assert patch.status_code == 200, patch.get_json()
        u = patch.get_json()["user"]
        assert u["preferredLanguage"] == "es"
        assert u["preferredCurrency"] == "EUR"

    def test_resend_verification_flow(self, client):
        register(client, name="RsvUser", email="rsv@example.com")
        resp = client.post(
            "/api/auth/resend-verification", json={"email": "rsv@example.com"}
        )
        assert resp.status_code == 200, resp.get_json()
