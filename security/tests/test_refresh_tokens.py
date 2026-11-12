"""Tests for persistent sessions: rotating refresh tokens.

Covers the backend half of "stay signed in until you log out / the token is
revoked / it can no longer be renewed":

- A successful login returns both an access and a refresh token.
- ``POST /api/auth/refresh`` exchanges a valid refresh token for a fresh
  access token and a rotated refresh token; the new access token actually
  works against a protected endpoint.
- Refresh tokens are single-use: a rotated token is rejected, and a replay of
  an already-rotated token revokes the whole family (theft response).
- Expired / unknown / missing refresh tokens are rejected.
- ``POST /api/auth/logout`` revokes the refresh token server-side and is
  idempotent.
- Only the SHA-256 hash of the raw token is ever persisted.

All tokens here are synthetic and generated against the isolated in-memory
test database; no real credentials or sessions are involved.
"""

import hashlib
from datetime import datetime, timedelta

from config.database import db
from models.user_refresh_token import UserRefreshToken

from .helpers import (
    verify_email,
    auth_headers,
    create_trip_and_get_id,
    login,
    register,
)


def _login_get_tokens(client, email="alice@example.com", password="supersecret1"):
    """Register + log in and return (accessToken, refreshToken)."""
    register(client, name="Alice", email=email, password=password)
    resp = login(client, email, password)
    assert resp.status_code == 200, resp.get_json()
    body = resp.get_json()
    assert body["accessToken"]
    assert body["refreshToken"]
    verify_email(client, body["accessToken"], email)
    return body["accessToken"], body["refreshToken"]


def _refresh(client, refresh_token):
    return client.post(
        "/api/auth/refresh",
        json={"refreshToken": refresh_token},
    )


class TestLoginIssuesRefreshToken:
    def test_login_returns_both_tokens(self, client):
        _, refresh = _login_get_tokens(client)
        assert isinstance(refresh, str) and len(refresh) > 20

    def test_refresh_token_is_stored_hashed_only(self, client):
        """The raw refresh token must never be persisted verbatim."""
        _, refresh = _login_get_tokens(client)
        digest = hashlib.sha256(refresh.encode("utf-8")).hexdigest()

        row = UserRefreshToken.query.filter_by(token_hash=digest).first()
        assert row is not None
        assert UserRefreshToken.query.filter_by(token_hash=refresh).first() is None


class TestRefreshFlow:
    def test_valid_refresh_returns_new_tokens(self, client):
        _, refresh = _login_get_tokens(client)

        resp = _refresh(client, refresh)
        assert resp.status_code == 200, resp.get_json()
        body = resp.get_json()
        assert body["success"] is True
        assert body["accessToken"]
        assert body["refreshToken"]
        assert body["refreshToken"] != refresh

    def test_refreshed_access_token_works_on_protected_endpoint(self, client):
        _, refresh = _login_get_tokens(client)
        refreshed = _refresh(client, refresh).get_json()

        me = client.get(
            "/api/auth/me",
            headers=auth_headers(refreshed["accessToken"]),
        )
        assert me.status_code == 200
        assert me.get_json()["user"]["email"] == "alice@example.com"

    def test_refreshed_access_token_can_create_trip(self, client):
        """A refreshed access token is fully functional, not just /me."""
        _, refresh = _login_get_tokens(client)
        refreshed = _refresh(client, refresh).get_json()
        trip_id = create_trip_and_get_id(client, refreshed["accessToken"])
        assert isinstance(trip_id, int)


class TestRotationAndReuseDetection:
    def test_rotated_token_is_rejected(self, client):
        """After a successful refresh the old refresh token is single-use."""
        _, refresh1 = _login_get_tokens(client)
        assert _refresh(client, refresh1).status_code == 200

        assert _refresh(client, refresh1).status_code == 401

    def test_replay_revokes_the_whole_family(self, client):
        """Reusing a rotated token invalidates the replacement too (theft)."""
        _, refresh1 = _login_get_tokens(client)
        refresh2 = _refresh(client, refresh1).get_json()["refreshToken"]

        # Replaying the rotated token is rejected...
        assert _refresh(client, refresh1).status_code == 401
        # ...and the whole family is revoked.
        assert _refresh(client, refresh2).status_code == 401


class TestRefreshValidation:
    def test_missing_token_returns_400(self, client):
        resp = client.post("/api/auth/refresh", json={})
        assert resp.status_code == 400
        assert resp.get_json()["success"] is False

    def test_unknown_token_returns_401(self, client):
        resp = _refresh(client, "not-a-real-refresh-token")
        assert resp.status_code == 401
        assert resp.get_json()["success"] is False

    def test_empty_token_returns_400(self, client):
        resp = client.post("/api/auth/refresh", json={"refreshToken": ""})
        assert resp.status_code == 400

    def test_expired_token_returns_401(self, client):
        _, refresh = _login_get_tokens(client)
        digest = hashlib.sha256(refresh.encode("utf-8")).hexdigest()
        row = UserRefreshToken.query.filter_by(token_hash=digest).first()
        row.expires_at = datetime.utcnow() - timedelta(minutes=1)
        db.session.commit()

        assert _refresh(client, refresh).status_code == 401


class TestLogout:
    def test_logout_revokes_refresh_token(self, client):
        _, refresh = _login_get_tokens(client)

        out = client.post(
            "/api/auth/logout",
            json={"refreshToken": refresh},
        )
        assert out.status_code == 200
        assert out.get_json()["success"] is True

        assert _refresh(client, refresh).status_code == 401

    def test_logout_is_idempotent_and_does_not_leak(self, client):
        assert client.post(
            "/api/auth/logout", json={"refreshToken": "does-not-exist"}
        ).status_code == 200
        assert client.post("/api/auth/logout", json={}).status_code == 200

    def test_logout_does_not_affect_other_sessions(self, client):
        """Logging out one device leaves another device's family intact."""
        register(client, name="Alice", email="alice@example.com")
        first = login(client, "alice@example.com", "supersecret1").get_json()
        second = login(client, "alice@example.com", "supersecret1").get_json()

        client.post(
            "/api/auth/logout",
            json={"refreshToken": first["refreshToken"]},
        )

        assert _refresh(client, first["refreshToken"]).status_code == 401
        assert _refresh(client, second["refreshToken"]).status_code == 200
