"""Tests for the password-reset flow (forgot -> verify -> reset).

Covers the full happy path plus the security properties that matter:

- Generic responses (no account enumeration on unknown / social-only accounts).
- Codes are stored hashed, expire, and lock out after N failed attempts.
- The one-time reset token is required, expires, and is cleared after use.
- The reset code/attempt fields are wiped on a successful password change.
- The new password works for login and the old one no longer does.
"""

import logging
from datetime import datetime, timedelta

from werkzeug.security import check_password_hash

import routes.auth as auth_module
import services.email_service as email_module
from config.database import db
from models.user import User

from .helpers import (
    get_user_by_email,
    login,
    register,
)


def auth_module_hash_reset_token(token):
    from routes.auth import _hash_reset_token

    return _hash_reset_token(token)


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

    def test_delivery_failure_keeps_generic_response_and_no_active_code(
        self, client, monkeypatch, caplog
    ):
        email = "delivery-failure@example.com"
        register(client, name="Delivery", email=email, password="supersecret1")
        monkeypatch.setattr(auth_module, "send_password_reset_code", lambda *_: False)

        with caplog.at_level(logging.DEBUG):
            resp = client.post("/api/auth/forgot-password", json={"email": email})

        assert resp.status_code == 200
        assert resp.get_json()["message"] == auth_module.GENERIC_RESET_MESSAGE
        user = get_user_by_email(email)
        assert user.reset_code_hash is None
        assert email not in caplog.text


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
        assert user.reset_token_hash == auth_module_hash_reset_token(body["resetToken"])
        assert user.reset_token_expires_at > datetime.utcnow()

    def test_reset_token_and_code_are_not_logged(self, client, monkeypatch, caplog):
        email, code, _ = _setup_code(client, monkeypatch, "log-token@example.com")
        caplog.clear()

        with caplog.at_level(logging.DEBUG):
            resp = client.post(
                "/api/auth/forgot-password/verify",
                json={"email": email, "code": code},
            )

        reset_token = resp.get_json()["resetToken"]
        assert code not in caplog.text
        assert reset_token not in caplog.text
        assert email not in caplog.text


class TestPasswordResetDeliveryLogging:
    @staticmethod
    def _without_providers(monkeypatch):
        for key in (
            "MAIL_HOST",
            "MAIL_USER",
            "MAIL_PASSWORD",
            "RESEND_API_KEY",
        ):
            monkeypatch.delenv(key, raising=False)

    def test_production_without_provider_fails_without_sensitive_logs(
        self, monkeypatch, caplog
    ):
        self._without_providers(monkeypatch)
        monkeypatch.setenv("TRIPORA_ENV", "production")
        recipient = "production-recipient@example.com"
        code = "654321"

        with caplog.at_level(logging.DEBUG, logger=email_module.__name__):
            assert email_module.send_password_reset_code(recipient, code) is False

        assert recipient not in caplog.text
        assert code not in caplog.text
        assert "Email delivery unavailable; no provider configured." in caplog.text

    def test_development_simulation_never_logs_recipient_or_code(
        self, monkeypatch, caplog
    ):
        self._without_providers(monkeypatch)
        monkeypatch.setenv("TRIPORA_ENV", "development")
        recipient = "development-recipient@example.com"
        code = "123456"

        with caplog.at_level(logging.DEBUG, logger=email_module.__name__):
            assert email_module.send_password_reset_code(recipient, code) is True

        assert recipient not in caplog.text
        assert code not in caplog.text
        assert "Email delivery simulated in development" in caplog.text

    def test_smtp_failure_does_not_log_sensitive_delivery_data(
        self, monkeypatch, caplog
    ):
        monkeypatch.setenv("MAIL_HOST", "smtp.test.invalid")
        monkeypatch.setenv("MAIL_USER", "mail-user")
        monkeypatch.setenv("MAIL_PASSWORD", "mail-password")
        monkeypatch.delenv("RESEND_API_KEY", raising=False)
        recipient = "smtp-recipient@example.com"
        code = "111222"
        exception_marker = "smtp-sensitive-marker"

        def fail_smtp(*_args, **_kwargs):
            raise RuntimeError(exception_marker)

        monkeypatch.setattr(email_module, "_send_via_smtp", fail_smtp)
        with caplog.at_level(logging.DEBUG, logger=email_module.__name__):
            assert email_module.send_password_reset_code(recipient, code) is False

        assert recipient not in caplog.text
        assert code not in caplog.text
        assert exception_marker not in caplog.text
        assert "SMTP email delivery failed." in caplog.text

    def test_resend_failure_does_not_log_sensitive_delivery_data(
        self, monkeypatch, caplog
    ):
        self._without_providers(monkeypatch)
        monkeypatch.setenv("RESEND_API_KEY", "test-resend-key")
        recipient = "resend-recipient@example.com"
        code = "333444"
        exception_marker = "resend-sensitive-marker"

        def fail_resend(*_args, **_kwargs):
            raise RuntimeError(exception_marker)

        monkeypatch.setattr(email_module, "_send_via_resend", fail_resend)
        with caplog.at_level(logging.DEBUG, logger=email_module.__name__):
            assert email_module.send_password_reset_code(recipient, code) is False

        assert recipient not in caplog.text
        assert code not in caplog.text
        assert exception_marker not in caplog.text
        assert "Resend email delivery failed." in caplog.text

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

    def test_same_password_rejected_with_400(self, client, monkeypatch):
        # Regression: the reset endpoint previously raised AttributeError on
        # the misspelled `passwod_hash` attribute (R1), returning HTTP 500 for
        # every reset. Same-password must be a clean 400, not a crash.
        email = "samepw@example.com"
        old_password = "supersecret1"
        register(client, name="Pw", email=email, password=old_password)

        reset_token = _setup_token(client, monkeypatch, email, old_password)

        resp = client.post(
            "/api/auth/reset-password",
            json={"resetToken": reset_token, "password": old_password},
        )
        assert resp.status_code == 400
        body = resp.get_json()
        assert body["success"] is False
        assert body["message"] == "New password must be different from your old password."

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


class TestRecoveryCredentialRotation:
    """P1: a new request must not leave old recovery credentials usable."""

    def test_failed_delivery_invalidates_previous_code(
        self, client, monkeypatch
    ):
        email, first_code, user = _setup_code(
            client, monkeypatch, "rotate-code@example.com"
        )
        assert check_password_hash(user.reset_code_hash, first_code)

        monkeypatch.setattr(
            auth_module,
            "send_password_reset_code",
            lambda *_: False,
        )

        resp = client.post(
            "/api/auth/forgot-password", json={"email": email}
        )
        assert resp.status_code == 200
        assert resp.get_json()["message"] == auth_module.GENERIC_RESET_MESSAGE

        # The previously valid code no longer verifies.
        verify = client.post(
            "/api/auth/forgot-password/verify",
            json={"email": email, "code": first_code},
        )
        assert verify.status_code == 400
        assert (
            verify.get_json()["message"]
            == auth_module.INVALID_RESET_CODE_MESSAGE
        )

        rotated = get_user_by_email(email)
        assert rotated.reset_code_hash is None
        assert rotated.reset_code_expires_at is None
        assert rotated.reset_attempts == 0

    def test_failed_delivery_invalidates_previous_reset_token(
        self, client, monkeypatch
    ):
        email = "rotate-token@example.com"
        old_password = "supersecret1"
        reset_token = _setup_token(client, monkeypatch, email, old_password)

        monkeypatch.setattr(
            auth_module,
            "send_password_reset_code",
            lambda *_: False,
        )

        resp = client.post(
            "/api/auth/forgot-password", json={"email": email}
        )
        assert resp.status_code == 200

        user = get_user_by_email(email)
        assert user.reset_token_hash is None
        assert user.reset_token_expires_at is None

        # The previously issued token can no longer reset the password.
        reset = client.post(
            "/api/auth/reset-password",
            json={
                "resetToken": reset_token,
                "password": "a-new-password-2",
            },
        )
        assert reset.status_code == 400
        assert (
            reset.get_json()["message"]
            == auth_module.INVALID_RESET_TOKEN_MESSAGE
        )

        # The old password is unchanged and still works.
        assert login(client, email, old_password).status_code == 200

    def test_persistence_failure_after_delivery_makes_new_code_unusable(
        self, client, monkeypatch
    ):
        email, first_code, _ = _setup_code(
            client, monkeypatch, "persist-failure@example.com"
        )
        captured = {}

        def _send(_email, code):
            captured["code"] = code
            return True

        monkeypatch.setattr(
            auth_module,
            "send_password_reset_code",
            _send,
        )

        real_commit = db.session.commit
        calls = {"count": 0}

        def _flaky_commit():
            calls["count"] += 1
            if calls["count"] == 1:
                # Phase 1: credential invalidation succeeds and is committed.
                return real_commit()

            # Phase 3: persisting the newly delivered code fails.
            raise RuntimeError("simulated persistence failure")

        monkeypatch.setattr(db.session, "commit", _flaky_commit)

        resp = client.post(
            "/api/auth/forgot-password", json={"email": email}
        )
        assert resp.status_code == 200
        assert resp.get_json()["message"] == auth_module.GENERIC_RESET_MESSAGE
        assert calls["count"] >= 2

        # The emailed code was never persisted, so it cannot be used.
        verify_new = client.post(
            "/api/auth/forgot-password/verify",
            json={"email": email, "code": captured["code"]},
        )
        assert verify_new.status_code == 400

        # The old code was invalidated in phase 1 and is not restored.
        verify_old = client.post(
            "/api/auth/forgot-password/verify",
            json={"email": email, "code": first_code},
        )
        assert verify_old.status_code == 400

        user = get_user_by_email(email)
        assert user.reset_code_hash is None
        assert user.reset_code_expires_at is None
        assert user.reset_attempts == 0
        assert user.reset_token_hash is None

    def test_provider_timeout_after_acceptance_restores_nothing(
        self, client, monkeypatch, caplog
    ):
        email, first_code, _ = _setup_code(
            client, monkeypatch, "provider-timeout@example.com"
        )
        accepted = {}
        exception_marker = "provider-timeout-sensitive-marker"

        def _accept_then_timeout(_email, code):
            accepted["code"] = code
            raise TimeoutError(exception_marker)

        monkeypatch.setattr(
            auth_module,
            "send_password_reset_code",
            _accept_then_timeout,
        )

        with caplog.at_level(logging.DEBUG):
            resp = client.post(
                "/api/auth/forgot-password", json={"email": email}
            )

        assert resp.status_code == 200
        assert resp.get_json()["message"] == auth_module.GENERIC_RESET_MESSAGE

        # No old and no new credential remains active.
        verify_old = client.post(
            "/api/auth/forgot-password/verify",
            json={"email": email, "code": first_code},
        )
        assert verify_old.status_code == 400

        verify_new = client.post(
            "/api/auth/forgot-password/verify",
            json={"email": email, "code": accepted["code"]},
        )
        assert verify_new.status_code == 400

        user = get_user_by_email(email)
        assert user.reset_code_hash is None
        assert user.reset_code_expires_at is None
        assert user.reset_token_hash is None

        # Delivery failures must not log the code, recipient, or exception.
        assert accepted["code"] not in caplog.text
        assert first_code not in caplog.text
        assert email not in caplog.text
        assert exception_marker not in caplog.text


class TestResetCodeSingleUse:
    """P3: a verified reset code is consumed and cannot mint a second token."""

    def test_verified_code_cannot_issue_a_second_token(
        self, client, monkeypatch
    ):
        email, code, _ = _setup_code(
            client, monkeypatch, "single-use-code@example.com"
        )

        first = client.post(
            "/api/auth/forgot-password/verify",
            json={"email": email, "code": code},
        )
        assert first.status_code == 200
        first_token = first.get_json()["resetToken"]

        user = get_user_by_email(email)
        assert user.reset_code_hash is None
        assert user.reset_code_expires_at is None
        assert user.reset_attempts == 0

        # Submitting the same code again must not issue another token.
        second = client.post(
            "/api/auth/forgot-password/verify",
            json={"email": email, "code": code},
        )
        assert second.status_code == 400
        assert (
            second.get_json()["message"]
            == auth_module.INVALID_RESET_CODE_MESSAGE
        )

        # The token issued by the first verification is still usable.
        reset = client.post(
            "/api/auth/reset-password",
            json={
                "resetToken": first_token,
                "password": "a-new-password-2",
            },
        )
        assert reset.status_code == 200

        # And the reset token remains single-use.
        replay = client.post(
            "/api/auth/reset-password",
            json={
                "resetToken": first_token,
                "password": "anotherpass99",
            },
        )
        assert replay.status_code == 400
