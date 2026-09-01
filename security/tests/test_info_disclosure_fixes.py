"""Regression tests for the sensitive-information logging fixes.

Proves that the following previously-disclosed values are no longer written
to server logs or stdout:

- F-4 (A-1): passwords are no longer logged in the register/login debug
  payloads in ``routes/auth.py``.
- F-5 (E-5): ``config/settings.py`` no longer prints DB identifiers to
  stdout at startup.

Only synthetic test users/data are used; no real secrets.
"""

import logging

from .helpers import (
    create_logged_in_user,
    login,
    register,
)


class TestPasswordsNotLogged:
    """F-4: passwords must never appear in register/login debug payloads."""

    def test_register_password_redacted(self, client, caplog):
        secret_password = "A-very-Distinct-secret-9x!"
        email = "passwd-log-reg@example.com"
        with caplog.at_level(logging.DEBUG, logger="routes.auth"):
            register(client, name="PwReg", email=email, password=secret_password)

        log_text = caplog.text
        assert secret_password not in log_text
        # A redaction marker should appear where the password was.
        assert "[REDACTED]" in log_text

    def test_login_password_redacted(self, client, caplog):
        secret_password = "Another-Distinct-secret-7x!"
        email = "passwd-log-login@example.com"
        register(client, name="PwLogin", email=email, password=secret_password)

        with caplog.at_level(logging.DEBUG, logger="routes.auth"):
            resp = login(client, email, secret_password)
        assert resp.status_code == 200

        log_text = caplog.text
        assert secret_password not in log_text
        assert "[REDACTED]" in log_text


class TestSettingsNoStartupPrint:
    """F-5: settings.py must not print DB identifiers at startup."""

    def test_settings_module_has_no_db_print(self):
        import inspect
        from config import settings

        src = inspect.getsource(settings)
        # The diagnostic print block that leaked DB user/host/port/name to
        # stdout must be gone.
        assert "========== DATABASE CONFIG ==========" not in src
        assert 'print("DB_USER:"' not in src
        assert 'print("DB_HOST:"' not in src
