import logging
import os
import time

from flask import Flask, g, jsonify, request
from flask_cors import CORS
from flask_migrate import Migrate
from flask_jwt_extended import JWTManager, decode_token
from sqlalchemy import text

from config.database import db
from config.settings import Config
from models.activity_log import ActivityLog
from routes.auth import auth_bp
from routes.trips import trips_bp
from routes.premium import premium_bp
from routes.travel import travel_bp
from routes.admin import admin_bp
from services.rate_limiter import limiter, RateLimitExceeded
logger = logging.getLogger(__name__)


def _configure_logging():
    """Configure root logging for the application.

    Level is read from LOG_LEVEL (default: INFO). In production, wire
    this up to a real log aggregator / file handler as needed.
    """
    level = os.getenv("LOG_LEVEL", "INFO").upper()

    logging.basicConfig(
        level=getattr(logging, level, logging.INFO),
        format="%(asctime)s %(levelname)s [%(name)s] %(message)s",
    )


_configure_logging()


def _jwt_sub():
    """Return the authenticated user id (from a valid JWT) or None.

    Expired/invalid tokens never raise here -- they are simply treated as
    unauthenticated, matching the rate limiter's behaviour.
    """
    auth_header = request.headers.get("Authorization", "")
    if auth_header.startswith("Bearer "):
        token = auth_header[len("Bearer "):].strip()
        if token:
            try:
                payload = decode_token(token)
                identity = payload.get("sub")
                if identity is not None:
                    return str(identity)
            except Exception:
                pass
    return None


def _rate_limit_key():
    """Resolve the per-request key for rate limiting.

    Authenticated users are keyed by their user id (from a valid JWT) so each
    account gets its own budget; when no valid token is present (e.g. the
    public authentication endpoints), fall back to the client IP. Unknown
    tokens never error here -- they are simply treated as unauthenticated.
    """
    identity = _jwt_sub()
    if identity is not None:
        return "user:{}".format(identity)
    return "ip:{}".format(request.remote_addr or "unknown")


def _set_rls_context():
    """Expose the authenticated user id to Postgres Row-Level Security.

    Sets the ``request.jwt.claims.sub`` GUC for the current transaction to the
    JWT user id (see ``migrations/versions/f0e9d8c7b6a5_*.py``). ``SET LOCAL``
    is scoped to the current transaction, so each request gets its own context
    and no value leaks into the next request. Unauthenticated requests leave the
    GUC unset and RLS policies fail closed.
    """
    identity = _jwt_sub()
    if identity is None:
        return
    try:
        db.session.execute(
            # ``SET LOCAL`` cannot take bind parameters on PostgreSQL, so use
            # ``set_config(..., is_local=true)`` which is transaction-scoped in
            # the same way as ``SET LOCAL``.
            text("SELECT set_config('request.jwt.claims.sub', :sub, true)"),
            {"sub": str(identity)},
        )
    except Exception:
        logger.exception("Failed to set RLS context")


# ============================================================
# EXTENSIONS
# ============================================================

jwt = JWTManager()
migrate = Migrate()


# ============================================================
# CREATE APP
# ============================================================

def create_app():

    app = Flask(__name__)

    # ========================================================
    # CONFIGURATION
    # ========================================================

    app.config.from_object(Config)

    # ========================================================
    # CORS
    # ========================================================
    #
    # Expose the rate-limit headers so browser clients can read them.
    # Allowed origins are env-driven via `CORS_ORIGINS` (comma-separated,
    # e.g. the Vercel frontend origin), falling back to local-dev defaults.
    # --------------------------------------------------------

    CORS(app, origins=Config.cors_origins(), expose_headers=[
        "X-RateLimit-Limit",
        "X-RateLimit-Remaining",
        "X-RateLimit-Reset",
        "Retry-After",
    ])

    # ========================================================
    # DATABASE
    # ========================================================

    db.init_app(app)

    # ========================================================
    # JWT
    # ========================================================

    jwt.init_app(app)

    @jwt.unauthorized_loader
    def handle_missing_token(error):
        return jsonify({
            "success": False,
            "message": "Authentication is required.",
            "error": "Missing or invalid credentials.",
        }), 401

    @jwt.invalid_token_loader
    def handle_invalid_token(error):
        return jsonify({
            "success": False,
            "message": "Your session is invalid. Please log in again.",
            "error": "Missing or invalid credentials.",
        }), 401

    @jwt.expired_token_loader
    def handle_expired_token(jwt_header, jwt_payload):
        return jsonify({
            "success": False,
            "message": "Your session has expired. Please log in again.",
        }), 401

    # ========================================================
    # DATABASE MIGRATIONS
    # ========================================================

    migrate.init_app(app, db)

    # ========================================================
    # REGISTER ROUTES
    # ========================================================

    app.register_blueprint(auth_bp)
    app.register_blueprint(trips_bp)
    app.register_blueprint(premium_bp)
    app.register_blueprint(travel_bp)
    app.register_blueprint(admin_bp)

    # ========================================================
    # RATE LIMITING
    # ========================================================
    #
    # Configure the named buckets from Config (environment-driven with safe
    # defaults), then enforce limits in a before_request hook. Authenticated
    # users are keyed by user id; unauthenticated/public traffic is keyed by
    # the client IP. Exceeded requests get HTTP 429 with X-RateLimit-* and
    # Retry-After. Normal read endpoints fall back to the read bucket; the
    # home/health routes are never throttled.
    # --------------------------------------------------------

    for name, settings in Config.rate_limit_buckets().items():
        limiter.configure_bucket(
            name,
            settings["limit"],
            settings["window"],
        )

    @app.before_request
    def enforce_rate_limits():

        if request.method == "OPTIONS":
            return None

        endpoint = request.endpoint
        bucket = limiter.bucket_for(endpoint) if endpoint else None
        if bucket is None:
            return None

        key = _rate_limit_key()
        try:
            result = limiter.check(bucket, key)
        except RateLimitExceeded as exc:

            resp = jsonify({
                "success": False,
                "message": "Rate limit exceeded. Please try again later.",
            })
            resp.status_code = 429

            retry_after = max(0, exc.reset_at - int(time.time()))
            resp.headers["Retry-After"] = str(retry_after)
            resp.headers["X-RateLimit-Limit"] = str(exc.limit)
            resp.headers["X-RateLimit-Remaining"] = "0"
            resp.headers["X-RateLimit-Reset"] = str(exc.reset_at)
            return resp

        if result["limit"] is not None:
            g.rate_limit_headers = {
                "X-RateLimit-Limit": str(result["limit"]),
                "X-RateLimit-Remaining": str(result["remaining"]),
                "X-RateLimit-Reset": str(result["reset_at"]),
            }
        return None

    @app.before_request
    def set_rls_context():
        # Establish the Row-Level Security context for authenticated requests.
        # Runs for every request (including ones the rate limiter skips) before
        # the route handler executes any query.
        if request.method == "OPTIONS":
            return None
        _set_rls_context()
        return None

    @app.after_request
    def attach_rate_limit_headers(response):
        headers = getattr(g, "rate_limit_headers", None)
        if headers:
            for name, value in headers.items():
                response.headers[name] = value
        return response

    # ========================================================
    # REQUEST LOGGING (ANALYTICS)
    # ========================================================
    #
    # When enabled, record each handled request into the activity log as an
    # ``api_request`` event so the admin dashboard can show raw traffic. The
    # page-view beacon writes its own row (and would otherwise double-count),
    # and OPTIONS / health probes are noise, so both are skipped here.
    # --------------------------------------------------------

    @app.after_request
    def record_api_request(response):
        if not Config.REQUEST_LOGGING_ENABLED:
            return response

        endpoint = request.endpoint
        if endpoint == "admin.track_page_view":
            return response
        if request.method == "OPTIONS":
            return response
        if endpoint in ("home", "health"):
            return response

        try:
            row = ActivityLog(
                event_type="api_request",
                path=request.path,
                method=request.method,
                status_code=response.status_code,
                user_id=_jwt_sub(),
                ip_address=request.headers.get(
                    "X-Forwarded-For",
                    request.remote_addr or "",
                ).split(",")[0].strip()[:64] or None,
            )
            db.session.add(row)
            db.session.commit()
        except Exception:
            db.session.rollback()
            logger.exception("Failed to record API request activity")
        return response


    # ========================================================
    # HOME
    # GET /
    # ========================================================

    @app.route("/", methods=["GET"])
    def home():

        return jsonify({
            "success": True,
            "message": "Tripora API is running!",
            "service": "Tripora Backend",
        }), 200

    # ========================================================
    # HEALTH CHECK
    # GET /api/health
    # ========================================================

    @app.route("/api/health", methods=["GET"])
    def health():

        try:

            db.session.execute(
                text("SELECT 1")
            )

            return jsonify({
                "success": True,
                "status": "healthy",
                "database": "connected",
            }), 200

        except Exception as error:

            logger.exception("Health check failed")

            return jsonify({
                "success": False,
                "status": "unhealthy",
                "database": "disconnected",
                "error": "Internal server error.",
            }), 500

    return app


# ============================================================
# APPLICATION INSTANCE
# ============================================================

app = create_app()


# ============================================================
# RUN SERVER
# ============================================================

if __name__ == "__main__":

    app.run(
        host="0.0.0.0",
        port=5000,
        debug=True,
    )
