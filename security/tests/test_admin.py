"""Tests for the token-gated admin / analytics API.

Covers the auth gate, the aggregate stats endpoint, the users/trips/logs list
endpoints, and the public page-view beacon. Uses only synthetic test users.
"""

from .helpers import (
    auth_headers,
    create_logged_in_user,
)

ADMIN_TOKEN = "tripora-test-admin-token"


def admin_headers():
    return auth_headers(ADMIN_TOKEN)


# ----------------------------------------------------------------------
# Authorization gate
# ----------------------------------------------------------------------


def test_admin_requires_token(client):
    resp = client.get("/api/admin/stats")
    assert resp.status_code == 401


def test_admin_rejects_wrong_token(client):
    resp = client.get(
        "/api/admin/stats", headers=auth_headers("wrong-admin-token-here")
    )
    assert resp.status_code == 401


def test_admin_login_status(client):
    resp = client.get(
        "/api/admin/login-status", headers=auth_headers(ADMIN_TOKEN)
    )
    assert resp.status_code == 200
    assert resp.get_json()["authenticated"] is True

    resp = client.get(
        "/api/admin/login-status", headers=auth_headers("nope")
    )
    assert resp.status_code == 200
    assert resp.get_json()["authenticated"] is False


# ----------------------------------------------------------------------
# Stats
# ----------------------------------------------------------------------


def test_admin_stats_empty(client):
    resp = client.get("/api/admin/stats", headers=admin_headers())
    assert resp.status_code == 200
    data = resp.get_json()
    assert data["success"] is True
    stats = data["stats"]
    assert stats["users"]["total"] == 0
    assert stats["trips"]["total"] == 0
    assert stats["activity"]["apiRequests"] >= 0


def test_admin_stats_reflects_user_and_trip(client):
    token = create_logged_in_user(client, name="Anna")

    # Generate a trip for the user.
    trip_resp = client.post(
        "/api/trips/generate",
        json={
            "destination": "Bali",
            "startDate": "2026-10-01",
            "endDate": "2026-10-05",
            "travelers": 2,
            "budget": "moderate",
            "travelStyle": "relaxed",
            "interests": ["beach"],
        },
        headers=auth_headers(token),
    )
    assert trip_resp.status_code == 200, trip_resp.get_json()

    resp = client.get("/api/admin/stats", headers=admin_headers())
    assert resp.status_code == 200
    stats = resp.get_json()["stats"]
    assert stats["users"]["total"] == 1
    assert stats["trips"]["total"] == 1
    assert stats["topDestinations"][0]["destination"] == "Bali"
    assert stats["topDestinations"][0]["count"] == 1


# ----------------------------------------------------------------------
# Users / trips lists
# ----------------------------------------------------------------------


def test_admin_users_list(client):
    create_logged_in_user(client, name="Ben")
    resp = client.get("/api/admin/users", headers=admin_headers())
    assert resp.status_code == 200
    data = resp.get_json()
    assert data["count"] == 1
    assert data["users"][0]["name"] == "Ben"
    assert "password" not in data["users"][0]


def test_admin_trips_list(client):
    token = create_logged_in_user(client, name="Carol")
    client.post(
        "/api/trips/generate",
        json={
            "destination": "Lisbon",
            "startDate": "2026-11-01",
            "endDate": "2026-11-03",
            "travelers": 1,
            "budget": "budget",
            "travelStyle": "fast",
            "interests": ["food"],
        },
        headers=auth_headers(token),
    )
    resp = client.get("/api/admin/trips", headers=admin_headers())
    assert resp.status_code == 200
    data = resp.get_json()
    assert data["count"] == 1
    assert data["trips"][0]["destination"] == "Lisbon"


# ----------------------------------------------------------------------
# Activity log / page-view beacon
# ----------------------------------------------------------------------


def test_page_view_beacon_requires_path(client):
    resp = client.post("/api/admin/page-view", json={})
    assert resp.status_code == 400


def test_page_view_beacon_records(client):
    resp = client.post("/api/admin/page-view", json={"path": "/planner"})
    assert resp.status_code == 201
    log_id = resp.get_json()["logId"]
    assert log_id is not None

    logs = client.get(
        "/api/admin/logs?type=page_view", headers=admin_headers()
    )
    assert logs.status_code == 200
    data = logs.get_json()
    assert data["count"] >= 1
    assert any(r["id"] == log_id for r in data["logs"])


def test_admin_logs_endpoint(client):
    resp = client.get("/api/admin/logs", headers=admin_headers())
    assert resp.status_code == 200
    assert resp.get_json()["success"] is True
