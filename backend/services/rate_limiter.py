"""Lightweight, dependency-free in-process rate limiter for Tripora.

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
    "auth.verify_email": {"limit": None, "window": 600},
    "auth.resend_verification": {"limit": None, "window": 600},
    "auth.update_current_user": {"limit": None, "window": 600},
    "auth.delete_current_user": {"limit": None, "window": 600},
    "premium.verify_receipt": {"limit": None, "window": 600},
    "premium.dev_activate": {"limit": None, "window": 600},
    "premium.flight_price": {"limit": None, "window": 60},
    "premium.weather_forecast": {"limit": None, "window": 60},
    "travel.search_flights_route": {"limit": None, "window": 600},
    "travel.search_stays_route": {"limit": None, "window": 600},
    "travel.search_cars_route": {"limit": None, "window": 600},
    "DEFAULT_READ": {"limit": None, "window": 60},
}

# Endpoints that are never rate-limited (cheap, essential, read-only).
UNLIMITED_ENDPOINTS = {"home", "health"}

# Endpoints considered "read" operations -> use the read bucket.
READ_ENDPOINTS = {
    "auth.get_current_user",
    "trips.get_trips",
    "trips.get_trip",
    "premium.status",
}


class RateLimitExceeded(Exception):
    """Raised when a request exceeds its bucket's limit."""

    def __init__(self, bucket, limit, reset_at):
        super().__init__(bucket)
        self.bucket = bucket
        self.limit = limit
        self.reset_at = reset_at


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

        count = self.storage.get(bucket_name, key, window_start)
        if count >= limit:
            reset_at = self.storage.reset_time(bucket_name, key, window_start, window)
            raise RateLimitExceeded(bucket_name, limit, reset_at)

        new_count = self.storage.increment(bucket_name, key, window_start, window)
        remaining = max(0, limit - new_count)
        reset_at = self.storage.reset_time(bucket_name, key, window_start, window)

        return {
            "allowed": True,
            "limit": limit,
            "remaining": remaining,
            "reset_at": reset_at,
        }

    def reset(self):
        """Drop all stored counters (used to isolate test budgets)."""
        self.storage.clear()


# Module-level singleton for the application (constructed at app setup).
limiter = RateLimiter()
