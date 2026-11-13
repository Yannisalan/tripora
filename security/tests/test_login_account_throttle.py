"""F3 - Per-account login throttling (distributed credential-stuffing defence).

A second rate-limit bucket, independent of the existing per-IP auth limit,
counts FAILED login attempts per account (keyed on the normalized e-mail's
keyed HMAC) across every source IP. Rotating source IPs therefore no longer
hides a credential-stuffing run against one account.

These tests exercise the behaviour end-to-end through the real login endpoint
(and the limiter directly for the concurrency property). Only synthetic test
users and data are used; no real credentials are touched. The per-account
limit is configured small here for speed -- the shipped default (20 / hour) is
asserted separately against Config.

Mapping to the F3 brief / review:
  A  TestSameAccountManyIps
  B  TestManyAccountsOneIp
  C  TestEmailNormalization (behavioural + unit)
  D  TestSuccessfulLogin (success resets the counter; never penalised)
  E  TestNoEnumeration
  F  TestWindowExpiry (+ fixed-window boundary characterisation)
  G  TestConcurrency (atomic gate: limiter-level AND end-to-end HTTP)
  Storage failure / fail-closed: TestStorageFailure
"""

import threading
import time

import pytest

import config.settings as settings_mod
from config.settings import Config
from services.rate_limiter import (
    RateLimiter,
    RateLimitStorage,
    InMemoryRateLimitStorage,
    RateLimitExceeded,
    RateLimitUnavailable,
    StorageError,
    limiter,
)
import routes.auth as auth_mod
from routes.auth import _account_login_key, ACCOUNT_LOGIN_BUCKET
from .helpers import create_logged_in_user, auth_headers  # noqa: F401


# Small per-account limit for fast behavioural tests (the real default is 20).
ACCOUNT_LIMIT = 5
PER_IP_AUTH_LIMIT = 10
WRONG_PASSWORD = "definitely-not-the-password"
GOOD_PASSWORD = "supersecret1"


def _post_login(client, email, password, ip):
    return client.post(
        "/api/auth/login",
        json={"email": email, "password": password},
        environ_base={"REMOTE_ADDR": ip},
    )


def _account_count(email):
    """Current per-account failure count for a (raw) e-mail, via the limiter."""
    key = _account_login_key(str(email).strip().lower())
    return limiter.peek(ACCOUNT_LOGIN_BUCKET, key)["count"]


@pytest.fixture(autouse=True)
def account_throttle_limits():
    """Configure the real-but-tightened buckets for this module and restore.

    conftest keeps RATE_LIMIT_ENABLED off globally and resets the limiter's
    counters around every test; here we additionally configure the buckets on
    the shared singleton so the login route enforces them, then reset every
    bucket back to unlimited so the tight config never leaks into other
    modules (the limiter is a session-wide singleton).
    """
    limiter.configure_bucket(ACCOUNT_LOGIN_BUCKET, ACCOUNT_LIMIT, 3600)
    limiter.configure_bucket("auth.login", PER_IP_AUTH_LIMIT, 600)
    # Keep registration / verification from throttling the fixtures.
    limiter.configure_bucket("auth.register", 100000, 600)
    limiter.configure_bucket("auth.verify_email", 100000, 900)
    limiter.configure_bucket("auth.resend_verification_email", 100000, 3600)
    limiter.configure_bucket("DEFAULT_READ", 100000, 60)
    limiter.configure_bucket("DEFAULT_WRITE", 100000, 600)
    yield
    for name in list(limiter._buckets.keys()):
        limiter.configure_bucket(name, None, 600)


# ----------------------------------------------------------------------
# Config default (ships at 20 / hour)
# ----------------------------------------------------------------------

class TestAccountBucketDefault:
    @pytest.fixture(autouse=True)
    def _enable(self, monkeypatch):
        monkeypatch.setattr(settings_mod.Config, "RATE_LIMIT_ENABLED", True)

    def test_default_is_20_per_hour(self):
        bucket = Config.rate_limit_buckets()["auth.login_account"]
        assert bucket == {"limit": 20, "window": 3600}

    def test_env_override_applies(self, monkeypatch):
        monkeypatch.setattr(
            settings_mod.Config, "RATE_LIMIT_LOGIN_ACCOUNT_LIMIT", "7")
        monkeypatch.setattr(
            settings_mod.Config, "RATE_LIMIT_LOGIN_ACCOUNT_WINDOW", "120")
        bucket = Config.rate_limit_buckets()["auth.login_account"]
        assert bucket == {"limit": 7, "window": 120}


# ----------------------------------------------------------------------
# A. Same account, many IPs -> account-level limit enforced
# ----------------------------------------------------------------------

class TestSameAccountManyIps:

    def test_same_account_many_ips_is_throttled(self, client):
        email = "victimA@example.com"
        create_logged_in_user(client, name="VictimA", email=email)

        # ACCOUNT_LIMIT failed attempts, each from a DIFFERENT IP so the
        # per-IP bucket (10) is never the thing that trips.
        for i in range(ACCOUNT_LIMIT):
            resp = _post_login(client, email, WRONG_PASSWORD,
                               ip="198.51.100.{}".format(i + 1))
            assert resp.status_code == 401, (i, resp.get_json())

        # The next attempt, from yet another fresh IP, is blocked by the
        # account bucket (every IP used so far sent only one request).
        resp = _post_login(client, email, WRONG_PASSWORD, ip="198.51.100.201")
        assert resp.status_code == 429
        assert resp.get_json()["success"] is False

    def test_tripped_account_blocks_even_correct_password(self, client):
        """The gate runs before password verification, so once the account is
        throttled even the CORRECT password is refused -- which is what stops a
        stuffing run from succeeding on the attempt that finally guesses right.
        """
        email = "victimA2@example.com"
        create_logged_in_user(client, name="VictimA2", email=email)

        for i in range(ACCOUNT_LIMIT):
            _post_login(client, email, WRONG_PASSWORD,
                        ip="198.51.100.{}".format(i + 1))

        # Correct password, brand-new IP -> still blocked.
        resp = _post_login(client, email, GOOD_PASSWORD, ip="198.51.100.202")
        assert resp.status_code == 429
        assert "accessToken" not in resp.get_json()


# ----------------------------------------------------------------------
# B. Many accounts, one IP -> existing per-IP protection still works
# ----------------------------------------------------------------------

class TestManyAccountsOneIp:

    def test_per_ip_limit_still_enforced(self, client):
        ip = "203.0.113.70"
        # Distinct e-mails, so no single account bucket fills; the per-IP
        # auth bucket (10) must still trip.
        for i in range(PER_IP_AUTH_LIMIT):
            resp = _post_login(client, "nobody{}@example.com".format(i),
                               WRONG_PASSWORD, ip=ip)
            assert resp.status_code == 401, (i, resp.get_json())

        resp = _post_login(client, "nobody-extra@example.com",
                           WRONG_PASSWORD, ip=ip)
        assert resp.status_code == 429  # per-IP limiter, not the account one


# ----------------------------------------------------------------------
# C. Email normalization -> casing/whitespace variants share one bucket
# ----------------------------------------------------------------------

class TestEmailNormalization:

    def test_variants_share_one_bucket(self, client):
        variants = [
            "  CaseTest@Example.COM  ",
            "casetest@example.com",
            "CASETEST@EXAMPLE.COM",
            "  casetest@example.com",
            "CaseTest@example.com  ",
        ]
        assert len(variants) == ACCOUNT_LIMIT

        for i, variant in enumerate(variants):
            resp = _post_login(client, variant, WRONG_PASSWORD,
                               ip="198.51.100.{}".format(100 + i))
            assert resp.status_code == 401, (i, resp.get_json())

        # All variants normalized to the same address -> bucket is now full.
        resp = _post_login(client, "  CASETEST@example.com ", WRONG_PASSWORD,
                           ip="198.51.100.199")
        assert resp.status_code == 429

    def test_key_is_normalization_stable_and_leaks_no_plaintext(self):
        a = _account_login_key("casetest@example.com")
        b = _account_login_key("casetest@example.com")
        assert a == b                      # deterministic
        assert "casetest" not in a         # raw local-part never in the key
        assert "@" not in a                # it is a hex digest
        assert len(a) == 64                # SHA-256 hex
        assert _account_login_key("other@example.com") != a


# ----------------------------------------------------------------------
# D. Successful authentication is not penalized
# ----------------------------------------------------------------------

class TestSuccessfulLogin:

    def test_login_succeeds_below_the_limit(self, client):
        email = "gooduser@example.com"
        create_logged_in_user(client, name="GoodUser", email=email)

        # A few failures, still under the limit.
        for i in range(ACCOUNT_LIMIT - 1):
            _post_login(client, email, WRONG_PASSWORD,
                        ip="198.51.100.{}".format(i + 1))

        resp = _post_login(client, email, GOOD_PASSWORD, ip="198.51.100.50")
        assert resp.status_code == 200
        assert resp.get_json()["accessToken"]

    def test_success_resets_the_failure_counter(self, client):
        """A successful login clears the account's failed-attempt budget, so a
        legitimate user is never penalised by earlier failures (the effective
        metric is consecutive failures).
        """
        email = "nopenalty@example.com"
        create_logged_in_user(client, name="NoPenalty", email=email)

        for i in range(ACCOUNT_LIMIT - 1):
            _post_login(client, email, WRONG_PASSWORD,
                        ip="198.51.100.{}".format(i + 1))
        assert _account_count(email) == ACCOUNT_LIMIT - 1

        ok = _post_login(client, email, GOOD_PASSWORD, ip="198.51.100.60")
        assert ok.status_code == 200
        # Success clears the counter back to zero.
        assert _account_count(email) == 0

        # And the fresh budget is real: the account can fail again right up to
        # the limit without being blocked.
        for i in range(ACCOUNT_LIMIT):
            resp = _post_login(client, email, WRONG_PASSWORD,
                               ip="198.51.100.{}".format(70 + i))
            assert resp.status_code == 401, (i, resp.get_json())


# ----------------------------------------------------------------------
# E. No account enumeration via the throttle response
# ----------------------------------------------------------------------

class TestNoEnumeration:

    def _trip_bucket(self, client, email, ip_base):
        for i in range(ACCOUNT_LIMIT):
            _post_login(client, email, WRONG_PASSWORD,
                        ip="{}.{}".format(ip_base, i + 1))

    def test_blocked_response_identical_existing_vs_unknown(self, client):
        existing = "realuser@example.com"
        create_logged_in_user(client, name="RealUser", email=existing)
        unknown = "ghost-does-not-exist@example.com"

        self._trip_bucket(client, existing, "198.51.100")
        self._trip_bucket(client, unknown, "203.0.113")

        blocked_existing = _post_login(
            client, existing, WRONG_PASSWORD, ip="198.51.100.250")
        blocked_unknown = _post_login(
            client, unknown, WRONG_PASSWORD, ip="203.0.113.250")

        assert blocked_existing.status_code == 429
        assert blocked_unknown.status_code == 429
        # Identical body and status: the response cannot reveal which e-mail
        # is a real account.
        assert blocked_existing.get_json() == blocked_unknown.get_json()
        assert (blocked_existing.headers.get("X-RateLimit-Limit")
                == blocked_unknown.headers.get("X-RateLimit-Limit"))

    def test_sub_limit_wrong_password_identical_existing_vs_unknown(self, client):
        existing = "realuser2@example.com"
        create_logged_in_user(client, name="RealUser2", email=existing)
        unknown = "ghost2@example.com"

        r_existing = _post_login(client, existing, WRONG_PASSWORD,
                                 ip="198.51.100.10")
        r_unknown = _post_login(client, unknown, WRONG_PASSWORD,
                                ip="198.51.100.11")
        assert r_existing.status_code == r_unknown.status_code == 401
        assert r_existing.get_json() == r_unknown.get_json()


# ----------------------------------------------------------------------
# F. Window expiry resets the account bucket
# ----------------------------------------------------------------------

class TestWindowExpiry:

    def test_account_bucket_expires_after_window(self, client):
        # Re-configure with a short window for this test only.
        window = 3
        limiter.configure_bucket(ACCOUNT_LOGIN_BUCKET, 2, window)

        email = "expiry@example.com"
        create_logged_in_user(client, name="Expiry", email=email)

        # Windows are aligned to the epoch. Start at the beginning of a fresh
        # window so the three attempts below (each ~0.3 s of password hashing)
        # cannot straddle a boundary; with the former 1 s window they did in
        # roughly half of all runs and the test was flaky.
        time.sleep(window - (time.time() % window) + 0.05)

        for i in range(2):
            resp = _post_login(client, email, WRONG_PASSWORD,
                               ip="198.51.100.{}".format(i + 1))
            assert resp.status_code == 401
        # Bucket full -> blocked.
        assert _post_login(client, email, WRONG_PASSWORD,
                           ip="198.51.100.80").status_code == 429

        # Wait past the fixed window so a new window starts, then it is allowed
        # again (counter reset by window roll-over).
        time.sleep(window + 0.2)
        resp = _post_login(client, email, WRONG_PASSWORD, ip="198.51.100.81")
        assert resp.status_code == 401

    def test_fixed_window_boundary_bound_is_2x_limit(self):
        """Characterise the known fixed-window boundary property: across one
        window roll-over an account can see up to 2*limit attempts in a short
        span (limit at the end of window N, limit at the start of N+1), never
        more. Documented as an accepted bound for a 20/hour budget; a sliding
        window would remove it at the cost of diverging from the shared
        fixed-window infrastructure.
        """
        lim = RateLimiter(storage=InMemoryRateLimitStorage())
        limit = 2
        lim.configure_bucket("b", limit, 1)  # 1-second window
        key = "acct"

        # Fill window N.
        for _ in range(limit):
            lim.check("b", key)
        with pytest.raises(RateLimitExceeded):
            lim.check("b", key)

        # Cross into window N+1: a fresh `limit` becomes available (and no more).
        time.sleep(1.05)
        admitted = 0
        for _ in range(limit + 2):
            try:
                lim.check("b", key)
                admitted += 1
            except RateLimitExceeded:
                pass
        assert admitted == limit


# ----------------------------------------------------------------------
# G. Concurrency: atomic counting cannot lose a failed attempt
# ----------------------------------------------------------------------

class TestConcurrency:
    """Strict burst-safety of the atomic gate (limiter.check).

    The production gate is an atomic increment-and-compare, so a simultaneous
    burst can never admit more than ``limit`` attempts -- the property a
    read-then-increment gate would fail (a cold-start burst would all read 0
    and slip through). These tests fire real threads behind a barrier for
    genuine contention: one at the limiter level (the exact primitive the login
    route calls) and one end-to-end through the HTTP login endpoint.
    """

    def test_check_gate_admits_at_most_limit_under_contention(self):
        lim = RateLimiter(storage=InMemoryRateLimitStorage())
        limit = 20
        lim.configure_bucket("b", limit, 3600)
        key = "acct"
        n_threads = 300

        barrier = threading.Barrier(n_threads)
        admitted = []
        blocked = []
        lock = threading.Lock()

        def hammer():
            barrier.wait()  # maximise real contention at the threshold
            try:
                lim.check("b", key)
                with lock:
                    admitted.append(1)
            except RateLimitExceeded:
                with lock:
                    blocked.append(1)

        threads = [threading.Thread(target=hammer) for _ in range(n_threads)]
        for t in threads:
            t.start()
        for t in threads:
            t.join()

        # Exactly `limit` admitted, every other request atomically blocked:
        # the burst cannot exceed the threshold.
        assert len(admitted) == limit
        assert len(blocked) == n_threads - limit

    def test_http_login_concurrency_admits_at_most_limit(self, client):
        """End-to-end: many SIMULTANEOUS login POSTs for one account, each from
        a distinct IP (so the per-IP limit is not the thing that fires), admit
        at most the account limit. Uses a limit of 1 so only the single admitted
        request touches the DB, keeping the shared in-memory SQLite connection
        uncontended.
        """
        limiter.configure_bucket(ACCOUNT_LOGIN_BUCKET, 1, 3600)
        email = "concurrent@example.com"
        n_threads = 40

        barrier = threading.Barrier(n_threads)
        statuses = []
        lock = threading.Lock()

        def attempt(i):
            barrier.wait()
            resp = _post_login(client, email, WRONG_PASSWORD,
                               ip="198.51.100.{}".format(i + 1))
            with lock:
                statuses.append(resp.status_code)

        threads = [threading.Thread(target=attempt, args=(i,))
                   for i in range(n_threads)]
        for t in threads:
            t.start()
        for t in threads:
            t.join()

        admitted = [s for s in statuses if s != 429]
        blocked = [s for s in statuses if s == 429]
        # At most the limit (1) was admitted; it was a normal failed login
        # (401), never a server error; everything else was atomically blocked.
        assert len(admitted) == 1, statuses
        assert admitted[0] == 401, statuses
        assert len(blocked) == n_threads - 1, statuses


# ----------------------------------------------------------------------
# Storage failure: no fail-open path; safe fallback preserved
# ----------------------------------------------------------------------

class _FailingStorage(RateLimitStorage):
    """A primary storage whose every operation raises StorageError."""

    def get(self, bucket, key, window_start):
        raise StorageError("primary down")

    def increment(self, bucket, key, window_start, window):
        raise StorageError("primary down")

    def reset_time(self, bucket, key, window_start, window):
        return window_start + window

    def clear(self):
        raise StorageError("primary down")


class TestStorageFailure:

    def test_fallback_mode_still_enforces_when_primary_down(self):
        """Redis-down with the default 'fallback' policy must keep counting in
        the per-process store -- the limit stays enforced, login is not left
        unthrottled and is not turned into a 503.
        """
        lim = RateLimiter(storage=InMemoryRateLimitStorage())
        lim.configure_bucket("b", 3, 3600)
        lim.use_storage(_FailingStorage(), failure_mode="fallback")

        key = "acct"
        for _ in range(3):
            lim.check("b", key)              # counted in the fallback store
        with pytest.raises(RateLimitExceeded):
            lim.check("b", key)              # still enforced

    def test_closed_mode_raises_unavailable_for_sensitive_bucket(self):
        """With 'closed' policy a sensitive bucket must refuse (not fall open)
        when the shared store is down.
        """
        lim = RateLimiter(storage=InMemoryRateLimitStorage())
        lim.configure_bucket("b", 3, 3600)
        lim.use_storage(_FailingStorage(), failure_mode="closed",
                        sensitive_buckets=("b",))
        with pytest.raises(RateLimitUnavailable):
            lim.check("b", "acct")

    def test_unexpected_limiter_error_fails_closed_at_login(self, client, monkeypatch):
        """If the account gate raises something unexpected, the login must be
        REJECTED (503), never silently admitted unthrottled.
        """
        email = "failclosed@example.com"
        create_logged_in_user(client, name="FailClosed", email=email)

        # Only the account bucket faults; the per-IP gate (same check()) is
        # passed through so this isolates the login route's own handling.
        real_check = auth_mod.limiter.check

        def boom(bucket, key):
            if bucket == ACCOUNT_LOGIN_BUCKET:
                raise RuntimeError("unexpected limiter fault")
            return real_check(bucket, key)

        monkeypatch.setattr(auth_mod.limiter, "check", boom)

        # Even the CORRECT password must not get through while the gate is faulty.
        resp = _post_login(client, email, GOOD_PASSWORD, ip="198.51.100.9")
        assert resp.status_code == 503
        assert "accessToken" not in resp.get_json()

    def test_limiter_unavailable_returns_503_at_login(self, client, monkeypatch):
        email = "unavail@example.com"
        create_logged_in_user(client, name="Unavail", email=email)

        real_check = auth_mod.limiter.check

        def unavailable(bucket, key):
            if bucket == ACCOUNT_LOGIN_BUCKET:
                raise RateLimitUnavailable(bucket)
            return real_check(bucket, key)

        monkeypatch.setattr(auth_mod.limiter, "check", unavailable)
        resp = _post_login(client, email, GOOD_PASSWORD, ip="198.51.100.8")
        assert resp.status_code == 503
