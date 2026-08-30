"""Automated tests for Tripora's in-process rate limiting.

Coverage
--------
* HTTP 429 response shape (envelope + X-RateLimit-* + Retry-After headers)
* Per-bucket defaults from Config: generate 5/10m, auth 10/10m, writes 30/10m,
  reads 60/1m.
* Per-user keying for authenticated endpoints (user A's budget is independent
  of user B's) and per-IP keying for the public authentication endpoints.
* Env-var driven configuration (with safe fallbacks) via Config.
* Non-limited endpoints (/, /api/health) and OPTIONS preflights are not
  throttled and do not emit rate-limit headers.

Everything runs through the isolated in-memory test DB with the AI itinerary
stubbed and the process-wide limiter reset before each test (see conftest).
Only synthetic test users/data are used; no real credentials are touched.
"""

import time

import pytest

import config.settings as settings_mod
from config.settings import Config
from services.rate_limiter import (
    RateLimiter,
    InMemoryRateLimitStorage,
    RateLimitExceeded,
    limiter,
)
from .helpers import (
    create_logged_in_user,
    create_trip,
    create_trip_and_get_id,
    auth_headers,
)

# Default buckets per the specification (must match Config defaults).
GENERATE_LIMIT = 5
AUTH_LIMIT = 10
WRITE_LIMIT = 30
READ_LIMIT = 60


def _client_get(client, path, ip="127.0.0.1", headers=None):
    return client.get(path, headers=headers, environ_base={"REMOTE_ADDR": ip})


def _client_post(client, path, ip="127.0.0.1", json=None, headers=None):
    return client.post(
        path,
        json=json,
        headers=headers,
        environ_base={"REMOTE_ADDR": ip},
    )


def _exhaust_generate(client, token, count=GENERATE_LIMIT):
    for _ in range(count):
        resp = create_trip(client, token)
        assert resp.status_code == 200, resp.get_json()


@pytest.fixture(autouse=True)
def tight_spec_limits():
    """Apply the real spec limits for this module's tests.

    conftest keeps the general suite's rate limiting OFF (RATE_LIMIT_ENABLED
    false) so the pre-existing tests are unaffected. Here we explicitly enable
    the tight per-bucket limits so the 429 / header / isolation behaviour can
    be exercised end-to-end. Fixture ordering guarantees this runs after the
    app/client fixtures for the integration tests.
    """
    limiter.configure_bucket("trips.generate_trip", 5, 600)
    limiter.configure_bucket("auth.login", 10, 600)
    limiter.configure_bucket("auth.register", 10, 600)
    limiter.configure_bucket("auth.verify_email", 10, 600)
    limiter.configure_bucket("auth.resend_verification", 10, 600)
    limiter.configure_bucket("trips.update_trip", 30, 600)
    limiter.configure_bucket("trips.delete_trip", 30, 600)
    limiter.configure_bucket("trips.regenerate_trip_itinerary", 30, 600)
    limiter.configure_bucket("auth.update_current_user", 30, 600)
    limiter.configure_bucket("DEFAULT_READ", 60, 60)
    yield
    # Teardown: restore the process-wide limiter to its unlimited defaults so
    # the tight config used here does NOT leak into later test modules (the
    # limiter is a session-wide singleton shared by the whole suite).
    for name in list(limiter._buckets.keys()):
        limiter.configure_bucket(name, None, 600)


class TestEnvConfiguration:
    """Rate-limit limits/windows are env-configurable with safe fallbacks."""

    @pytest.fixture(autouse=True)
    def _enable_for_config(self, monkeypatch):
        # conftest disables rate limiting globally; these tests exercise the
        # Config logic directly, so re-enable it for the assertions.
        monkeypatch.setattr(settings_mod.Config, "RATE_LIMIT_ENABLED", True)

    def test_default_generate_bucket(self):
        b = Config.rate_limit_buckets()["trips.generate_trip"]
        assert b["limit"] == GENERATE_LIMIT
        assert b["window"] == 600

    def test_default_auth_bucket(self):
        for ep in ("auth.login", "auth.register", "auth.verify_email",
                   "auth.resend_verification"):
            b = Config.rate_limit_buckets()[ep]
            assert b["limit"] == AUTH_LIMIT
            assert b["window"] == 600

    def test_default_write_bucket(self):
        for ep in ("trips.update_trip", "trips.delete_trip",
                   "trips.regenerate_trip_itinerary", "auth.update_current_user"):
            b = Config.rate_limit_buckets()[ep]
            assert b["limit"] == WRITE_LIMIT
            assert b["window"] == 600

    def test_default_read_bucket(self):
        b = Config.rate_limit_buckets()["DEFAULT_READ"]
        assert b["limit"] == READ_LIMIT
        assert b["window"] == 60

    def test_env_overrides_apply(self, monkeypatch):
        monkeypatch.setattr(settings_mod.Config, "RATE_LIMIT_GENERATE_LIMIT", "100")
        monkeypatch.setattr(settings_mod.Config, "RATE_LIMIT_GENERATE_WINDOW", "120")
        monkeypatch.setattr(settings_mod.Config, "RATE_LIMIT_AUTH_LIMIT", "7")
        b = Config.rate_limit_buckets()
        assert b["trips.generate_trip"] == {"limit": 100, "window": 120}
        assert b["auth.login"] == {"limit": 7, "window": 600}

    def test_invalid_env_falls_back_to_default(self, monkeypatch):
        monkeypatch.setattr(settings_mod.Config, "RATE_LIMIT_GENERATE_LIMIT", "not-a-number")
        monkeypatch.setattr(settings_mod.Config, "RATE_LIMIT_GENERATE_WINDOW", "abc")
        b = Config.rate_limit_buckets()["trips.generate_trip"]
        assert b["limit"] == GENERATE_LIMIT
        assert b["window"] == 600

    def test_disabled_returns_no_buckets(self, monkeypatch):
        monkeypatch.setattr(settings_mod.Config, "RATE_LIMIT_ENABLED", False)
        assert Config.rate_limit_buckets() == {}


class TestLimiterUnit:
    """Unit-level checks of the standalone limiter + storage."""

    def test_allowed_remaining_decrement(self):
        lim = RateLimiter(storage=InMemoryRateLimitStorage())
        lim.configure_bucket("b", 3, 60)
        r1 = lim.check("b", "alice")
        assert r1["allowed"] is True
        assert r1["limit"] == 3
        assert r1["remaining"] == 2
        r2 = lim.check("b", "alice")
        assert r2["remaining"] == 1

    def test_exceeds_limit_raises(self):
        lim = RateLimiter(storage=InMemoryRateLimitStorage())
        lim.configure_bucket("b", 2, 60)
        lim.check("b", "alice")
        lim.check("b", "alice")
        with pytest.raises(RateLimitExceeded) as ei:
            lim.check("b", "alice")
        assert ei.value.bucket == "b"
        assert ei.value.limit == 2

    def test_per_key_isolation(self):
        lim = RateLimiter(storage=InMemoryRateLimitStorage())
        lim.configure_bucket("b", 1, 60)
        lim.check("b", "alice")
        # different key still allowed
        assert lim.check("b", "bob")["allowed"] is True

    def test_unlimited_bucket_never_blocks(self):
        lim = RateLimiter(storage=InMemoryRateLimitStorage())
        lim.configure_bucket("b", None, 60)
        for _ in range(100):
            assert lim.check("b", "alice")["allowed"] is True

    def test_unknown_bucket_resolves_to_none(self):
        lim = RateLimiter(storage=InMemoryRateLimitStorage())
        assert lim.bucket_for("some.unexpected_route") is None

    def test_reset_clears_state(self):
        lim = RateLimiter(storage=InMemoryRateLimitStorage())
        lim.configure_bucket("b", 1, 60)
        lim.check("b", "alice")
        lim.reset()
        assert lim.check("b", "alice")["allowed"] is True


class TestGenerateLimit:
    """POST /api/trips/generate is limited per-user at 5 / 10 minutes."""

    def test_headers_on_successful_generate(self, client):
        token = create_logged_in_user(client, name="GenHeaders")
        resp = create_trip(client, token)
        assert resp.status_code == 200
        assert resp.headers.get("X-RateLimit-Limit") == str(GENERATE_LIMIT)
        assert resp.headers.get("X-RateLimit-Remaining") == str(GENERATE_LIMIT - 1)
        assert resp.headers.get("X-RateLimit-Reset") is not None

    def test_returns_429_after_limit(self, client):
        token = create_logged_in_user(client, name="GenExhaust")
        # Consume the 5 allowed generate calls.
        ids = []
        for _ in range(GENERATE_LIMIT):
            resp = create_trip(client, token)
            assert resp.status_code == 200, resp.get_json()
            ids.append(resp.get_json()["trip"]["id"])
        # The next call must be rejected with 429.
        resp = create_trip(client, token)
        assert resp.status_code == 429

    def test_429_envelope_and_headers(self, client):
        token = create_logged_in_user(client, name="Gen429Body")
        _exhaust_generate(client, token)
        resp = create_trip(client, token)
        body = resp.get_json()
        assert resp.status_code == 429
        assert body["success"] is False
        assert "rate limit" in body["message"].lower()
        assert resp.headers.get("Retry-After") is not None
        assert resp.headers.get("X-RateLimit-Limit") == str(GENERATE_LIMIT)
        assert resp.headers.get("X-RateLimit-Remaining") == "0"
        assert resp.headers.get("X-RateLimit-Reset") is not None
        assert int(resp.headers.get("X-RateLimit-Reset")) >= int(time.time())

    def test_429_does_not_create_trip(self, client):
        token = create_logged_in_user(client, name="GenNoWrite")
        _exhaust_generate(client, token)
        before = len(client.get("/api/trips", headers=auth_headers(token)).get_json()["trips"])
        resp = create_trip(client, token)
        assert resp.status_code == 429
        after = len(client.get("/api/trips", headers=auth_headers(token)).get_json()["trips"])
        assert after == before

    def test_per_user_isolation(self, client):
        """Exhausting user A's generate budget must not touch user B."""
        token_a = create_logged_in_user(client, name="IsolationA")
        _exhaust_generate(client, token_a)
        # User A is now blocked.
        assert create_trip(client, token_a).status_code == 429
        # User B (a distinct account) still has its own budget.
        token_b = create_logged_in_user(client, name="IsolationB")
        resp = create_trip(client, token_b)
        assert resp.status_code == 200
        assert resp.headers.get("X-RateLimit-Remaining") == str(GENERATE_LIMIT - 1)


class TestAuthLimit:
    """Public authentication endpoints are limited per-IP at 10 / 10 minutes."""

    def test_login_returns_429_after_limit(self, client):
        # Distinct IP so it never collides with the shared test-client IP.
        ip = "203.0.113.50"
        for _ in range(AUTH_LIMIT):
            resp = _client_post(client, "/api/auth/login", ip=ip,
                                json={"email": "a@example.com", "password": "wrong"})
            assert resp.status_code == 401, resp.status_code
        resp = _client_post(client, "/api/auth/login", ip=ip,
                            json={"email": "a@example.com", "password": "wrong"})
        assert resp.status_code == 429
        assert resp.get_json()["success"] is False

    def test_login_headers(self, client):
        ip = "203.0.113.51"
        resp = _client_post(client, "/api/auth/login", ip=ip,
                            json={"email": "a@example.com", "password": "wrong"})
        assert resp.status_code == 401
        assert resp.headers.get("X-RateLimit-Limit") == str(AUTH_LIMIT)
        assert resp.headers.get("X-RateLimit-Remaining") == str(AUTH_LIMIT - 1)

    def test_register_returns_429_after_limit(self, client):
        ip = "203.0.113.52"
        for i in range(AUTH_LIMIT):
            resp = _client_post(
                client, "/api/auth/register", ip=ip,
                json={"name": "User{}".format(i), "email": "u{}@example.com".format(i),
                      "password": "supersecret1", "preferredLanguage": "en",
                      "preferredCurrency": "USD"})
            assert resp.status_code == 201, resp.status_code
        resp = _client_post(
            client, "/api/auth/register", ip=ip,
            json={"name": "Burst", "email": "burst@example.com",
                  "password": "supersecret1", "preferredLanguage": "en",
                  "preferredCurrency": "USD"})
        assert resp.status_code == 429

    def test_per_ip_isolation_for_auth(self, client):
        ip_a = "203.0.113.60"
        ip_b = "203.0.113.61"
        for _ in range(AUTH_LIMIT):
            _client_post(client, "/api/auth/login", ip=ip_a,
                         json={"email": "a@example.com", "password": "wrong"})
        # IP A is now exhausted.
        assert _client_post(client, "/api/auth/login", ip=ip_a,
                            json={"email": "a@example.com", "password": "wrong"}).status_code == 429
        # IP B is unaffected.
        resp = _client_post(client, "/api/auth/login", ip=ip_b,
                            json={"email": "a@example.com", "password": "wrong"})
        assert resp.status_code == 401


class TestReadAndWriteBuckets:
    """Reads share a 60/min bucket; writes share a 30/10min bucket."""

    def test_write_returns_429_after_30(self, client):
        token = create_logged_in_user(client, name="WriteExhaust")
        trip_id = create_trip_and_get_id(client, token)
        valid_patch = {
            "destination": "Paris",
            "startDate": "2026-09-01",
            "endDate": "2026-09-03",
            "travelers": 2,
            "budget": "moderate",
            "travelStyle": "balanced",
            "interests": ["food", "culture"],
        }
        # 30 allowed PATCH updates, then 429.
        for _ in range(WRITE_LIMIT):
            resp = client.patch(
                "/api/trips/{}".format(trip_id),
                json=valid_patch,
                headers=auth_headers(token))
            assert resp.status_code == 200, (resp.status_code, resp.get_json())
        resp = client.patch(
            "/api/trips/{}".format(trip_id),
            json=dict(valid_patch, travelers=3),
            headers=auth_headers(token))
        assert resp.status_code == 429

    def test_read_headers_present_and_less_than_write_limit(self, client):
        token = create_logged_in_user(client, name="ReadHdr")
        resp = client.get("/api/trips", headers=auth_headers(token))
        assert resp.status_code == 200
        assert resp.headers.get("X-RateLimit-Limit") == str(READ_LIMIT)
        assert int(resp.headers.get("X-RateLimit-Remaining")) == READ_LIMIT - 1

    def test_get_me_treated_as_read(self, client):
        token = create_logged_in_user(client, name="ReadMe")
        resp = client.get("/api/auth/me", headers=auth_headers(token))
        assert resp.status_code == 200
        assert resp.headers.get("X-RateLimit-Limit") == str(READ_LIMIT)


class TestUnlimitedEndpoints:
    """Home/health are never throttled and emit no rate-limit headers."""

    def test_home_not_limited(self, client):
        for _ in range(200):
            resp = client.get("/")
            assert resp.status_code == 200
            assert resp.headers.get("X-RateLimit-Limit") is None

    def test_health_not_limited(self, client):
        resp = client.get("/api/health")
        assert resp.status_code == 200
        assert resp.headers.get("X-RateLimit-Limit") is None

    def test_options_preflight_not_limited(self, client):
        for _ in range(200):
            resp = client.open(
                "/api/auth/login", method="OPTIONS",
                headers={"Origin": "http://localhost:3000",
                         "Access-Control-Request-Method": "POST"})
            assert resp.status_code == 200
            assert resp.headers.get("X-RateLimit-Limit") is None


class TestFunctionalRegression:
    """The full happy path still works under active rate limiting."""

    def test_registration_verify_login_me_generate_still_works(self, client):
        token = create_logged_in_user(client, name="FunctionalRate")
        me = client.get("/api/auth/me", headers=auth_headers(token))
        assert me.status_code == 200
        resp = create_trip(client, token)
        assert resp.status_code == 200
        assert resp.get_json()["trip"]["destination"] == "Paris"
