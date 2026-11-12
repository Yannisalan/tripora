"""Cloudflare Turnstile + honeypot on /api/auth/register and
/api/auth/forgot-password, plus the public /api/turnstile endpoints.

Siteverify is always mocked (``FakeSiteverify``); conftest additionally fails
any test that would reach Cloudflare.
"""

import logging
import re

import httpx
import pytest

import services.turnstile as turnstile_service
from routes.auth import _redact_sensitive

from .helpers import get_user_by_email, register

# The unpatched network function, captured at import (conftest replaces the
# module attribute for every test).
_REAL_SITEVERIFY_POST = turnstile_service._siteverify_post

SECRET = "turnstile-test-secret-not-real"
SITE_KEY = "1x00000000000000000000AA"  # Cloudflare's documented dummy site key
WEB_HOST = "app.example.com"
API_HOST = "api.example.com"


# ----------------------------------------------------------------------
# Mocked Siteverify
# ----------------------------------------------------------------------

class _Response:
    def __init__(self, status_code, body):
        self.status_code = status_code
        self._body = body

    def json(self):
        if isinstance(self._body, Exception):
            raise self._body
        return self._body


class FakeSiteverify:
    """Behaves like Siteverify for a few well-known tokens.

    ``good-<action>-<n>``  valid once for <action>, solved on WEB_HOST
    ``elsewhere-<n>``      valid, but solved on an unexpected hostname
    ``expired-<n>``        Cloudflare's expired/duplicate answer
    anything else          invalid-input-response
    A token presented twice gets timeout-or-duplicate (single use).
    """

    def __init__(self):
        self.calls = []
        self.seen = set()
        self.exception = None
        self.status_code = 200

    def __call__(self, form, timeout):
        self.calls.append({"form": dict(form), "timeout": timeout})
        if self.exception is not None:
            raise self.exception
        if self.status_code != 200:
            return _Response(self.status_code, {})
        token = form.get("response", "")
        if form.get("secret") != SECRET:
            return _Response(200, {"success": False,
                                   "error-codes": ["invalid-input-secret"]})
        if token in self.seen or token.startswith("expired-"):
            return _Response(200, {"success": False,
                                   "error-codes": ["timeout-or-duplicate"]})
        self.seen.add(token)
        match = re.match(r"^good-(register|forgot_password)-", token)
        if match:
            return _Response(200, {"success": True, "action": match.group(1),
                                   "hostname": WEB_HOST,
                                   "challenge_ts": "2026-11-12T10:00:00Z"})
        if token.startswith("elsewhere-"):
            return _Response(200, {"success": True, "action": "register",
                                   "hostname": "evil.example.net"})
        return _Response(200, {"success": False,
                               "error-codes": ["invalid-input-response"]})


@pytest.fixture
def siteverify(monkeypatch):
    monkeypatch.setenv("TURNSTILE_ENABLED", "true")
    monkeypatch.setenv("TURNSTILE_SECRET_KEY", SECRET)
    monkeypatch.setenv("TURNSTILE_SITE_KEY", SITE_KEY)
    monkeypatch.setenv("TURNSTILE_ALLOWED_HOSTNAMES", "{}, {}".format(WEB_HOST, API_HOST))
    fake = FakeSiteverify()
    monkeypatch.setattr(turnstile_service, "_siteverify_post", fake)
    return fake


@pytest.fixture
def reset_mail(monkeypatch):
    """Capture password-reset e-mails: list of recipients."""
    import routes.auth as auth_routes

    sent = []

    def _capture(to_email, code):
        sent.append(to_email)
        return True

    monkeypatch.setattr(auth_routes, "send_password_reset_code", _capture)
    return sent


@pytest.fixture
def production_limits(monkeypatch):
    """The real production bucket table (conftest runs unlimited)."""
    import config.settings as settings_mod
    from services.rate_limiter import limiter

    monkeypatch.setattr(settings_mod.Config, "RATE_LIMIT_ENABLED", True)
    for name, cfg in settings_mod.Config.rate_limit_buckets().items():
        limiter.configure_bucket(name, cfg["limit"], cfg["window"])
    limiter.reset()
    yield
    for name in list(limiter._buckets.keys()):
        limiter.configure_bucket(name, None, 600)
    limiter.reset()


def _user_exists(app, email):
    with app.app_context():
        return get_user_by_email(email) is not None


def _forgot(client, email, **extra):
    payload = {"email": email}
    payload.update(extra)
    return client.post("/api/auth/forgot-password", json=payload)


def _make_user(app, client, email):
    """Existing password account, created with protection off."""
    import os
    previous = os.environ.get("TURNSTILE_ENABLED")
    os.environ["TURNSTILE_ENABLED"] = "false"
    try:
        assert register(client, email=email).status_code == 201
    finally:
        os.environ["TURNSTILE_ENABLED"] = previous or "false"
    assert _user_exists(app, email)


# ======================================================================
# Registration
# ======================================================================

class TestRegister:

    def test_valid_token_creates_the_account(self, app, client, siteverify,
                                             capture_verification_emails):
        resp = register(client, email="ok@example.com",
                        turnstileToken="good-register-1")
        assert resp.status_code == 201, resp.get_json()
        assert resp.get_json()["verificationRequired"] is True
        assert _user_exists(app, "ok@example.com")
        assert "ok@example.com" in capture_verification_emails
        form = siteverify.calls[0]["form"]
        assert form["secret"] == SECRET and form["response"] == "good-register-1"
        assert "remoteip" in form

    def test_invalid_token_is_rejected_without_side_effects(
            self, app, client, siteverify, capture_verification_emails):
        resp = register(client, email="bad@example.com", turnstileToken="forged")
        assert resp.status_code == 400
        assert resp.get_json()["code"] == "turnstile_failed"
        assert not _user_exists(app, "bad@example.com")
        assert capture_verification_emails == {}

    def test_missing_token_is_rejected_without_calling_cloudflare(
            self, app, client, siteverify):
        resp = register(client, email="none@example.com")
        assert resp.status_code == 400
        assert resp.get_json()["code"] == "turnstile_failed"
        assert siteverify.calls == []
        assert not _user_exists(app, "none@example.com")

    @pytest.mark.parametrize("token", ["", "   ", None, 12345, ["x"]])
    def test_blank_or_non_string_token_counts_as_missing(
            self, app, client, siteverify, token):
        resp = register(client, email="blank@example.com", turnstileToken=token)
        assert resp.status_code == 400
        assert siteverify.calls == []

    def test_oversized_token_is_rejected_locally(self, client, siteverify):
        resp = register(client, email="long@example.com",
                        turnstileToken="good-register-" + "x" * 2100)
        assert resp.status_code == 400
        assert siteverify.calls == []

    def test_expired_token_is_rejected(self, app, client, siteverify):
        resp = register(client, email="exp@example.com", turnstileToken="expired-1")
        assert resp.status_code == 400
        assert not _user_exists(app, "exp@example.com")

    def test_reused_token_is_rejected(self, app, client, siteverify):
        first = register(client, email="first@example.com",
                         turnstileToken="good-register-reuse")
        second = register(client, email="second@example.com",
                          turnstileToken="good-register-reuse")
        assert first.status_code == 201
        assert second.status_code == 400
        assert not _user_exists(app, "second@example.com")

    def test_token_for_another_action_is_rejected(self, app, client, siteverify):
        resp = register(client, email="act@example.com",
                        turnstileToken="good-forgot_password-1")
        assert resp.status_code == 400
        assert not _user_exists(app, "act@example.com")

    def test_token_from_unexpected_hostname_is_rejected(self, app, client, siteverify):
        resp = register(client, email="host@example.com", turnstileToken="elsewhere-1")
        assert resp.status_code == 400
        assert not _user_exists(app, "host@example.com")

    @pytest.mark.parametrize("failure", [
        httpx.ConnectTimeout("timed out"),
        httpx.ReadTimeout("timed out"),
        httpx.ConnectError("unreachable"),
    ])
    def test_network_failure_fails_closed_with_503(self, app, client, siteverify, failure):
        siteverify.exception = failure
        resp = register(client, email="net@example.com",
                        turnstileToken="good-register-net")
        assert resp.status_code == 503
        assert resp.get_json()["code"] == "turnstile_unavailable"
        assert not _user_exists(app, "net@example.com")

    def test_cloudflare_error_status_fails_closed(self, app, client, siteverify):
        siteverify.status_code = 502
        resp = register(client, email="cf5xx@example.com",
                        turnstileToken="good-register-5xx")
        assert resp.status_code == 503
        assert not _user_exists(app, "cf5xx@example.com")

    def test_unparseable_siteverify_body_fails_closed(self, app, client, monkeypatch, siteverify):
        monkeypatch.setattr(turnstile_service, "_siteverify_post",
                            lambda form, timeout: _Response(200, ValueError("not json")))
        resp = register(client, email="json@example.com",
                        turnstileToken="good-register-json")
        assert resp.status_code == 503
        assert not _user_exists(app, "json@example.com")

    def test_enabled_without_secret_fails_closed(self, app, client, siteverify, monkeypatch):
        monkeypatch.setenv("TURNSTILE_SECRET_KEY", "")
        resp = register(client, email="nosecret@example.com",
                        turnstileToken="good-register-1")
        assert resp.status_code == 503
        assert siteverify.calls == []
        assert not _user_exists(app, "nosecret@example.com")

    def test_field_errors_do_not_burn_the_token(self, client, siteverify):
        resp = register(client, email="weak@example.com", password="short",
                        turnstileToken="good-register-keep")
        assert resp.status_code == 400
        assert siteverify.calls == []

    def test_filled_honeypot_looks_like_success_but_does_nothing(
            self, app, client, siteverify, capture_verification_emails):
        normal = register(client, email="human@example.com",
                          turnstileToken="good-register-h")
        bot = register(client, email="bot@example.com",
                       turnstileToken="good-register-b", website="http://spam")
        assert bot.status_code == normal.status_code == 201
        assert bot.get_json() == normal.get_json()
        assert not _user_exists(app, "bot@example.com")
        assert "bot@example.com" not in capture_verification_emails
        # Only the human request was sent to Cloudflare.
        assert [c["form"]["response"] for c in siteverify.calls] == ["good-register-h"]

    @pytest.mark.parametrize("value", [1, True, ["x"], {"a": 1}])
    def test_non_string_honeypot_counts_as_filled(self, app, client, siteverify, value):
        resp = register(client, email="nonstr@example.com",
                        turnstileToken="good-register-ns", website=value)
        assert resp.status_code == 201
        assert not _user_exists(app, "nonstr@example.com")

    @pytest.mark.parametrize("value", ["", "   ", "\n", None])
    def test_empty_honeypot_does_not_block_people(self, app, client, siteverify, value):
        resp = register(client, email="empty@example.com",
                        turnstileToken="good-register-e", website=value)
        assert resp.status_code == 201
        assert _user_exists(app, "empty@example.com")

    def test_honeypot_is_enforced_even_with_turnstile_off(self, app, client):
        resp = register(client, email="offbot@example.com", website="spam")
        assert resp.status_code == 201
        assert not _user_exists(app, "offbot@example.com")


# ======================================================================
# Forgot password
# ======================================================================

class TestForgotPassword:

    def test_valid_token_sends_the_reset_code(self, app, client, siteverify, reset_mail):
        _make_user(app, client, "reset@example.com")
        resp = _forgot(client, "reset@example.com",
                       turnstileToken="good-forgot_password-1")
        assert resp.status_code == 200
        assert reset_mail == ["reset@example.com"]

    def test_invalid_token_issues_no_reset_code(self, app, client, siteverify, reset_mail):
        _make_user(app, client, "victim@example.com")
        resp = _forgot(client, "victim@example.com", turnstileToken="forged")
        assert resp.status_code == 400
        assert resp.get_json()["code"] == "turnstile_failed"
        assert reset_mail == []
        with app.app_context():
            assert get_user_by_email("victim@example.com").reset_code_hash is None

    def test_missing_and_expired_tokens_issue_no_reset_code(
            self, app, client, siteverify, reset_mail):
        _make_user(app, client, "victim2@example.com")
        assert _forgot(client, "victim2@example.com").status_code == 400
        assert _forgot(client, "victim2@example.com",
                       turnstileToken="expired-9").status_code == 400
        assert reset_mail == []

    def test_register_token_cannot_be_used_for_reset(self, app, client, siteverify, reset_mail):
        _make_user(app, client, "cross@example.com")
        resp = _forgot(client, "cross@example.com", turnstileToken="good-register-x")
        assert resp.status_code == 400
        assert reset_mail == []

    def test_network_failure_fails_closed(self, app, client, siteverify, reset_mail):
        _make_user(app, client, "down@example.com")
        siteverify.exception = httpx.ConnectTimeout("timed out")
        resp = _forgot(client, "down@example.com",
                       turnstileToken="good-forgot_password-n")
        assert resp.status_code == 503
        assert reset_mail == []

    def test_responses_stay_generic_for_known_and_unknown_addresses(
            self, app, client, siteverify, reset_mail):
        _make_user(app, client, "known@example.com")
        known = _forgot(client, "known@example.com",
                        turnstileToken="good-forgot_password-k")
        unknown = _forgot(client, "nobody@example.com",
                          turnstileToken="good-forgot_password-u")
        assert known.status_code == unknown.status_code == 200
        assert known.get_json() == unknown.get_json()

    def test_challenge_failure_does_not_depend_on_the_address(
            self, app, client, siteverify):
        _make_user(app, client, "exists@example.com")
        a = _forgot(client, "exists@example.com", turnstileToken="forged-a")
        b = _forgot(client, "ghost@example.com", turnstileToken="forged-b")
        assert a.status_code == b.status_code == 400
        assert a.get_json() == b.get_json()

    def test_filled_honeypot_gets_the_generic_answer_and_no_email(
            self, app, client, siteverify, reset_mail):
        _make_user(app, client, "hp@example.com")
        unknown = _forgot(client, "nobody@example.com",
                          turnstileToken="good-forgot_password-g")
        bot = _forgot(client, "hp@example.com", website="x",
                      turnstileToken="good-forgot_password-b")
        assert bot.status_code == 200
        assert bot.get_json() == unknown.get_json()
        assert reset_mail == []
        assert [c["form"]["response"] for c in siteverify.calls] == [
            "good-forgot_password-g"]


# ======================================================================
# Rate limiting still applies first
# ======================================================================

class TestRateLimitInteraction:

    def test_failed_challenges_consume_the_reset_budget(
            self, app, client, siteverify, reset_mail, production_limits):
        _make_user(app, client, "rl@example.com")
        for i in range(5):
            assert _forgot(client, "rl@example.com",
                           turnstileToken="forged-%d" % i).status_code == 400
        blocked = _forgot(client, "rl@example.com",
                          turnstileToken="good-forgot_password-late")
        assert blocked.status_code == 429
        # The limiter answered before Cloudflare was asked.
        assert "good-forgot_password-late" not in [
            c["form"]["response"] for c in siteverify.calls]
        assert reset_mail == []

    def test_honeypot_requests_are_rate_limited_too(self, client, production_limits):
        statuses = [_forgot(client, "x@example.com", website="bot").status_code
                    for _ in range(6)]
        assert statuses[:5] == [200] * 5 and statuses[5] == 429


# ======================================================================
# Configuration and logging
# ======================================================================

class TestConfiguration:

    @pytest.mark.parametrize("enabled, env, expected", [
        (None, "production", True),
        (None, "", True),
        (None, "test", False),
        (None, "development", False),
        ("false", "production", False),
        ("0", "production", False),
        ("true", "test", True),
        ("garbage", "production", True),
    ])
    def test_enabled_resolution(self, monkeypatch, enabled, env, expected):
        if enabled is None:
            monkeypatch.delenv("TURNSTILE_ENABLED", raising=False)
        else:
            monkeypatch.setenv("TURNSTILE_ENABLED", enabled)
        monkeypatch.setenv("TRIPORA_ENV", env)
        assert turnstile_service.is_enabled() is expected

    def test_disabled_in_tests_needs_no_token(self, app, client):
        assert register(client, email="dev@example.com").status_code == 201
        assert _user_exists(app, "dev@example.com")

    def test_timeout_is_strict(self, client, siteverify, monkeypatch):
        register(client, email="t1@example.com", turnstileToken="good-register-t1")
        assert siteverify.calls[-1]["timeout"] == 5.0
        monkeypatch.setenv("TURNSTILE_TIMEOUT_SECONDS", "120")
        register(client, email="t2@example.com", turnstileToken="good-register-t2")
        assert siteverify.calls[-1]["timeout"] == 10.0

    def test_real_post_uses_strict_timeout_and_no_redirects(self, monkeypatch):
        captured = {}

        def fake_post(url, **kwargs):
            captured["url"] = url
            captured.update(kwargs)
            return _Response(200, {})

        # httpx.post itself is replaced, so nothing leaves the machine.
        monkeypatch.setattr(turnstile_service.httpx, "post", fake_post)
        _REAL_SITEVERIFY_POST({"secret": "s", "response": "r"}, 5.0)
        assert captured["url"] == turnstile_service.SITEVERIFY_URL
        assert captured["url"].startswith("https://challenges.cloudflare.com/")
        assert captured["follow_redirects"] is False
        timeout = captured["timeout"]
        assert timeout.read == 5.0 and timeout.connect == 3.0

    def test_tokens_and_secret_are_never_logged(self, client, siteverify, caplog):
        caplog.set_level(logging.DEBUG)
        register(client, email="log1@example.com", turnstileToken="forged-secret-token")
        register(client, email="log2@example.com", turnstileToken="good-register-logged")
        _forgot(client, "log1@example.com", turnstileToken="forged-reset-token")
        text = caplog.text
        for needle in ("forged-secret-token", "good-register-logged",
                       "forged-reset-token", SECRET):
            assert needle not in text

    def test_redaction_covers_new_fields(self):
        safe = _redact_sensitive({"turnstileToken": "t", "website": "w", "name": "n"})
        assert safe["turnstileToken"] == "[REDACTED]"
        assert safe["website"] == "[REDACTED]"
        assert safe["name"] == "n"


# ======================================================================
# Public endpoints
# ======================================================================

class TestPublicEndpoints:

    def test_config_exposes_only_the_public_site_key(self, client, siteverify):
        resp = client.get("/api/turnstile/config")
        body = resp.get_json()
        assert resp.status_code == 200
        assert body["enabled"] is True and body["siteKey"] == SITE_KEY
        assert body["challengePath"] == "/api/turnstile/challenge"
        assert SECRET not in resp.get_data(as_text=True)

    def test_config_when_disabled(self, client):
        body = client.get("/api/turnstile/config").get_json()
        assert body["enabled"] is False and body["siteKey"] is None

    def test_challenge_page_is_locked_down(self, client, siteverify):
        resp = client.get("/api/turnstile/challenge?action=register&theme=dark")
        html = resp.get_data(as_text=True)
        assert resp.status_code == 200
        assert resp.mimetype == "text/html"
        assert SITE_KEY in html and '"action": "register"' in html
        assert SECRET not in html
        csp = resp.headers["Content-Security-Policy"]
        nonce = re.search(r"'nonce-([^']+)'", csp).group(1)
        assert html.count('nonce="{}"'.format(nonce)) == 3
        assert "default-src 'none'" in csp
        assert "frame-ancestors 'none'" in csp
        assert "script-src 'nonce-{}' https://challenges.cloudflare.com".format(nonce) in csp
        assert "'unsafe-inline'" not in csp and "'unsafe-eval'" not in csp
        assert resp.headers["X-Frame-Options"] == "DENY"
        assert resp.headers["Cache-Control"] == "no-store"
        assert "TriporaTurnstile" in html

    def test_challenge_nonce_changes_per_request(self, client, siteverify):
        a = client.get("/api/turnstile/challenge?action=register")
        b = client.get("/api/turnstile/challenge?action=register")
        assert a.headers["Content-Security-Policy"] != b.headers["Content-Security-Policy"]

    def test_challenge_rejects_unknown_action_and_theme_injection(self, client, siteverify):
        assert client.get("/api/turnstile/challenge?action=login").status_code == 400
        assert client.get("/api/turnstile/challenge").status_code == 400
        html = client.get(
            '/api/turnstile/challenge?action=register&theme="><script>x</script>'
        ).get_data(as_text=True)
        assert "<script>x</script>" not in html
        assert 'class="light"' in html

    def test_site_key_cannot_break_out_of_the_script(self, client, siteverify, monkeypatch):
        monkeypatch.setenv("TURNSTILE_SITE_KEY", "</script><script>alert(1)</script>")
        html = client.get("/api/turnstile/challenge?action=register").get_data(as_text=True)
        assert "</script><script>alert(1)" not in html

    def test_challenge_unavailable_when_disabled_or_unconfigured(self, client, monkeypatch):
        assert client.get("/api/turnstile/challenge?action=register").status_code == 503
        monkeypatch.setenv("TURNSTILE_ENABLED", "true")
        monkeypatch.setenv("TURNSTILE_SITE_KEY", "")
        assert client.get("/api/turnstile/challenge?action=register").status_code == 503

    def test_other_routes_keep_the_default_csp(self, client):
        csp = client.get("/api/health").headers["Content-Security-Policy"]
        assert csp.startswith("default-src 'self'; script-src 'self';")
