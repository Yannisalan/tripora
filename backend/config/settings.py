import os
from datetime import timedelta
from urllib.parse import quote_plus

from config import local_safety

# Normal runs load backend/.env as before. TRIPORA_LOCAL_ONLY=1 never loads it
# (it may hold production settings); see config/local_safety.py.
local_safety.load_environment()


class Config:

    # ============================================================
    # DATABASE CONFIGURATION
    # ============================================================

    DB_USER = os.getenv("DB_USER")
    DB_PASSWORD = os.getenv("DB_PASSWORD")
    DB_HOST = os.getenv("DB_HOST")
    DB_PORT = os.getenv("DB_PORT")
    DB_NAME = os.getenv("DB_NAME")

    # ------------------------------------------------------------
    # Validate database configuration
    # ------------------------------------------------------------

    if not DB_USER:
        raise ValueError(
            "DB_USER is not configured."
        )

    if not DB_PASSWORD:
        raise ValueError(
            "DB_PASSWORD is not configured."
        )

    if not DB_HOST:
        raise ValueError(
            "DB_HOST is not configured."
        )

    if not DB_PORT:
        raise ValueError(
            "DB_PORT is not configured."
        )

    if not DB_NAME:
        raise ValueError(
            "DB_NAME is not configured."
        )

    # Local-only mode: refuse any non-loopback host (e.g. Neon) before an
    # engine or connection exists. No-op in deployed environments.
    local_safety.check_database_host(DB_HOST)

    # ------------------------------------------------------------
    # Encode password
    # ------------------------------------------------------------

    password = quote_plus(DB_PASSWORD)

    SQLALCHEMY_DATABASE_URI = (
        f"postgresql+psycopg://{DB_USER}:"
        f"{password}@"
        f"{DB_HOST}:"
        f"{DB_PORT}/"
        f"{DB_NAME}"
    )

    # ============================================================
    # SQLALCHEMY
    # ============================================================

    SQLALCHEMY_TRACK_MODIFICATIONS = False

    # ------------------------------------------------------------
    # Transport security for the database connection.
    #
    # DB_SSLMODE is passed to libpq as ``sslmode``. When it is unset, remote
    # hosts default to "require" so credentials and data never cross the
    # network in plaintext; local hosts (developer machines, CI service
    # containers) default to libpq's own behaviour. Set "verify-full" in
    # production when the provider's CA bundle is available.
    # ------------------------------------------------------------

    _LOCAL_DB_HOSTS = {"localhost", "127.0.0.1", "::1"}

    DB_SSLMODE = (os.getenv("DB_SSLMODE", "") or "").strip() or (
        None if DB_HOST in _LOCAL_DB_HOSTS else "require"
    )

    SQLALCHEMY_ENGINE_OPTIONS = {
        "pool_pre_ping": True,
        "pool_recycle": 300,
    }

    if DB_SSLMODE:
        SQLALCHEMY_ENGINE_OPTIONS["connect_args"] = {"sslmode": DB_SSLMODE}

    # ============================================================
    # REVERSE PROXY
    # ============================================================
    #
    # Number of reverse proxies in front of the app that append to
    # X-Forwarded-For / X-Forwarded-Proto. Render terminates TLS in one proxy
    # hop and sets RENDER=true, so the default there is 1. Elsewhere the
    # default is 0: forwarded headers are ignored, so a client can never spoof
    # its address into the rate limiter or the audit log.
    # ------------------------------------------------------------

    @staticmethod
    def _trusted_proxy_hops():
        raw = os.getenv("TRUSTED_PROXY_HOPS", "")
        if raw.strip():
            try:
                return max(0, int(raw))
            except ValueError:
                return 0
        return 1 if os.getenv("RENDER", "").lower() == "true" else 0

    TRUSTED_PROXY_HOPS = _trusted_proxy_hops.__func__()

    # ============================================================
    # JWT AUTHENTICATION
    # ============================================================

    JWT_SECRET_KEY = os.getenv("JWT_SECRET_KEY")

    if not JWT_SECRET_KEY:
        raise ValueError(
            "JWT_SECRET_KEY is not configured."
        )

    # ------------------------------------------------------------
    # Token lifetimes
    # ------------------------------------------------------------
    # Access tokens are short-lived (default 15 minutes) and are renewed
    # silently with a long-lived, rotating refresh token (default 30 days)
    # so users stay signed in across app restarts until they log out or the
    # refresh token is revoked/expires.
    # ------------------------------------------------------------

    JWT_ACCESS_TOKEN_EXPIRES = timedelta(
        minutes=int(
            os.getenv("JWT_ACCESS_TOKEN_MINUTES", "15") or "15"
        )
    )

    REFRESH_TOKEN_LIFETIME_DAYS = int(
        os.getenv("REFRESH_TOKEN_DAYS", "30") or "30"
    )

    # ============================================================
    # EMAIL / SMTP
    # ============================================================
    MAIL_HOST=os.getenv("MAIL_HOST", "smtp.gmail.com")
    MAIL_PORT=int(os.getenv("MAIL_PORT", "465") or "465")
    MAIL_USE_TLS = os.getenv("MAIL_USE_TLS", "false").lower() in (
        "1", "true", "yes", "on"
    )
    MAIL_USE_SSL = os.getenv("MAIL_USE_SSL", "true").lower() in (
        "1", "true", "yes", "on"
    )

    MAIL_USER = os.getenv("MAIL_USER", "")
    MAIL_PASSWORD = os.getenv("MAIL_PASSWORD", "")
    MAIL_FROM = os.getenv("MAIL_FROM", "")
    MAIL_FROM_NAME = os.getenv("MAIL_FROM_NAME", "Tripora")

    # ============================================================
    # SOCIAL AUTHENTICATION (GOOGLE / APPLE)
    # ============================================================
    #
    # These are the OAuth client IDs the backend accepts as the
    # "audience" of a Google ID token, and the Apple client/service
    # identifier used when verifying an Apple identity token.
    # Configure only the ones you use; empty/unused values are fine.
    # ------------------------------------------------------------

    GOOGLE_CLIENT_ID_ANDROID = os.getenv("GOOGLE_CLIENT_ID_ANDROID", "")
    GOOGLE_CLIENT_ID_IOS = os.getenv("GOOGLE_CLIENT_ID_IOS", "")
    GOOGLE_CLIENT_ID_WEB = os.getenv("GOOGLE_CLIENT_ID_WEB", "")

    APPLE_CLIENT_ID = os.getenv("APPLE_CLIENT_ID", "")

    # ============================================================
    # CORS / ALLOWED ORIGINS
    # ============================================================
    #
    # Comma-separated list of browser origins allowed to call the API.
    # Overridable at deploy time via `CORS_ORIGINS` (e.g. "https://app.example.com").
    # When unset, safe local-development defaults are used. Note: replacing
    # the value wholesale also removes the localhost defaults, so include them
    # if you still need local dev alongside production.
    # ------------------------------------------------------------

    CORS_ORIGINS_ENV = os.getenv("CORS_ORIGINS", "")

    DEFAULT_CORS_ORIGINS = [
        "http://localhost:3000",
        "http://localhost:5000",
        "http://127.0.0.1:3000",
        "http://127.0.0.1:5000",
        "https://api.tripora.example.com",
        "https://tripora.example.com",
        "https://tripora-iota.vercel.app",
    ]

    @classmethod
    def cors_origins(cls):
        """Return the list of allowed CORS origins.

        Uses the `CORS_ORIGINS` env var (comma-separated) when provided,
        otherwise falls back to the local-development defaults.
        """
        raw = cls.CORS_ORIGINS_ENV
        if raw:
            origins = [o.strip() for o in raw.split(",") if o.strip()]
            if origins:
                return origins
        return list(cls.DEFAULT_CORS_ORIGINS)

    # ============================================================
    # ADMIN / ANALYTICS
    # ============================================================
    #
    # Legacy shared secret accepted on `/api/admin/*` data endpoints next to
    # MFA admin sessions. Server-side only: the Flutter app has no admin UI
    # and never sees it. Leave unset to disable the shared-token path.
    # ------------------------------------------------------------

    ADMIN_API_TOKEN = os.getenv("ADMIN_API_TOKEN", "")

    # Transitional: accept the shared ADMIN_API_TOKEN alongside MFA admin
    # sessions. Set to false once an MFA administrator has signed in
    # successfully; then also unset ADMIN_API_TOKEN.
    ADMIN_LEGACY_TOKEN_ENABLED = os.getenv(
        "ADMIN_LEGACY_TOKEN_ENABLED", "true"
    ).lower() in ("1", "true", "yes", "on")

    # When true, the backend records each request into the activity log
    # (the `api_request` event type). Turn it off to reduce write load.
    REQUEST_LOGGING_ENABLED = os.getenv(
        "REQUEST_LOGGING_ENABLED", "true"
    ).lower() in ("1", "true", "yes", "on")

    # ============================================================
    # DUFFEL TRAVEL SEARCH
    # ============================================================
    #
    # Server-only API token for the Duffel travel-search provider. It is never
    # exposed to the client and is only read from the environment at request
    # time by ``services.duffel_service``. An empty/unset value makes the
    # travel-search endpoints fail closed (no data returned).
    # ------------------------------------------------------------

    DUFFEL_API_TOKEN = os.getenv("DUFFEL_API_TOKEN", "")

    # ============================================================
    # TRAVELPAYOUTS FLIGHT PRICES (ANY LOGGED-IN USER)
    # ============================================================
    #
    # Server-only API token for the Travelpayouts (Aviasales) flight price
    # lookups shown on the generated itinerary. It is never exposed to the
    # client and is read at request time by ``services.travelpayouts_service``.
    # An empty/unset value makes the endpoint fail closed.
    # ------------------------------------------------------------

    TRAVELPAYOUTS_API_KEY = os.getenv("TRAVELPAYOUTS_API_KEY", "")

    # ============================================================
    # RATE LIMITING
    # ============================================================
    #
    # Every limit/window is configurable through environment variables
    # with safe, development-friendly defaults below. Values are parsed
    # defensively: anything that fails to parse falls back to the default.
    # Only defaults/MISSING env vars are ever used at runtime; the real
    # .env is never read, printed, or exposed here.
    # ------------------------------------------------------------

    RATE_LIMIT_ENABLED = os.getenv("RATE_LIMIT_ENABLED", "true").lower() in (
        "1", "true", "yes", "on"
    )

    # Shared rate-limit store. Use the Render Key Value *internal* URL
    # (redis://...) or a TLS URL (rediss://...). Unset = per-process memory
    # (fine for local development; logged as an error on Render).
    REDIS_URL = os.getenv("REDIS_URL", "").strip()

    # What to do when Redis is unreachable: "fallback" (count in per-process
    # memory, default) or "closed" (reject security-sensitive buckets with
    # 503). See services/rate_limiter.py.
    RATE_LIMIT_FAILURE_MODE = (
        os.getenv("RATE_LIMIT_FAILURE_MODE", "fallback").strip().lower()
        or "fallback"
    )
    REDIS_RETRY_SECONDS = os.getenv("REDIS_RETRY_SECONDS", "30")

    # Email verification (signed-in): code attempts and resends.
    RATE_LIMIT_VERIFY_LIMIT = os.getenv("RATE_LIMIT_VERIFY_LIMIT", "10")
    RATE_LIMIT_VERIFY_WINDOW = os.getenv("RATE_LIMIT_VERIFY_WINDOW", "900")
    RATE_LIMIT_VERIFY_RESEND_LIMIT = os.getenv(
        "RATE_LIMIT_VERIFY_RESEND_LIMIT", "5")
    RATE_LIMIT_VERIFY_RESEND_WINDOW = os.getenv(
        "RATE_LIMIT_VERIFY_RESEND_WINDOW", "3600")

    # Platform-wide ceiling on AI (Gemini) calls across ALL users, so many
    # accounts together cannot run up unbounded spend.
    RATE_LIMIT_AI_GLOBAL_LIMIT = os.getenv("RATE_LIMIT_AI_GLOBAL_LIMIT", "300")
    RATE_LIMIT_AI_GLOBAL_WINDOW = os.getenv(
        "RATE_LIMIT_AI_GLOBAL_WINDOW", "3600")

    # POST /api/trips/generate  (LLM-triggering, most expensive)
    RATE_LIMIT_GENERATE_LIMIT = os.getenv("RATE_LIMIT_GENERATE_LIMIT", "5")
    RATE_LIMIT_GENERATE_WINDOW = os.getenv("RATE_LIMIT_GENERATE_WINDOW", "600")

    # Authentication endpoints (login / register / verify / resend)
    RATE_LIMIT_AUTH_LIMIT = os.getenv("RATE_LIMIT_AUTH_LIMIT", "10")
    RATE_LIMIT_AUTH_WINDOW = os.getenv("RATE_LIMIT_AUTH_WINDOW", "600")

    # Password reset endpoints (forgot-password flow) -- much tighter than
    # general auth because these are prime brute-force targets.
    RATE_LIMIT_RESET_LIMIT = os.getenv("RATE_LIMIT_RESET_LIMIT", "5")
    RATE_LIMIT_RESET_WINDOW = os.getenv("RATE_LIMIT_RESET_WINDOW", "900")

    # AI activity swap (one Gemini call chain per request)
    RATE_LIMIT_AI_SWAP_LIMIT = os.getenv("RATE_LIMIT_AI_SWAP_LIMIT", "20")
    RATE_LIMIT_AI_SWAP_WINDOW = os.getenv("RATE_LIMIT_AI_SWAP_WINDOW", "600")

    # Admin API (shared-secret auth; keyed by client IP) -- prevents online
    # guessing of ADMIN_API_TOKEN.
    RATE_LIMIT_ADMIN_LIMIT = os.getenv("RATE_LIMIT_ADMIN_LIMIT", "60")
    RATE_LIMIT_ADMIN_WINDOW = os.getenv("RATE_LIMIT_ADMIN_WINDOW", "600")

    # Other write/mutation endpoints
    RATE_LIMIT_WRITE_LIMIT = os.getenv("RATE_LIMIT_WRITE_LIMIT", "30")
    RATE_LIMIT_WRITE_WINDOW = os.getenv("RATE_LIMIT_WRITE_WINDOW", "600")

    # Normal GET/read endpoints
    RATE_LIMIT_READ_LIMIT = os.getenv("RATE_LIMIT_READ_LIMIT", "60")
    RATE_LIMIT_READ_WINDOW = os.getenv("RATE_LIMIT_READ_WINDOW", "60")

    # Buckets that reject with 503 instead of falling back when Redis is down
    # and RATE_LIMIT_FAILURE_MODE=closed.
    SENSITIVE_RATE_LIMIT_BUCKETS = (
        "auth.login",
        "auth.register",
        "auth.social_login",
        "auth.google_login",
        "auth.refresh",
        "auth.forgot_password",
        "auth.verify_reset_code",
        "auth.reset_password",
        "auth.verify_email",
        "auth.resend_verification_email",
        "auth.delete_current_user",
        "admin.login_status",
        "admin_auth.admin_login",
        "admin_auth.admin_mfa_setup",
        "admin_auth.admin_mfa_activate",
        "admin_auth.admin_mfa_verify",
        "trips.generate_trip",
        "trips.regenerate_trip_itinerary",
        "trips.swap_activity",
        "AI_GLOBAL",
    )

    @staticmethod
    def _rate_int(value, default):
        try:
            return int(value)
        except (TypeError, ValueError):
            return default

    @classmethod
    def google_client_ids(cls):
        """Return the non-empty list of accepted Google OAuth client IDs.

        A Google ID token's ``aud`` must match one of these.
        """
        return [
            os.getenv("GOOGLE_CLIENT_ID_ANDROID", ""),
            os.getenv("GOOGLE_CLIENT_ID_IOS", ""),
            os.getenv("GOOGLE_CLIENT_ID_WEB", ""),
        ]

    @classmethod
    def apple_client_id(cls):
        """Return the Apple client/service identifier used for verification."""
        return os.getenv("APPLE_CLIENT_ID", "")

    @classmethod
    def _bucket(cls, limit_value, window_value, default_limit, default_window):
        """Parse one bucket's limit/window with safe fallbacks."""
        return {
            "limit": cls._rate_int(limit_value, default_limit),
            "window": cls._rate_int(window_value, default_window),
        }

    @classmethod
    def rate_limit_buckets(cls):
        """Build the named-bucket config consumed by the rate limiter.

        Returns a dict of {endpoint_name: {"limit": N, "window": seconds}}
        using the environment-configured values (or safe defaults).
        Only the blueprint endpoints that should be throttled are listed;
        unlimited/unselected routes are left out on purpose.
        """
        if not cls.RATE_LIMIT_ENABLED:
            return {}

        G = cls.RATE_LIMIT_GENERATE_LIMIT
        G_W = cls.RATE_LIMIT_GENERATE_WINDOW
        A = cls.RATE_LIMIT_AUTH_LIMIT
        A_W = cls.RATE_LIMIT_AUTH_WINDOW
        RESET = cls.RATE_LIMIT_RESET_LIMIT
        RESET_W = cls.RATE_LIMIT_RESET_WINDOW
        W = cls.RATE_LIMIT_WRITE_LIMIT
        W_W = cls.RATE_LIMIT_WRITE_WINDOW
        R = cls.RATE_LIMIT_READ_LIMIT
        R_W = cls.RATE_LIMIT_READ_WINDOW
        SW = cls.RATE_LIMIT_AI_SWAP_LIMIT
        SW_W = cls.RATE_LIMIT_AI_SWAP_WINDOW
        AD = cls.RATE_LIMIT_ADMIN_LIMIT
        AD_W = cls.RATE_LIMIT_ADMIN_WINDOW
        V = cls.RATE_LIMIT_VERIFY_LIMIT
        V_W = cls.RATE_LIMIT_VERIFY_WINDOW
        VR = cls.RATE_LIMIT_VERIFY_RESEND_LIMIT
        VR_W = cls.RATE_LIMIT_VERIFY_RESEND_WINDOW
        AIG = cls.RATE_LIMIT_AI_GLOBAL_LIMIT
        AIG_W = cls.RATE_LIMIT_AI_GLOBAL_WINDOW

        return {
            # ---- expensive / LLM-triggering: POST /api/trips/generate ----
            "trips.generate_trip": cls._bucket(G, G_W, 5, 600),
            "trips.regenerate_trip_itinerary": cls._bucket(W, W_W, 30, 600),
            "trips.update_trip": cls._bucket(W, W_W, 30, 600),
            "trips.delete_trip": cls._bucket(W, W_W, 30, 600),
            "trips.swap_activity": cls._bucket(SW, SW_W, 20, 600),
            # ---- authentication endpoints ----
            "auth.login": cls._bucket(A, A_W, 10, 600),
            "auth.register": cls._bucket(A, A_W, 10, 600),
            "auth.social_login": cls._bucket(A, A_W, 10, 600),
            "auth.google_login": cls._bucket(A, A_W, 10, 600),
            "auth.refresh": cls._bucket(A, A_W, 10, 600),
            "auth.logout": cls._bucket(A, A_W, 10, 600),
            "auth.update_current_user": cls._bucket(W, W_W, 30, 600),
            "auth.delete_current_user": cls._bucket(A, A_W, 5, 600),
            # ---- email verification (per signed-in user) ----
            "auth.verify_email": cls._bucket(V, V_W, 10, 900),
            "auth.resend_verification_email": cls._bucket(VR, VR_W, 5, 3600),
            # ---- password reset (tight; brute-force target) ----
            "auth.forgot_password": cls._bucket(RESET, RESET_W, 5, 900),
            "auth.verify_reset_code": cls._bucket(RESET, RESET_W, 5, 900),
            "auth.reset_password": cls._bucket(RESET, RESET_W, 5, 900),
            # ---- travel search (Duffel-backed, third-party cost) ----
            "travel.search_flights_route": cls._bucket(A, A_W, 10, 600),
            "travel.search_stays_route": cls._bucket(A, A_W, 10, 600),
            "travel.search_cars_route": cls._bucket(A, A_W, 10, 600),
            "travel.flight_prices_route": cls._bucket(A, A_W, 10, 600),
            # ---- currency rates (cached upstream; public) ----
            "rates.get_rates": cls._bucket(R, R_W, 60, 60),
            "rates.get_single_rate": cls._bucket(R, R_W, 60, 60),
            # ---- Turnstile config + Android challenge page (no DB) ----
            "turnstile.turnstile_config": cls._bucket(R, R_W, 60, 60),
            "turnstile.turnstile_challenge": cls._bucket(R, R_W, 60, 60),
            # ---- smart trip expense tracker ----
            "expenses.get_trip_expenses": cls._bucket(R, R_W, 60, 60),
            "expenses.get_expense": cls._bucket(R, R_W, 60, 60),
            "expenses.create_expense": cls._bucket(W, W_W, 30, 600),
            "expenses.update_expense": cls._bucket(W, W_W, 30, 600),
            "expenses.delete_expense": cls._bucket(W, W_W, 30, 600),
            # ---- public page-view beacon ----
            # One event per screen visit, so it needs a read-sized budget.
            "admin.track_page_view": cls._bucket(R, R_W, 60, 60),
            # ---- admin API (shared secret; per-IP guessing budget) ----
            "admin.login_status": cls._bucket(A, A_W, 10, 600),
            "admin.stats": cls._bucket(AD, AD_W, 60, 600),
            "admin.users_list": cls._bucket(AD, AD_W, 60, 600),
            "admin.trips_list": cls._bucket(AD, AD_W, 60, 600),
            "admin.logs": cls._bucket(AD, AD_W, 60, 600),
            # ---- admin sign-in (password + TOTP; per IP) ----
            "admin_auth.admin_login": cls._bucket(A, A_W, 10, 600),
            "admin_auth.admin_mfa_setup": cls._bucket(A, A_W, 10, 600),
            "admin_auth.admin_mfa_activate": cls._bucket(A, A_W, 10, 600),
            "admin_auth.admin_mfa_verify": cls._bucket(A, A_W, 10, 600),
            "admin_auth.admin_regenerate_recovery_codes": cls._bucket(
                A, A_W, 10, 600),
            "admin_auth.admin_me": cls._bucket(AD, AD_W, 60, 600),
            "admin_auth.admin_logout": cls._bucket(AD, AD_W, 60, 600),
            # ---- browser CSP violation reports (public) ----
            "csp_report": cls._bucket(R, R_W, 60, 60),
            # ---- platform-wide AI ceiling (key: "global") ----
            "AI_GLOBAL": cls._bucket(AIG, AIG_W, 300, 3600),
            # ---- weather forecast (Open-Meteo, read-heavy) ----
            "weather.get_trip_weather": cls._bucket(R, R_W, 60, 60),
            # ---- default buckets ----
            # Applied by app.enforce_rate_limits to any endpoint that has no
            # bucket of its own, so a newly added route is never unlimited.
            "DEFAULT_READ": cls._bucket(R, R_W, 60, 60),
            "DEFAULT_WRITE": cls._bucket(W, W_W, 30, 600),
        }