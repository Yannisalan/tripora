"""Redis-backed rate limiting against a real Redis server (TRP-18).

Opt-in: set TRIPORA_TEST_REDIS_URL (e.g. redis://127.0.0.1:56379/15). CI
provides a Redis service container. Uses a dedicated key prefix and only
deletes its own keys.
"""

import os
import threading
import time
import uuid

import pytest

REDIS_URL = os.getenv("TRIPORA_TEST_REDIS_URL", "")

pytestmark = pytest.mark.skipif(
    not REDIS_URL, reason="TRIPORA_TEST_REDIS_URL not set"
)


@pytest.fixture
def redis_client():
    import redis

    client = redis.Redis.from_url(REDIS_URL, socket_timeout=2)
    client.ping()
    yield client
    client.close()


@pytest.fixture
def prefix(redis_client):
    value = "tripora:test:{}:".format(uuid.uuid4().hex[:8])
    yield value
    for key in redis_client.scan_iter(value + "*"):
        redis_client.delete(key)


def _limiter(redis_client, prefix, limit=5, window=60, **policy):
    from services.rate_limiter import RateLimiter, RedisRateLimitStorage

    rl = RateLimiter(buckets={})
    rl.configure_bucket("auth.login", limit, window)
    rl.use_storage(RedisRateLimitStorage(redis_client, prefix=prefix), **policy)
    return rl


def test_counters_are_shared_between_workers(redis_client, prefix):
    from services.rate_limiter import RateLimitExceeded

    worker_a = _limiter(redis_client, prefix)
    worker_b = _limiter(redis_client, prefix)  # separate process stand-in

    for i in range(5):
        (worker_a if i % 2 else worker_b).check("auth.login", "ip:203.0.113.1")
    with pytest.raises(RateLimitExceeded):
        worker_a.check("auth.login", "ip:203.0.113.1")
    with pytest.raises(RateLimitExceeded):
        worker_b.check("auth.login", "ip:203.0.113.1")


def test_state_survives_a_new_limiter_instance(redis_client, prefix):
    from services.rate_limiter import RateLimitExceeded

    for _ in range(5):
        _limiter(redis_client, prefix).check("auth.login", "ip:x")
    # "Restarted" app: brand-new limiter object, same Redis.
    with pytest.raises(RateLimitExceeded):
        _limiter(redis_client, prefix).check("auth.login", "ip:x")


def test_increment_is_atomic_under_concurrency(redis_client, prefix):
    from services.rate_limiter import RateLimitExceeded

    limit = 10
    allowed = []
    lock = threading.Lock()

    def hit():
        rl = _limiter(redis_client, prefix, limit=limit)
        try:
            rl.check("auth.login", "ip:race")
            with lock:
                allowed.append(1)
        except RateLimitExceeded:
            pass

    threads = [threading.Thread(target=hit) for _ in range(60)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    assert len(allowed) == limit


def test_keys_expire_with_the_window(redis_client, prefix):
    _limiter(redis_client, prefix, window=60).check("auth.login", "ip:ttl")
    keys = list(redis_client.scan_iter(prefix + "*"))
    assert keys
    ttl = redis_client.ttl(keys[0])
    assert 0 < ttl <= 61


def test_unreachable_redis_falls_back_and_still_limits(prefix):
    import redis
    from services.rate_limiter import RateLimitExceeded

    from redis.backoff import NoBackoff
    from redis.retry import Retry

    dead = redis.Redis(host="127.0.0.1", port=1, socket_connect_timeout=0.2,
                       socket_timeout=0.2, retry=Retry(NoBackoff(), 0))
    rl = _limiter(dead, prefix, limit=3, failure_mode="fallback",
                  sensitive_buckets={"auth.login"})
    rl.check("auth.login", "ip:down")      # pays the one connect failure
    started = time.time()
    for _ in range(2):
        rl.check("auth.login", "ip:down")
    with pytest.raises(RateLimitExceeded):
        rl.check("auth.login", "ip:down")
    # Circuit breaker: later requests skip the dead Redis entirely.
    assert time.time() - started < 0.5


def test_unreachable_redis_closed_mode_rejects(prefix):
    import redis
    from services.rate_limiter import RateLimitUnavailable

    from redis.backoff import NoBackoff
    from redis.retry import Retry

    dead = redis.Redis(host="127.0.0.1", port=1, socket_connect_timeout=0.2,
                       socket_timeout=0.2, retry=Retry(NoBackoff(), 0))
    rl = _limiter(dead, prefix, failure_mode="closed",
                  sensitive_buckets={"auth.login"})
    with pytest.raises(RateLimitUnavailable):
        rl.check("auth.login", "ip:down")


def test_app_uses_redis_when_configured(app, monkeypatch, redis_client):
    """REDIS_URL wires the app's limiter to Redis (and back afterwards)."""
    import app as app_module
    import config.settings as settings_mod
    from services.rate_limiter import (
        InMemoryRateLimitStorage,
        RedisRateLimitStorage,
        limiter,
    )

    monkeypatch.setattr(settings_mod.Config, "REDIS_URL", REDIS_URL)
    previous = limiter.storage
    try:
        app_module._configure_rate_limit_storage()
        assert isinstance(limiter.storage, RedisRateLimitStorage)
    finally:
        limiter.use_storage(previous if previous is not None
                            else InMemoryRateLimitStorage())
