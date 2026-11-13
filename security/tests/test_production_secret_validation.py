"""F6 - Production startup validation for weak/missing security secrets.

In production (RENDER=true) the app must REFUSE to start when a critical
authentication secret is missing or too weak, rather than merely logging a
warning. Outside production the historical warn-only behaviour is preserved so
development, staging and this test suite are never bricked.

Rules under test:
  * JWT_SECRET_KEY: always required, >= 32 chars (ignoring surrounding
    whitespace); missing / empty / whitespace-only / short all fail.
  * ADMIN_API_TOKEN: the shared legacy-admin credential. Mandatory and strong
    only while ADMIN_LEGACY_TOKEN_ENABLED is true (the single code path that
    accepts it, routes/admin.py). Dead config -- and therefore not validated --
    when the legacy path is disabled.
  * Secret VALUES never appear in logs or the raised exception.

Mapping to the brief: A/B valid, C/D short, E/F missing, G empty+whitespace,
H RENDER=true enforcement, I RENDER=false dev behaviour, J test-env compat.
"""

import pytest

import config.settings as settings_mod
import app as app_module
from app import (
    ConfigurationError,
    _validate_production_secrets,
    _is_strong_secret,
    MIN_SECRET_LENGTH,
)

STRONG = "x" * MIN_SECRET_LENGTH          # exactly 32 non-whitespace chars
STRONGER = "k" * (MIN_SECRET_LENGTH + 16)
SHORT = "y" * (MIN_SECRET_LENGTH - 1)     # 31 chars
WHITESPACE = "   " * MIN_SECRET_LENGTH    # whitespace-only, 96 chars


def _configure(monkeypatch, *, render, jwt, admin, legacy=True):
    """Set the RENDER flag and the three relevant Config values for one case."""
    if render is None:
        monkeypatch.delenv("RENDER", raising=False)
    else:
        monkeypatch.setenv("RENDER", render)
    monkeypatch.setattr(settings_mod.Config, "JWT_SECRET_KEY", jwt)
    monkeypatch.setattr(settings_mod.Config, "ADMIN_API_TOKEN", admin)
    monkeypatch.setattr(
        settings_mod.Config, "ADMIN_LEGACY_TOKEN_ENABLED", legacy)


# ----------------------------------------------------------------------
# Unit: the strength predicate
# ----------------------------------------------------------------------

class TestStrengthPredicate:
    def test_none_is_weak(self):
        assert _is_strong_secret(None) is False

    def test_empty_is_weak(self):
        assert _is_strong_secret("") is False

    def test_whitespace_only_is_weak(self):
        assert _is_strong_secret(WHITESPACE) is False

    def test_short_is_weak(self):
        assert _is_strong_secret(SHORT) is False

    def test_exactly_min_is_strong(self):
        assert _is_strong_secret(STRONG) is True


# ----------------------------------------------------------------------
# H + A/B: RENDER=true enforcement, valid configurations pass
# ----------------------------------------------------------------------

class TestProductionValidConfig:
    def test_valid_jwt_and_admin_with_legacy_enabled_passes(self, monkeypatch):
        _configure(monkeypatch, render="true", jwt=STRONGER, admin=STRONG,
                   legacy=True)
        _validate_production_secrets()  # must not raise

    def test_valid_jwt_with_legacy_disabled_passes_without_admin(self, monkeypatch):
        # Legacy admin path off -> ADMIN_API_TOKEN is dead config, not required.
        _configure(monkeypatch, render="true", jwt=STRONGER, admin="",
                   legacy=False)
        _validate_production_secrets()  # must not raise

    def test_render_true_case_insensitive(self, monkeypatch):
        _configure(monkeypatch, render="TRUE", jwt=SHORT, admin=STRONG)
        with pytest.raises(ConfigurationError):
            _validate_production_secrets()


# ----------------------------------------------------------------------
# C/E/G: JWT secret failures in production
# ----------------------------------------------------------------------

class TestProductionJwtFailures:
    @pytest.mark.parametrize("bad", [None, "", WHITESPACE, SHORT])
    def test_bad_jwt_refuses_startup(self, monkeypatch, bad):
        _configure(monkeypatch, render="true", jwt=bad, admin=STRONG)
        with pytest.raises(ConfigurationError) as ei:
            _validate_production_secrets()
        assert "JWT_SECRET_KEY" in str(ei.value)

    def test_exception_never_contains_the_secret_value(self, monkeypatch):
        secret = "s3cr3t-but-way-too-short"
        _configure(monkeypatch, render="true", jwt=secret, admin=STRONG)
        with pytest.raises(ConfigurationError) as ei:
            _validate_production_secrets()
        assert secret not in str(ei.value)


# ----------------------------------------------------------------------
# D/F: admin token failures (conditional on the legacy path)
# ----------------------------------------------------------------------

class TestProductionAdminTokenFailures:
    @pytest.mark.parametrize("bad", [None, "", WHITESPACE, SHORT])
    def test_bad_admin_token_refuses_when_legacy_enabled(self, monkeypatch, bad):
        _configure(monkeypatch, render="true", jwt=STRONGER, admin=bad,
                   legacy=True)
        with pytest.raises(ConfigurationError) as ei:
            _validate_production_secrets()
        assert "ADMIN_API_TOKEN" in str(ei.value)

    @pytest.mark.parametrize("bad", [None, "", SHORT])
    def test_bad_admin_token_ignored_when_legacy_disabled(self, monkeypatch, bad):
        _configure(monkeypatch, render="true", jwt=STRONGER, admin=bad,
                   legacy=False)
        _validate_production_secrets()  # dead config -> must not raise

    def test_admin_exception_never_contains_the_secret_value(self, monkeypatch):
        secret = "admin-token-too-short-xx"
        _configure(monkeypatch, render="true", jwt=STRONGER, admin=secret,
                   legacy=True)
        with pytest.raises(ConfigurationError) as ei:
            _validate_production_secrets()
        assert secret not in str(ei.value)

    def test_both_bad_are_reported_together(self, monkeypatch):
        _configure(monkeypatch, render="true", jwt=SHORT, admin=SHORT,
                   legacy=True)
        with pytest.raises(ConfigurationError) as ei:
            _validate_production_secrets()
        msg = str(ei.value)
        assert "JWT_SECRET_KEY" in msg and "ADMIN_API_TOKEN" in msg


# ----------------------------------------------------------------------
# I: non-production warn-only behaviour (never fatal)
# ----------------------------------------------------------------------

class TestNonProductionIsWarnOnly:
    @pytest.mark.parametrize("render", [None, "false", "0", "no"])
    def test_weak_secrets_do_not_raise_outside_production(self, monkeypatch, render):
        _configure(monkeypatch, render=render, jwt=None, admin=None,
                   legacy=True)
        # Must NOT raise: dev/staging/test only warn.
        _validate_production_secrets()

    def test_weak_secrets_outside_production_log_warning(self, monkeypatch, caplog):
        import logging
        _configure(monkeypatch, render="false", jwt=SHORT, admin=SHORT,
                   legacy=True)
        with caplog.at_level(logging.WARNING, logger="app"):
            _validate_production_secrets()
        assert any("JWT_SECRET_KEY" in r.message for r in caplog.records)


# ----------------------------------------------------------------------
# H (lifecycle): a bad production config actually blocks create_app()
# ----------------------------------------------------------------------

class TestStartupLifecycle:
    def test_create_app_raises_before_building_in_production(self, monkeypatch):
        """Prove the check runs early in create_app and aborts startup: a weak
        JWT secret with RENDER=true makes create_app() raise ConfigurationError
        rather than returning an app.
        """
        _configure(monkeypatch, render="true", jwt=SHORT, admin=STRONG)
        with pytest.raises(ConfigurationError):
            app_module.create_app()


# ----------------------------------------------------------------------
# J: existing test environment remains functional
# ----------------------------------------------------------------------

class TestTestEnvCompatibility:
    def test_default_test_env_builds_app(self, app):
        # The conftest `app` fixture builds a real app with RENDER unset and the
        # test secrets; if F6 broke the test env this fixture would fail.
        assert app is not None

    def test_test_env_validation_does_not_raise(self, monkeypatch):
        # Exactly the conftest posture: RENDER unset, long JWT, short admin
        # token, legacy enabled -> warn-only, no raise.
        monkeypatch.delenv("RENDER", raising=False)
        _validate_production_secrets()
