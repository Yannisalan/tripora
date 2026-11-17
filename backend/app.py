import logging
import os
import time

from flask import Flask, g, jsonify, request
from flask_cors import CORS
from flask_migrate import Migrate
from flask_jwt_extended import (
    JWTManager,
    decode_token,
    get_jwt_identity,
    verify_jwt_in_request,
)
from sqlalchemy import text
from werkzeug.exceptions import HTTPException
from werkzeug.middleware.proxy_fix import ProxyFix

from config.database import db
from config.settings import Config
from models.activity_log import ActivityLog
from models.user import User
from routes.auth import auth_bp
from routes.trips import trips_bp
from routes.travel import travel_bp
from routes.admin import admin_bp
from routes.admin_auth import admin_auth_bp
from routes.auth import email_unverified_response
from routes.expenses import expenses_bp
from routes.rates import rates_bp
from routes.turnstile import turnstile_bp
from routes.weather import weather_bp
from services import db_context, turnstile
from services.cli import register_cli
from services.client_errors import (
    GENERIC_SERVER_ERROR,
    UNEXPECTED_ERROR_MESSAGE,
)
from services.client_ip import client_ip, rate_limit_ip_key
from services.rate_limiter import (
    UNLIMITED_ENDPOINTS,
    RateLimitExceeded,
    RateLimitUnavailable,
    RedisRateLimitStorage,
    limiter,
)
logger = logging.getLogger(__name__)



# Diagnostic: confirm whether the Travelpayouts token reached the process.
# Only presence is logged -- never the value or its length.
logger.info(
    "TRAVELPAYOUTS_API_KEY present=%s",
    bool(os.getenv("TRAVELPAYOUTS_API_KEY")),
)

# Minimum length for HMAC/shared secrets. In production (RENDER=true) a secret
# below this is fatal (see _validate_production_secrets); elsewhere it is only
# reported, so a dev/test environment is never bricked. Rotate weak secrets to
# long random values (e.g. `secrets.token_urlsafe(48)`).
MIN_SECRET_LENGTH = 32


class ConfigurationError(RuntimeError):
    """Raised when required production security configuration is invalid.

    Carries only the names of offending variables, never their values.
    """


def _is_production():
    """True in the Render production environment (F6's agreed condition)."""
    return os.getenv("RENDER", "").lower() == "true"


def _is_strong_secret(value):
    """A secret is strong enough when it is present and, ignoring surrounding
    whitespace, at least MIN_SECRET_LENGTH characters.

    Rejects missing (None), empty, whitespace-only, and too-short values. The
    value itself is never logged or returned.
    """
    return value is not None and len(value.strip()) >= MIN_SECRET_LENGTH


def _warn_weak_secrets():
    """Non-fatal startup warnings for weak secrets (dev/staging/test)."""
    if not _is_strong_secret(Config.JWT_SECRET_KEY):
        logger.warning(
            "JWT_SECRET_KEY is missing or shorter than %d characters; rotate it.",
            MIN_SECRET_LENGTH,
        )
    admin = Config.ADMIN_API_TOKEN or ""
    if admin and len(admin.strip()) < MIN_SECRET_LENGTH:
        logger.warning(
            "ADMIN_API_TOKEN is shorter than %d characters; rotate it.",
            MIN_SECRET_LENGTH,
        )


def _validate_production_secrets():
    """Refuse to start in production (RENDER=true) with weak/missing secrets.

    Outside production the historical behaviour is preserved: weak secrets are
    logged as warnings, never fatal, so development, staging and the test suite
    are not bricked. Secret VALUES are never logged or placed in the exception;
    only the name of the offending variable and the required length appear.

    - JWT_SECRET_KEY is always required (it signs every session token).
    - ADMIN_API_TOKEN is the shared legacy-admin credential and is only a live
      authentication path while ADMIN_LEGACY_TOKEN_ENABLED is true; it is then
      required to be present and strong. When the legacy path is disabled the
      token is dead configuration and is not validated.
    """
    if not _is_production():
        _warn_weak_secrets()
        return

    problems = []

    if not _is_strong_secret(Config.JWT_SECRET_KEY):
        problems.append(
            "JWT_SECRET_KEY must be set to at least {} characters".format(
                MIN_SECRET_LENGTH
            )
        )

    if Config.ADMIN_LEGACY_TOKEN_ENABLED and not _is_strong_secret(
        Config.ADMIN_API_TOKEN
    ):
        problems.append(
            "ADMIN_API_TOKEN must be set to at least {} characters while "
            "ADMIN_LEGACY_TOKEN_ENABLED is true (or disable the legacy admin "
            "token by setting ADMIN_LEGACY_TOKEN_ENABLED=false)".format(
                MIN_SECRET_LENGTH
            )
        )

    if problems:
        raise ConfigurationError(
            "Refusing to start in production (RENDER=true) due to insecure "
            "security configuration: " + "; ".join(problems) + "."
        )


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
                # Only an access token identifies a user for rate limiting
                # and Row-Level Security; any other token type is ignored.
                if payload.get("type") != "access":
                    return None
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

    ``request.remote_addr`` is the real client address: ProxyFix rewrites it
    from X-Forwarded-For only for the configured number of trusted proxy
    hops, so a client-supplied header cannot choose its own bucket.
    """
    identity = _jwt_sub()
    if identity is not None:
        return "user:{}".format(identity)
    return "ip:{}".format(rate_limit_ip_key())


# Endpoints that must read/write ``users`` before a user JWT exists (lookup
# by email or by token). Only these get ``app.auth_flow`` for RLS.
AUTH_FLOW_ENDPOINTS = frozenset({
    "auth.register",
    "auth.login",
    "auth.social_login",
    "auth.google_login",
    "auth.refresh",
    "auth.logout",
    "auth.forgot_password",
    "auth.verify_reset_code",
    "auth.reset_password",
    # e-mail uniqueness check looks at other rows
    "auth.update_current_user",
    "admin_auth.admin_login",
    "admin_auth.admin_mfa_setup",
    "admin_auth.admin_mfa_activate",
    "admin_auth.admin_mfa_verify",
    "admin_auth.admin_me",
    "admin_auth.admin_logout",
    "admin_auth.admin_regenerate_recovery_codes",
    # admin data endpoints resolve the admin session before enabling reads
    "admin.login_status",
    "admin.stats",
    "admin.users_list",
    "admin.trips_list",
    "admin.logs",
})

# Blueprints whose features require a verified email address.
VERIFIED_EMAIL_BLUEPRINTS = frozenset({"trips", "expenses", "travel", "weather"})

# Endpoints that call the AI provider (Groq); also counted against the platform-wide budget.
AI_ENDPOINTS = frozenset({
    "trips.generate_trip",
    "trips.regenerate_trip_itinerary",
    "trips.swap_activity",
    "trips.update_trip",
})


def _configure_rate_limit_storage():
    """Use Redis when REDIS_URL is set; otherwise per-process memory."""
    if not Config.REDIS_URL:
        if os.getenv("RENDER", "").lower() == "true":
            logger.error(
                "REDIS_URL is not set: rate limits are per-process and reset "
                "on every deploy. Configure Render Key Value."
            )
        return
    try:
        import redis
        from redis.backoff import NoBackoff
        from redis.retry import Retry

        # Short timeouts and no client-side retries: a slow/dead Redis must
        # not stall requests; the limiter's own fallback handles outages.
        client = redis.Redis.from_url(
            Config.REDIS_URL,
            socket_connect_timeout=0.5,
            socket_timeout=0.5,
            health_check_interval=30,
            retry=Retry(NoBackoff(), 0),
        )
    except Exception:
        logger.exception("Invalid REDIS_URL; using in-memory rate limits.")
        return
    limiter.use_storage(
        RedisRateLimitStorage(client),
        failure_mode=Config.RATE_LIMIT_FAILURE_MODE,
        sensitive_buckets=Config.SENSITIVE_RATE_LIMIT_BUCKETS,
        retry_seconds=Config._rate_int(Config.REDIS_RETRY_SECONDS, 30),
    )
    logger.info(
        "Rate limits use Redis (failure mode: %s).",
        limiter.failure_mode,
    )


# ============================================================
# ERROR HANDLERS (F9)
# ============================================================
#
# Last line of defence for anything a route does not handle itself. Every
# response is JSON with a fixed message chosen by status code: neither the
# exception text nor an HTTPException ``description`` (which a caller of
# ``abort()`` may have filled with internal detail) ever reaches the client.
# Flask-JWT-Extended registers handlers for its own exception classes; Flask
# picks the most specific handler, so those keep their 401/422 responses.
# ------------------------------------------------------------

_HTTP_ERROR_MESSAGES = {
    400: "Bad request.",
    401: "Authentication is required.",
    403: "You do not have permission to perform this action.",
    404: "The requested resource was not found.",
    405: "Method not allowed.",
    408: "The request timed out.",
    409: "The request conflicts with the current state.",
    413: "The request is too large.",
    415: "Unsupported media type.",
    422: "The request could not be processed.",
    429: "Too many requests. Please try again later.",
}


def _register_error_handlers(app):

    @app.errorhandler(HTTPException)
    def handle_http_exception(error):
        status = error.code or 500
        if status >= 500:
            logger.error(
                "HTTP %s on %s %s", status, request.method, request.path
            )
            message = UNEXPECTED_ERROR_MESSAGE
        else:
            message = _HTTP_ERROR_MESSAGES.get(status, "Request failed.")
        response = jsonify({
            "success": False,
            "message": message,
            "error": error.name,
        })
        response.status_code = status
        # Keep protocol headers such as Allow (405) and Retry-After.
        for name, value in error.get_headers():
            if name in ("Allow", "Retry-After", "WWW-Authenticate"):
                response.headers[name] = value
        return response

    @app.errorhandler(Exception)
    def handle_unexpected_exception(error):
        # The full traceback goes to the server log; the client gets a
        # fixed message. Roll back so a failed transaction never leaks into
        # the next request on this connection.
        logger.exception(
            "Unhandled %s on %s %s",
            type(error).__name__,
            request.method,
            request.path,
        )
        try:
            db.session.rollback()
        except Exception:  # noqa: BLE001 - never mask the original failure
            logger.exception("Rollback after unhandled error failed")
        return jsonify({
            "success": False,
            "message": UNEXPECTED_ERROR_MESSAGE,
            "error": GENERIC_SERVER_ERROR,
        }), 500


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
    MAX_CONTENT_LENGTH = 1024 * 1024
    app.config["MAX_CONTENT_LENGTH"] = MAX_CONTENT_LENGTH

    # Fail fast on weak/missing production secrets, before any blueprint, DB or
    # network wiring. In non-production this only logs warnings.
    _validate_production_secrets()
    turnstile.log_startup_status()

    # Trust X-Forwarded-For / -Proto only from the configured number of
    # reverse-proxy hops (see Config.TRUSTED_PROXY_HOPS). With 0 hops the
    # headers are ignored entirely.
    if Config.TRUSTED_PROXY_HOPS > 0:
        app.wsgi_app = ProxyFix(
            app.wsgi_app,
            x_for=Config.TRUSTED_PROXY_HOPS,
            x_proto=Config.TRUSTED_PROXY_HOPS,
        )

    @app.after_request
    def set_security_headers(response):
        response.headers['X-Content-Type-Options'] = 'nosniff'
        response.headers['X-Frame-Options'] = 'DENY'
        response.headers['Referrer-Policy'] = 'strict-origin-when-cross-origin'
        response.headers['X-XSS-Protection'] = '0'
        response.headers['Permissions-Policy'] = 'geolocation=(), camera=(), microphone=()'
        # HSTS only when served over TLS (request.is_secure honours
        # X-Forwarded-Proto through ProxyFix for trusted hops only).
        if request.is_secure:
            response.headers['Strict-Transport-Security'] = 'max-age=31536000; includeSubDomains'
        # Responses that carry tokens or personal data must never be stored
        # by browsers, proxies or CDNs.
        if request.path.startswith('/api/') and (
            request.path.startswith('/api/auth/')
            or request.headers.get('Authorization')
        ):
            response.headers['Cache-Control'] = 'no-store'
            response.headers['Pragma'] = 'no-cache'
        # A route may set a stricter, page-specific policy (the Turnstile
        # challenge page uses a per-request nonce); keep it in that case.
        if 'Content-Security-Policy' not in response.headers:
            response.headers['Content-Security-Policy'] = "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; font-src 'self' data:; connect-src 'self' https:; frame-ancestors 'none'; base-uri 'self'; form-action 'self'"
        return response



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
    #
    # F9: SQLAlchemy renders bind parameters into exception text
    # ("[parameters: ...]"). Route handlers log DB failures with
    # logger.exception, so without this the server log would receive
    # emails, password/reset-code hashes and token versions.
    # --------------------------------------------------------

    engine_options = dict(app.config.get("SQLALCHEMY_ENGINE_OPTIONS") or {})
    engine_options.setdefault("hide_parameters", True)
    app.config["SQLALCHEMY_ENGINE_OPTIONS"] = engine_options

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

    @jwt.revoked_token_loader
    def handle_revoked_token(jwt_header, jwt_payload):
        return jsonify({
            "success": False,
            "message": "Your session is no longer valid. Please log in again.",
        }), 401

    # ========================================================
    # ACCESS TOKEN REVOCATION
    # ========================================================
    #
    # Access tokens are short-lived (15 minutes by default), but a token
    # that is still inside that window must stop working the moment the
    # account's credentials change or the account is deleted.
    #
    # Every issued access token carries the account's ``token_version`` in
    # the ``ver`` claim. Bumping ``users.token_version`` therefore
    # invalidates every token minted before the bump, without needing a
    # per-token blocklist table.
    #
    # The check also rejects tokens whose ``sub`` claim is not a positive
    # integer or points at a row that no longer exists. Those tokens used
    # to reach the route handlers, where the identity conversion raised an
    # unhandled ValueError and surfaced as HTTP 500.
    # --------------------------------------------------------

    @jwt.token_in_blocklist_loader
    def is_access_token_revoked(jwt_header, jwt_payload):

        identity = jwt_payload.get("sub")

        try:
            user_id = int(identity)
        except (TypeError, ValueError):
            return True

        if user_id <= 0:
            return True

        try:
            user = db.session.get(User, user_id)
        except Exception:
            logger.exception(
                "Failed to read the user for access-token revocation"
            )
            # Fail closed: a token that cannot be verified is not honoured.
            return True

        if user is None:
            # The account was deleted; the token must not work any more.
            return True

        version = jwt_payload.get("ver")

        if version is None:
            # Token minted before the token-version rollout. It is honoured
            # until it expires (at most the access-token lifetime).
            return False

        try:
            return int(version) != int(user.token_version)
        except (TypeError, ValueError):
            return True

    # ========================================================
    # DATABASE MIGRATIONS
    # ========================================================

    migrate.init_app(app, db)

    # ========================================================
    # REGISTER ROUTES
    # ========================================================

    app.register_blueprint(auth_bp)
    app.register_blueprint(trips_bp)
    app.register_blueprint(travel_bp)
    app.register_blueprint(admin_bp)
    app.register_blueprint(admin_auth_bp)
    app.register_blueprint(expenses_bp)
    app.register_blueprint(rates_bp)
    app.register_blueprint(weather_bp)
    app.register_blueprint(turnstile_bp)

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

    _configure_rate_limit_storage()

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
        if endpoint is None or endpoint in UNLIMITED_ENDPOINTS:
            return None
        bucket = limiter.bucket_for(endpoint)
        if bucket is None:
            # Fail closed: an endpoint without its own bucket still gets the
            # default read/write budget instead of being unlimited.
            bucket = (
                "DEFAULT_READ"
                if request.method in ("GET", "HEAD")
                else "DEFAULT_WRITE"
            )

        key = _rate_limit_key()
        try:
            if endpoint in AI_ENDPOINTS and request.method != "GET":
                limiter.check("AI_GLOBAL", "global")
            result = limiter.check(bucket, key)
        except RateLimitUnavailable:
            resp = jsonify({
                "success": False,
                "message": "Service temporarily unavailable. Please try again.",
            })
            resp.status_code = 503
            resp.headers["Retry-After"] = "30"
            return resp
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

    @app.teardown_request
    def clear_rls_context(_exc=None):
        # The RLS settings themselves are transaction-local (gone at commit /
        # rollback). This also clears the per-thread context so a worker
        # thread never carries one request's identity into the next.
        db_context.reset()

    @app.before_request
    def set_rls_context():
        # Row-Level Security context for this request, re-applied by
        # services/db_context at the start of every DB transaction. Values
        # come from the verified JWT and the endpoint name only.
        db_context.reset()
        if request.method == "OPTIONS":
            return None
        identity = _jwt_sub()
        if identity is not None:
            try:
                db_context.set_subject(int(identity))
            except (TypeError, ValueError):
                pass
        if request.endpoint in AUTH_FLOW_ENDPOINTS:
            db_context.enable_auth_flow()
        # (db_context re-applies every change to an already-open transaction.)
        return None

    @app.before_request
    def require_verified_email():
        # Trips, AI, expenses, travel search and weather need a verified
        # address. The status is read from the database on every request;
        # nothing the client sends can claim it.
        if request.method == "OPTIONS":
            return None
        if request.blueprint not in VERIFIED_EMAIL_BLUEPRINTS:
            return None
        try:
            verify_jwt_in_request(optional=True)
            identity = get_jwt_identity()
        except Exception:
            # Let the route's own @jwt_required() produce the 401.
            return None
        if identity is None:
            return None
        try:
            user = db.session.get(User, int(identity))
        except (TypeError, ValueError):
            return None
        if user is not None and not user.email_verified:
            return email_unverified_response()
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
                ip_address=client_ip(),
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
    # CSP VIOLATION REPORTS (public, from browsers)
    # POST /api/csp-report
    # ========================================================
    #
    # Collects Content-Security-Policy(-Report-Only) violation reports from
    # the web app so the policy can be tightened from real data. Only a few
    # non-sensitive fields are logged (directive, blocked origin, page path);
    # bodies are size-capped and rate-limited.

    @app.route("/api/csp-report", methods=["POST"], endpoint="csp_report")
    def csp_report():
        if (request.content_length or 0) > 16 * 1024:
            return "", 413
        payload = request.get_json(force=True, silent=True)
        reports = []
        if isinstance(payload, dict) and isinstance(
            payload.get("csp-report"), dict
        ):
            reports = [payload["csp-report"]]
        elif isinstance(payload, list):
            reports = [
                item.get("body") for item in payload[:20]
                if isinstance(item, dict) and isinstance(item.get("body"), dict)
            ]
        for report in reports[:20]:
            directive = str(
                report.get("effective-directive")
                or report.get("effectiveDirective")
                or report.get("violated-directive")
                or ""
            )[:80]
            blocked = str(
                report.get("blocked-uri") or report.get("blockedURL") or ""
            )
            blocked = blocked.split("?")[0][:200]
            page = str(
                report.get("document-uri") or report.get("documentURL") or ""
            )
            page = page.split("?")[0].split("#")[0][:200]
            logger.warning(
                "CSP violation: directive=%s blocked=%s page=%s",
                directive, blocked, page,
            )
        return "", 204

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

    _register_error_handlers(app)

    register_cli(app)

    return app


# ============================================================
# APPLICATION INSTANCE
# ============================================================

app = create_app()


# ============================================================
# RUN SERVER
# ============================================================

if __name__ == "__main__":

    # Local development only. Production runs `gunicorn wsgi:app`. The
    # Werkzeug debugger allows code execution, so it is opt-in and the dev
    # server binds to loopback unless told otherwise.
    app.run(
        host=os.getenv("FLASK_RUN_HOST", "127.0.0.1"),
        port=int(os.getenv("PORT", "5000")),
        debug=os.getenv("FLASK_DEBUG", "0") == "1",
    )
