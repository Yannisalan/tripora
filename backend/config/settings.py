import os
from urllib.parse import quote_plus

from dotenv import load_dotenv


load_dotenv()


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

    # ============================================================
    # JWT AUTHENTICATION
    # ============================================================

    JWT_SECRET_KEY = os.getenv("JWT_SECRET_KEY")

    if not JWT_SECRET_KEY:
        raise ValueError(
            "JWT_SECRET_KEY is not configured."
        )

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
    # A single shared secret that gates every `/api/admin/*` endpoint. The
    # Flutter admin UI presents this to whoever runs the product; it is never
    # returned to normal app users. Leave unset to disable the admin API.
    # ------------------------------------------------------------

    ADMIN_API_TOKEN = os.getenv("ADMIN_API_TOKEN", "")

    # When true, the backend records each request into the activity log
    # (the `api_request` event type). Turn it off to reduce write load.
    REQUEST_LOGGING_ENABLED = os.getenv(
        "REQUEST_LOGGING_ENABLED", "true"
    ).lower() in ("1", "true", "yes", "on")

    # ============================================================
    # DUFFEL TRAVEL SEARCH (PREMIUM)
    # ============================================================
    #
    # Server-only API token for the Duffel travel-search provider. It is never
    # exposed to the client and is only read from the environment at request
    # time by ``services.duffel_service``. An empty/unset value makes the
    # premium travel-search endpoints fail closed (no data returned).
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

    # POST /api/trips/generate  (LLM-triggering, most expensive)
    RATE_LIMIT_GENERATE_LIMIT = os.getenv("RATE_LIMIT_GENERATE_LIMIT", "5")
    RATE_LIMIT_GENERATE_WINDOW = os.getenv("RATE_LIMIT_GENERATE_WINDOW", "600")

    # Authentication endpoints (login / register / verify / resend)
    RATE_LIMIT_AUTH_LIMIT = os.getenv("RATE_LIMIT_AUTH_LIMIT", "10")
    RATE_LIMIT_AUTH_WINDOW = os.getenv("RATE_LIMIT_AUTH_WINDOW", "600")

    # Other write/mutation endpoints
    RATE_LIMIT_WRITE_LIMIT = os.getenv("RATE_LIMIT_WRITE_LIMIT", "30")
    RATE_LIMIT_WRITE_WINDOW = os.getenv("RATE_LIMIT_WRITE_WINDOW", "600")

    # Normal GET/read endpoints
    RATE_LIMIT_READ_LIMIT = os.getenv("RATE_LIMIT_READ_LIMIT", "60")
    RATE_LIMIT_READ_WINDOW = os.getenv("RATE_LIMIT_READ_WINDOW", "60")

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
        W = cls.RATE_LIMIT_WRITE_LIMIT
        W_W = cls.RATE_LIMIT_WRITE_WINDOW
        R = cls.RATE_LIMIT_READ_LIMIT
        R_W = cls.RATE_LIMIT_READ_WINDOW

        return {
            # ---- expensive / LLM-triggering: POST /api/trips/generate ----
            "trips.generate_trip": cls._bucket(G, G_W, 5, 600),
            "trips.regenerate_trip_itinerary": cls._bucket(W, W_W, 30, 600),
            "trips.update_trip": cls._bucket(W, W_W, 30, 600),
            "trips.delete_trip": cls._bucket(W, W_W, 30, 600),
            # ---- authentication endpoints ----
            "auth.login": cls._bucket(A, A_W, 10, 600),
            "auth.register": cls._bucket(A, A_W, 10, 600),
            "auth.social_login": cls._bucket(A, A_W, 10, 600),
            "auth.update_current_user": cls._bucket(W, W_W, 30, 600),
            "auth.delete_current_user": cls._bucket(A, A_W, 5, 600),
            # ---- premium / IAP endpoints ----
            "premium.verify_receipt": cls._bucket(W, W_W, 30, 600),
            "premium.dev_activate": cls._bucket(W, W_W, 30, 600),
            "premium.flight_price": cls._bucket(R, R_W, 60, 60),
            "premium.weather_forecast": cls._bucket(R, R_W, 60, 60),
            # ---- premium travel search (Duffel-backed, third-party cost) ----
            "travel.search_flights_route": cls._bucket(A, A_W, 10, 600),
            "travel.search_stays_route": cls._bucket(A, A_W, 10, 600),
            "travel.search_cars_route": cls._bucket(A, A_W, 10, 600),
            # ---- public page-view beacon ----
            "admin.track_page_view": cls._bucket(A, A_W, 10, 600),
            # ---- default read bucket ----
            "DEFAULT_READ": cls._bucket(R, R_W, 60, 60),
        }