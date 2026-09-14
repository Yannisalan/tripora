"""Tests for the password-reset flow (forgot -> verify -> reset).

Covers the full happy path plus the security properties that matter:

- Generic responses (no account enumeration on unknown / social-only accounts).
- Codes are stored hashed, expire, and lock out after N failed attempts.
- The one-time reset token is required, expires, and is cleared after use.
- The reset code/attempt fields are wiped on a successful password change.
- The new password works for login and the old one no longer does.
"""

from datetime import datetime, timedelta

from werkzeug.security import check_password_hash

import routes.auth as auth_module
from config.database import db
from models.user import User

from .helpers import (
    get_user_by_email,
    login,
    register,
)


def _capture_email(monkeypatch):
    """Stub the email sender and capture (recipient, code) for assertions."""
    captured = {}

    def _fake_send(email, code):
        captured["email"] = email
        captured["code"] = code
        return True

    monkeypatch.setattr(auth_module, "send_password_reset_code", _fake_send)
    return captured


def _setup_code(client, monkeypatch, email, password="supersecret1"):
    """Register a user, request a reset code, return (email, code, user)."""
    captured = _capture_email(monkeypatch)
    register(client, name="ResetUser", email=email, password=password)

    resp = client.post(
        "/api/auth/forgot-password",
        json={"email": email},
    )
    assert resp.status_code == 200, resp.get_json()

    user = get_user_by_email(email)
    return captured["email"], captured["code"], user


def _setup_token(client, monkeypatch, email, password="supersecret1"):
    """Run forgot+verify and return the one-time reset token."""
    _, code, _ = _setup_code(client, monkeypatch, email, password)
    resp = client.post(
        "/api/auth/forgot-password/verify",
        json={"email": email, "code": code},
    )
    assert resp.status_code == 200, resp.get_json()
    return resp.get_json()["resetToken"]


class TestForgotPassword:
    def test_missing_email_returns_400(self, client):
        resp = client.post("/api/auth/forgot-password", json={})
        assert resp.status_code == 400
        body = resp.get_json()
        assert body["success"] is False

    def test_unknown_email_gets_generic_success(self, client, monkeypatch):
        captured = _capture_email(monkeypatch)
        resp = client.post(
            "/api/auth/forgot-password",
            json={"email": "missing@example.com"},
        )
        assert resp.status_code == 200
        body = resp.get_json()
        assert body["success"] is True
        # No email is sent for unknown accounts and the response does not
        # reveal whether the account exists.
        assert "email" not in captured
        assert body["message"] == auth_module.GENERIC_RESET_MESSAGE

    def test_code_looks_uniform_across_existing_and_missing(self, client, monkeypatch):
        """Both paths must produce indistinguishable generic success bodies."""
        register(client, name="A", email="a@example.com", password="supersecret1")
        captured = _capture_email(monkeypatch)
        resp_existing = client.post(
            "/api/auth/forgot-password", json={"email": "a@example.com"}
        )
        resp_missing = client.post(
            "/api/auth/forgot-password", json={"email": "b@example.com"}
        )
        assert resp_existing.status_code == resp_missing.status_code == 200
        assert (
            resp_existing.get_json() == resp_missing.get_json()
        )

    def test_code_is_sent_and_stored_hashed(self, client, monkeypatch):
        email, code, user = _setup_code(
            client, monkeypatch, "reset1@example.com"
        )
        assert email == "reset1@example.com"
        assert len(code) == 6
        assert code.isdigit()
        # Stored as a hash, never plaintext.
        assert user.reset_code_hash != code
        assert check_password_hash(user.reset_code_hash, code)
        assert user.reset_code_expires_at > datetime.utcnow()
        assert user.reset_code_expires_at <= datetime.utcnow() + timedelta(
            minutes=auth_module.RESET_CODE_LIFETIME_MINUTES
        )
        assert user.reset_attempts == 0

    def test_requesting_new_code_rotates_old_code(self, client, monkeypatch):
        email, first_code, user = _setup_code(
            client, monkeypatch, "reset2@example.com"
        )
        assert check_password_hash(user.reset_code_hash, first_code)

        _capture_email(monkeypatch)
        resp = client.post(
            "/api/auth/forgot-password", json={"email": email}
        )
        assert resp.status_code == 200
        user2 = get_user_by_email(email)
        # The old code no longer verifies.
        assert not check_password_hash(user2.reset_code_hash, first_code)

    def test_social_only_account_gets_generic_response_and_no_email(self, app, client, monkeypatch):
        # A social-only account has no password to reset.
        with app.app_context():
            user = User(
                name="Social",
                email="socialonly@example.com",
                password_hash=None,
                auth_provider="google",
            )
            db.session.add(user)
            db.session.commit()

        captured = _capture_email(monkeypatch)
        resp = client.post(
            "/api/auth/forgot-password",
            json={"email": "socialonly@example.com"},
        )
        assert resp.status_code == 200
        assert resp.get_json()["message"] == auth_module.GENERIC_RESET_MESSAGE
        assert "email" not in captured


class TestVerifyResetCode:
    def test_correct_code_returns_reset_token(self, client, monkeypatch):
        email, code, _ = _setup_code(
            client, monkeypatch, "verify1@example.com"
        )
        resp = client.post(
            "/api/auth/forgot-password/verify",
            json={"email": email, "code": code},
        )
        assert resp.status_code == 200
        body = resp.get_json()
        assert body["success"] is True
        assert len(body["resetToken"]) >= 20

        user = get_user_by_email(email)
        assert user.reset_attempts == 0
        assert user.reset_token_hash is not None
        # Token is stored hashed.
        assert check_password_hash(user.reset_token_hash, body["resetToken"])
        assert user.reset_token_expires_at > datetime.utcnow()

    def test_wrong_code_increments_attempts(self, client, monkeypatch):
        email, _, _ = _setup_code(client, monkeypatch, "verify2@example.com")
        for _ in range(3):
            resp = client.post(
                "/api/auth/forgot-password/verify",
                json={"email": email, "code": "000000"},
            )
            assert resp.status_code == 400
            assert resp.get_json()["message"] == auth_module.INVALID_RESET_CODE_MESSAGE

        user = get_user_by_email(email)
        assert user.reset_attempts == 3

    def test_attempts_lock_out_even_with_correct_code(self, client, monkeypatch):
        email, code, _ = _setup_code(client, monkeypatch, "verify3@example.com")
        # Burn all attempts with wrong codes.
        for _ in range(auth_module.RESET_MAX_ATTEMPTS):
            client.post(
                "/api/auth/forgot-password/verify",
                json={"email": email, "code": "000000"},
            )
        # The real code is now refused too.
        resp = client.post(
            "/api/auth/forgot-password/verify",
            json={"email": email, "code": code},
        )
        assert resp.status_code == 400
        assert resp.get_json()["message"] == auth_module.INVALID_RESET_CODE_MESSAGE
        # After lockout the code fields are wiped, forcing a fresh request.
        user = get_user_by_email(email)
        assert user.reset_code_hash is None
        assert user.reset_attempts == 0

    def test_expired_code_rejected(self, client, monkeypatch):
        email, code, user = _setup_code(
            client, monkeypatch, "verify4@example.com"
        )
        user.reset_code_expires_at = datetime.utcnow() - timedelta(minutes=1)
        db.session.commit()

        resp = client.post(
            "/api/auth/forgot-password/verify",
            json={"email": email, "code": code},
        )
        assert resp.status_code == 400

    def test_unknown_email_rejected(self, client, monkeypatch):
        resp = client.post(
            "/api/auth/forgot-password/verify",
            json={"email": "nope@example.com", "code": "123456"},
        )
        assert resp.status_code == 400

    def test_missing_fields_rejected(self, client, monkeypatch):
        resp = client.post("/api/auth/forgot-password/verify", json={})
        assert resp.status_code == 400


class TestResetPassword:
    def test_reset_changes_password(self, client, monkeypatch):
        email = "pwreset@example.com"
        old_password = "supersecret1"
        new_password = "a-new-password-2"
        register(client, name="Pw", email=email, password=old_password)

        reset_token = _setup_token(client, monkeypatch, email, old_password)

        resp = client.post(
            "/api/auth/reset-password",
            json={"resetToken": reset_token, "password": new_password},
        )
        assert resp.status_code == 200

        # Old password fails, new password works.
        assert login(client, email, old_password).status_code == 401
        resp = login(client, email, new_password)
        assert resp.status_code == 200
        assert resp.get_json()["accessToken"]

        # All reset fields are cleared.
        user = get_user_by_email(email)
        assert user.reset_code_hash is None
        assert user.reset_code_expires_at is None
        assert user.reset_token_hash is None
        assert user.reset_token_expires_at is None
        assert user.reset_attempts == 0

    def test_reset_token_single_use(self, client, monkeypatch):
        email = "onetime@example.com"
        reset_token = _setup_token(client, monkeypatch, email)

        client.post(
            "/api/auth/reset-password",
            json={"resetToken": reset_token, "password": "freshpass1234"},
        )
        # Reusing the token fails and does not overwrite the new password.
        resp = client.post(
            "/api/auth/reset-password",
            json={"resetToken": reset_token, "password": "anotherpass99"},
        )
        assert resp.status_code == 400
        user = get_user_by_email(email)
        assert user.password_hash is not None
        assert user.reset_token_hash is None

    def test_short_password_rejected(self, client, monkeypatch):
        reset_token = _setup_token(client, monkeypatch, "shortpass@example.com")
        resp = client.post(
            "/api/auth/reset-password",
            json={"resetToken": reset_token, "password": "short"},
        )
        assert resp.status_code == 400

    def test_garbage_token_rejected(self, client, monkeypatch):
        resp = client.post(
            "/api/auth/reset-password",
            json={"resetToken": "junk-token", "password": "validpass123"},
        )
        assert resp.status_code == 400

    def test_missing_token_or_password_rejected(self, client):
        resp = client.post(
            "/api/auth/reset-password",
            json={"password": "validpass123"},
        )
        assert resp.status_code == 400

        resp = client.post(
            "/api/auth/reset-password",
            json={"resetToken": "abc"},
        )
        assert resp.status_code == 400

    def test_expired_token_rejected(self, client, monkeypatch):
        email = "expiredtoken@example.com"
        reset_token = _setup_token(client, monkeypatch, email)
        user = get_user_by_email(email)
        user.reset_token_expires_at = datetime.utcnow() - timedelta(minutes=1)
        db.session.commit()

        resp = client.post(
            "/api/auth/reset-password",
            json={"resetToken": reset_token, "password": "a-new-password-2"},
        )
        assert resp.status_code == 400