"""Fixed-window rate limiter for Tripora with a shared (Redis) backend.

Storage backends
----------------
- ``RedisRateLimitStorage``: production backend. Counters are shared by every
  Gunicorn worker and instance and survive app restarts (subject to the Redis
  instance's own persistence). Each request is ONE atomic MULTI/EXEC:
  ``SET key 0 EX window NX`` + ``INCR key``.
- ``InMemoryRateLimitStorage``: per-process backend for local development,
  tests, and as the controlled fallback when Redis is unreachable.

Redis failure strategy (``RATE_LIMIT_FAILURE_MODE``)
-----------------------------------------------------
- ``fallback`` (default): when Redis errors, the request is counted in the
  per-process in-memory store instead. Limits stay enforced (per worker, so
  up to N-workers times looser) and an ERROR is logged. Login, reset and AI
  endpoints therefore never become unlimited, and a Redis outage does not take
  authentication down with it.
- ``closed``: for security-sensitive buckets (authentication, password reset,
  email verification, admin, AI) a Redis error rejects the request with 503
  instead; other buckets still use the in-memory fallback.

After a Redis error the backend is skipped for a short cool-down
(``REDIS_RETRY_SECONDS``) so a dead Redis does not add a timeout to every
request.

Original design notes
---------------------

Design
------
- ``RateLimitStorage`` is the replaceable storage interface. The shipped
  ``InMemoryRateLimitStorage`` keeps counters in a bounded, thread-safe dict
  suitable for local development / a single process.
- To deploy across multiple instances, implement the same interface against a
  shared store (e.g. Redis using INCR + EXPIRE for fixed windows, or a
  Lua-based sliding window) and construct the limiter with it. Nothing else in
  the application changes.
- Uses a simple fixed-window counter: ``count`` per (bucket, key, window_start).
  Window boundaries are computed from ``time.time()`` so the window is aligned
  to wall-clock intervals. When the count reaches the ``limit`` the request is
  refused until the window rolls over.

Not production Redis — this is the local/default backend. It is intentionally
small and self-contained (no third-party dependencies).
"""

import time
import threading
from abc import ABC, abstractmethod

import logging

logger = logging.getLogger(__name__)

# Default bucket definitions. Each bucket pairs a human-readable name with an
# optional per-route limit/window (in seconds). A bucket with ``limit=None`` is
# unlimited (used for read endpoints we do not throttle). The actual numbers
# come from ``Config`` at app setup time; these are only structural fallbacks.
DEFAULT_BUCKETS = {
    "trips.generate_trip": {"limit": None, "window": 600},
    "trips.regenerate_trip_itinerary": {"limit": None, "window": 600},
    "trips.update_trip": {"limit": None, "window": 600},
    "trips.delete_trip": {"limit": None, "window": 600},
    "auth.login": {"limit": None, "window": 600},
    "auth.register": {"limit": None, "window": 600},
    "auth.social_login": {"limit": None, "window": 600},
    "auth.forgot_password": {"limit": None, "window": 900},
    "auth.forgot_password_verify": {"limit": None, "window": 900},
    "auth.reset_password": {"limit": None, "window": 900},
    "auth.update_current_user": {"limit": None, "window": 600},
    "auth.delete_current_user": {"limit": None, "window": 600},
    "travel.search_flights_route": {"limit": None, "window": 600},
    "travel.search_stays_route": {"limit": None, "window": 600},
    "travel.search_cars_route": {"limit": None, "window": 600},
    "travel.flight_prices_route": {"limit": None, "window": 600},
    "rates.get_rates": {"limit": None, "window": 60},
    "rates.get_single_rate": {"limit": None, "window": 60},
    "expenses.get_trip_expenses": {"limit": None, "window": 60},
    "expenses.get_expense": {"limit": None, "window": 60},
    "expenses.create_expense": {"limit": None, "window": 600},
    "expenses.update_expense": {"limit": None, "window": 600},
    "expenses.delete_expense": {"limit": None, "window": 600},
    "DEFAULT_READ": {"limit": None, "window": 60},
}

# Endpoints that are never rate-limited (cheap, essential, read-only).
UNLIMITED_ENDPOINTS = {"home", "health"}

# Endpoints considered "read" operations -> use the read bucket.
READ_ENDPOINTS = {
    "auth.get_current_user",
    "trips.get_trips",
    "trips.get_trip",
}


class RateLimitExceeded(Exception):
    """Raised when a request exceeds its bucket's limit."""

    def __init__(self, bucket, limit, reset_at):
        super().__init__(bucket)
        self.bucket = bucket
        self.limit = limit
        self.reset_at = reset_at


class RateLimitUnavailable(Exception):
    """Raised in ``closed`` failure mode when the shared store is down."""

    def __init__(self, bucket):
        super().__init__(bucket)
        self.bucket = bucket


class StorageError(Exception):
    """A storage backend could not complete an operation."""


class RateLimitStorage(ABC):
    """Interface for persisting/reading rate-limit counters.

    Implementations must be safe to call from the request thread.
    """

    @abstractmethod
    def get(self, bucket, key, window_start):
        """Return the number of requests counted for (bucket, key, window)."""

    @abstractmethod
    def increment(self, bucket, key, window_start, window):
        """Record one request and return the new count for the window."""

    @abstractmethod
    def reset_time(self, bucket, key, window_start, window):
        """Return the absolute epoch time the current window resets."""

    @abstractmethod
    def clear(self):
        """Drop all counters (used to isolate test budgets)."""


class InMemoryRateLimitStorage(RateLimitStorage):
    """Thread-safe in-memory (process-local) implementation.

    Counters are stored under a ``(bucket, key)`` key with a ``window_start``.
    Entries for windows other than the current one are ignored (and lazily
    overwritten), so memory stays bounded per active key/bucket.
    """

    def __init__(self):
        self._lock = threading.Lock()
        # maps (bucket, key) -> {"window_start": int, "count": int}
        self._data = {}

    def get(self, bucket, key, window_start):
        with self._lock:
            entry = self._data.get((bucket, key))
            if entry is None or entry["window_start"] != window_start:
                return 0
            return entry["count"]

    def increment(self, bucket, key, window_start, window):
        with self._lock:
            entry = self._data.get((bucket, key))
            if entry is None or entry["window_start"] != window_start:
                entry = {"window_start": window_start, "count": 0}
                self._data[(bucket, key)] = entry
            entry["count"] += 1
            return entry["count"]

    def reset_time(self, bucket, key, window_start, window):
        return window_start + window

    def clear(self):
        with self._lock:
            self._data.clear()

    def clear_key(self, bucket, key):
        """Drop the counter for a single (bucket, key) across all windows."""
        with self._lock:
            self._data.pop((bucket, key), None)


class RedisRateLimitStorage(RateLimitStorage):
    """Shared fixed-window counters in Redis (atomic per request)."""

    def __init__(self, client, prefix="tripora:rl:"):
        self._client = client
        self._prefix = prefix

    def _key(self, bucket, key, window_start):
        return "{}{}:{}:{}".format(self._prefix, bucket, key, window_start)

    def get(self, bucket, key, window_start):
        try:
            value = self._client.get(self._key(bucket, key, window_start))
        except Exception as error:  # redis.RedisError, OSError, ...
            raise StorageError(str(error)) from error
        return int(value or 0)

    def increment(self, bucket, key, window_start, window):
        redis_key = self._key(bucket, key, window_start)
        try:
            pipe = self._client.pipeline(transaction=True)
            # Create the counter with its TTL only if it does not exist yet,
            # then increment -- both inside one MULTI/EXEC.
            pipe.set(redis_key, 0, ex=int(window) + 1, nx=True)
            pipe.incr(redis_key)
            _, count = pipe.execute()
        except Exception as error:
            raise StorageError(str(error)) from error
        return int(count)

    def reset_time(self, bucket, key, window_start, window):
        return window_start + window

    def clear(self):
        try:
            for redis_key in self._client.scan_iter(self._prefix + "*"):
                self._client.delete(redis_key)
        except Exception as error:
            raise StorageError(str(error)) from error

    def clear_key(self, bucket, key):
        """Drop the counter for a single (bucket, key) across all windows."""
        pattern = "{}{}:{}:*".format(self._prefix, bucket, key)
        try:
            for redis_key in self._client.scan_iter(pattern):
                self._client.delete(redis_key)
        except Exception as error:
            raise StorageError(str(error)) from error


class RateLimiter:
    """Applies per-bucket fixed-window limits.

    Buckets are looked up by a human-readable name (usually the Flask endpoint
    name). A bucket may be defined with ``{"limit": N, "window": seconds}``.
    ``None`` limit means unlimited. Unknown endpoints are NOT limited so that
    adding routes never silently throttles them; read/write defaults are
    applied only to explicitly selected endpoints.
    """

    def __init__(self, storage=None, buckets=None):
        self.storage = storage or InMemoryRateLimitStorage()
        self._buckets = dict(buckets or DEFAULT_BUCKETS)
        # Controlled fallback used when a shared backend fails.
        self.fallback_storage = InMemoryRateLimitStorage()
        self.failure_mode = "fallback"
        self.sensitive_buckets = set()
        self.retry_seconds = 30
        self._primary_down_until = 0.0
        self._lock = threading.Lock()

    def use_storage(self, storage, failure_mode="fallback",
                    sensitive_buckets=(), retry_seconds=30):
        """Install a (shared) primary backend and its failure policy."""
        if failure_mode not in ("fallback", "closed"):
            failure_mode = "fallback"
        self.storage = storage
        self.failure_mode = failure_mode
        self.sensitive_buckets = set(sensitive_buckets)
        self.retry_seconds = retry_seconds
        self._primary_down_until = 0.0

    def _peek_count(self, bucket_name, key, window_start):
        """Read the current window count WITHOUT incrementing it.

        Mirrors ``_count``'s choice of backend (primary unless its circuit
        breaker is open, otherwise the in-memory fallback) so a read sees the
        same counter a write would touch. A read never trips the breaker: a
        transient read error just falls back to the local store.
        """
        primary_is_local = isinstance(self.storage, InMemoryRateLimitStorage)

        if primary_is_local or time.time() >= self._primary_down_until:
            try:
                return self.storage.get(bucket_name, key, window_start)
            except StorageError:
                logger.error(
                    "Rate-limit store unavailable on read; using fallback."
                )

        return self.fallback_storage.get(bucket_name, key, window_start)

    def _count(self, bucket_name, key, window_start, window):
        """Atomically record one request and return the window count."""
        primary_is_local = isinstance(self.storage, InMemoryRateLimitStorage)

        if primary_is_local or time.time() >= self._primary_down_until:
            try:
                return self.storage.increment(
                    bucket_name, key, window_start, window
                )
            except StorageError:
                with self._lock:
                    self._primary_down_until = (
                        time.time() + self.retry_seconds
                    )
                logger.error(
                    "Rate-limit store unavailable; using %s mode for %ss.",
                    self.failure_mode,
                    self.retry_seconds,
                )

        if (
            self.failure_mode == "closed"
            and bucket_name in self.sensitive_buckets
        ):
            raise RateLimitUnavailable(bucket_name)

        return self.fallback_storage.increment(
            bucket_name, key, window_start, window
        )

    # ------------------------------------------------------------------
    # Bucket resolution
    # ------------------------------------------------------------------

    def configure_bucket(self, name, limit, window):
        """Set/override a bucket's (limit, window). Limit None = unlimited."""
        if limit is None:
            self._buckets[name] = {"limit": None, "window": int(window)}
        else:
            self._buckets[name] = {"limit": int(limit), "window": int(window)}

    def bucket_for(self, endpoint):
        """Return the bucket name for a Flask endpoint, or None if unlimited."""
        if endpoint in UNLIMITED_ENDPOINTS:
            return None
        if endpoint in self._buckets:
            return endpoint
        if endpoint in READ_ENDPOINTS:
            return "DEFAULT_READ"
        return None

    def _settings(self, bucket_name):
        return self._buckets.get(bucket_name)

    # ------------------------------------------------------------------
    # Enforcement
    # ------------------------------------------------------------------

    def check(self, bucket_name, key):
        """Check and record a request.

        Returns dict with keys: allowed, limit, remaining, reset_at.
        Raises RateLimitExceeded when the limit has already been reached.
        """
        settings = self._settings(bucket_name)
        if settings is None or settings.get("limit") is None:
            return {
                "allowed": True,
                "limit": None,
                "remaining": None,
                "reset_at": None,
            }

        limit = settings["limit"]
        window = settings["window"]

        now = int(time.time())
        window_start = (now // window) * window
        reset_at = window_start + window

        # Increment first, then compare: a single atomic operation, so
        # concurrent requests (across workers, with Redis) can never all
        # observe "one left" and overshoot the limit.
        new_count = self._count(bucket_name, key, window_start, window)
        if new_count > limit:
            raise RateLimitExceeded(bucket_name, limit, reset_at)

        remaining = max(0, limit - new_count)

        return {
            "allowed": True,
            "limit": limit,
            "remaining": remaining,
            "reset_at": reset_at,
        }

    def peek(self, bucket_name, key):
        """Report a bucket's current state for ``key`` WITHOUT counting.

        Returns a dict with ``count``, ``limit``, ``window``, ``reset_at`` and
        ``exceeded`` (True once ``count`` has reached ``limit``). An unlimited
        or unknown bucket is never exceeded. Used as a read-only gate that can
        reject an attempt before any side effect (e.g. before verifying a
        password), so the gate itself never consumes budget.
        """
        settings = self._settings(bucket_name)
        if settings is None or settings.get("limit") is None:
            return {
                "count": 0,
                "limit": None,
                "window": None,
                "reset_at": None,
                "exceeded": False,
            }

        limit = settings["limit"]
        window = settings["window"]

        now = int(time.time())
        window_start = (now // window) * window

        count = self._peek_count(bucket_name, key, window_start)

        return {
            "count": count,
            "limit": limit,
            "window": window,
            "reset_at": window_start + window,
            "exceeded": count >= limit,
        }

    def reset_key(self, bucket_name, key):
        """Drop a single key's counter in both the primary and fallback stores.

        Used to clear an account's failed-attempt budget after a *successful*
        login, so legitimate authentication is never penalised by earlier
        failures. Best-effort: a storage error here is logged and swallowed
        (the login has already succeeded; a lingering counter only means the
        next failed attempt counts from a slightly higher base).
        """
        for store in (self.storage, self.fallback_storage):
            clear_key = getattr(store, "clear_key", None)
            if clear_key is None:
                continue
            try:
                clear_key(bucket_name, key)
            except StorageError:
                logger.error("Could not reset rate-limit key for %s", bucket_name)
            except Exception:  # noqa: BLE001 - never let cleanup break a login
                logger.exception(
                    "Unexpected error resetting rate-limit key for %s",
                    bucket_name,
                )

    def reset(self):
        """Drop all stored counters (used to isolate test budgets)."""
        self.storage.clear()
        self.fallback_storage.clear()
        self._primary_down_until = 0.0


# Module-level singleton for the application (constructed at app setup).
limiter = RateLimiter()
