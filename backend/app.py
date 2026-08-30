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
from routes.auth import auth_bp
from routes.trips import trips_bp
from routes.premium import premium_bp
from routes.travel import travel_bp
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


def _rate_limit_key():
    """Resolve the per-request key for rate limiting.

    Authenticated users are keyed by their user id (from a valid JWT) so each
    account gets its own budget; when no valid token is present (e.g. the
    public authentication endpoints), fall back to the client IP. Unknown
    tokens never error here -- they are simply treated as unauthenticated.
    """
    auth_header = request.headers.get("Authorization", "")
    if auth_header.startswith("Bearer "):
        token = auth_header[len("Bearer "):].strip()
        if token:
            try:
                payload = decode_token(token)
                identity = payload.get("sub")
                if identity is not None:
                    return "user:{}".format(identity)
            except Exception:
                pass
    return "ip:{}".format(request.remote_addr or "unknown")


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

    @app.after_request
    def attach_rate_limit_headers(response):
        headers = getattr(g, "rate_limit_headers", None)
        if headers:
            for name, value in headers.items():
                response.headers[name] = value
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
