"""
Admin / analytics API.

Authorization (checked server-side on EVERY ``/api/admin/*`` data endpoint):

1. An *active admin session* (``Authorization: Bearer <session token>``)
   obtained through ``/api/admin/auth`` with password + TOTP by a user whose
   ``role`` is ``admin``. See ``routes/admin_auth.py``.
2. Legacy, transitional: the shared ``ADMIN_API_TOKEN``, only while
   ``ADMIN_LEGACY_TOKEN_ENABLED`` is true. Every legacy use is audited and
   logged as a warning. Disable it once an MFA admin exists.

Every authorized request is written to ``admin_audit_log``.

Row-Level Security
------------------
Admin views are cross-user. After authorization the request enables the
``app.admin_read`` setting (``services/db_context``), which the
``trips_admin_select`` / ``users_auth_flow_select`` policies honour. This works
for both the owner role and the least-privilege runtime role (which cannot use
``SET row_security = off``).
"""

import hmac
import logging
from datetime import datetime, timedelta

from flask import Blueprint, jsonify, request
from flask_jwt_extended import get_jwt_identity, verify_jwt_in_request
from sqlalchemy import func, text

from config.database import db
from config.settings import Config
from models.activity_log import ActivityLog
from models.admin_security import ADMIN_SESSION_ACTIVE
from models.trip import Trip
from models.user import User
from services import admin_auth, db_context
from services.client_ip import client_ip

logger = logging.getLogger(__name__)


admin_bp = Blueprint(
    "admin",
    __name__,
    url_prefix="/api/admin",
)


_PRINCIPAL_KEY = "tripora.admin_principal"


def _provided_bearer():
    auth = request.headers.get("Authorization", "")
    if not auth.startswith("Bearer "):
        return None
    return auth[len("Bearer "):].strip() or None


def _legacy_token_matches(provided):
    token = Config.ADMIN_API_TOKEN
    if not token or not Config.ADMIN_LEGACY_TOKEN_ENABLED or not provided:
        return False
    # Constant-time comparison (no early exit on length or first mismatch).
    return hmac.compare_digest(
        provided.encode("utf-8"),
        token.encode("utf-8"),
    )


def _authorize():
    """Resolve the admin principal for this request.

    Returns ``("session", user_id)``, ``("legacy", None)`` or None.
    The result is cached in the WSGI environ (strictly per request).
    """
    if _PRINCIPAL_KEY in request.environ:
        return request.environ[_PRINCIPAL_KEY]

    principal = None
    provided = _provided_bearer()

    if provided:
        session, user = admin_auth.find_session(provided, ADMIN_SESSION_ACTIVE)
        if session is not None:
            admin_auth.touch(session)
            db.session.commit()
            principal = ("session", user.id)
        elif _legacy_token_matches(provided):
            principal = ("legacy", None)

    request.environ[_PRINCIPAL_KEY] = principal
    return principal


def _require_admin():
    """Return None when authorized, else a 401 response."""
    if _authorize():
        return None
    return jsonify({
        "success": False,
        "message": "Admin authentication required.",
    }), 401


def _bypass_rls():
    """Allow cross-user reads for this (already authorized) request."""
    if not _authorize():
        raise PermissionError("admin read without authorization")
    # enable_admin_read() also applies to the transaction already open from
    # the admin-session lookup.
    db_context.enable_admin_read()


@admin_bp.before_request
def _guard():
    """Reject unauthenticated calls to every /api/admin route.

    The page-view beacon lives on its own public route and is wired before the
    blueprint's guard via a separate Flask route (see _track_page_view).
    """
    if request.endpoint not in (
        "admin.track_page_view",
        "admin.login_status",
    ):
        response = _require_admin()
        if response is not None:
            admin_auth.audit(
                "access_denied", None, request, 401, ip_address=client_ip(),
            )
            return response
    return None


@admin_bp.after_request
def _set_admin_headers(response):
    """No caching anywhere; audit every authorized admin request."""
    if request.endpoint == "admin.track_page_view":
        return response

    response.headers["Cache-Control"] = "no-store"

    principal = request.environ.get(_PRINCIPAL_KEY)
    if principal and request.endpoint != "admin.login_status":
        kind, user_id = principal
        if kind == "legacy":
            logger.warning(
                "Admin API used with the legacy shared token; migrate to "
                "MFA admin accounts and set ADMIN_LEGACY_TOKEN_ENABLED=false."
            )
        admin_auth.audit(
            "legacy_token_access" if kind == "legacy" else "access",
            user_id,
            request,
            response.status_code,
            detail={"query": dict(request.args)} if request.args else None,
            ip_address=client_ip(),
        )
    return response


# ============================================================
# LOGIN STATUS
# GET /api/admin/login-status
# ============================================================

@admin_bp.route("/login-status", methods=["GET"])
def login_status():
    """Return whether the supplied admin token is valid."""
    principal = _authorize()
    return jsonify({
        "success": True,
        "authenticated": bool(principal),
        "method": principal[0] if principal else None,
    }), 200


# ============================================================
# ANALYTICS SUMMARY
# GET /api/admin/stats
# ============================================================

@admin_bp.route("/stats", methods=["GET"])
def stats():
    try:
        _bypass_rls()

        users_total = db.session.query(func.count(User.id)).scalar() or 0
        users_verified = db.session.query(
            func.count(User.id)
        ).filter(User.email_verified.is_(True)).scalar() or 0

        trips_total = db.session.query(func.count(Trip.id)).scalar() or 0

        page_views = db.session.query(
            func.count(ActivityLog.id)
        ).filter(ActivityLog.event_type == "page_view").scalar() or 0
        api_requests = db.session.query(
            func.count(ActivityLog.id)
        ).filter(ActivityLog.event_type == "api_request").scalar() or 0

        # Top destinations across all users.
        top_destinations = [
            {"destination": row[0], "count": row[1]}
            for row in db.session.query(
                Trip.destination, func.count(Trip.id)
            ).group_by(Trip.destination).order_by(
                func.count(Trip.id).desc()
            ).limit(10).all()
        ]

        # Recent signups (last 7 days).
        since = datetime.utcnow() - timedelta(days=7)
        recent_signups = db.session.query(
            func.count(User.id)
        ).filter(User.created_at >= since).scalar() or 0

        return jsonify({
            "success": True,
            "stats": {
                "users": {
                    "total": users_total,
                    "verified": users_verified,
                    "recent7d": recent_signups,
                },
                "trips": {
                    "total": trips_total,
                },
                "activity": {
                    "pageViews": page_views,
                    "apiRequests": api_requests,
                },
                "topDestinations": top_destinations,
            },
        }), 200
    except Exception as error:
        logger.exception("Admin stats failed")
        return jsonify({
            "success": False,
            "message": "Failed to load analytics.",
            "error": "Internal server error.",
        }), 500


# ============================================================
# USERS LIST
# GET /api/admin/users?limit=&offset=
# ============================================================

@admin_bp.route("/users", methods=["GET"])
def users_list():
    try:
        _bypass_rls()

        limit = _as_int(request.args.get("limit"), 100, 1, 500)
        offset = _as_int(request.args.get("offset"), 0, 0, 100000)

        rows = User.query.order_by(User.created_at.desc()).limit(limit).offset(offset).all()

        return jsonify({
            "success": True,
            "count": len(rows),
            "users": [
                {
                    "id": u.id,
                    "name": u.name,
                    "email": u.email,
                    "emailVerified": u.email_verified,
                    "authProvider": u.auth_provider,
                    "preferredLanguage": u.preferred_language,
                    "preferredCurrency": u.preferred_currency,
                    "regionCountry": u.region_country,
                    "createdAt": (
                        u.created_at.isoformat()
                        if u.created_at
                        else None
                    ),
                }
                for u in rows
            ],
        }), 200
    except Exception as error:
        logger.exception("Admin users list failed")
        return jsonify({
            "success": False,
            "message": "Failed to load users.",
            "error": "Internal server error.",
        }), 500


# ============================================================
# TRIPS LIST
# GET /api/admin/trips?limit=&offset=
# ============================================================

@admin_bp.route("/trips", methods=["GET"])
def trips_list():
    try:
        _bypass_rls()

        limit = _as_int(request.args.get("limit"), 100, 1, 500)
        offset = _as_int(request.args.get("offset"), 0, 0, 100000)

        rows = Trip.query.order_by(Trip.created_at.desc()).limit(limit).offset(offset).all()

        return jsonify({
            "success": True,
            "count": len(rows),
            "trips": [
                {
                    "id": t.id,
                    "userId": t.user_id,
                    "destination": t.destination,
                    "startDate": (
                        t.start_date.isoformat() if t.start_date else None
                    ),
                    "endDate": (
                        t.end_date.isoformat() if t.end_date else None
                    ),
                    "travelers": t.travelers,
                    "budget": t.budget,
                    "travelStyle": t.travel_style,
                    "createdAt": (
                        t.created_at.isoformat()
                        if t.created_at
                        else None
                    ),
                }
                for t in rows
            ],
        }), 200
    except Exception as error:
        logger.exception("Admin trips list failed")
        return jsonify({
            "success": False,
            "message": "Failed to load trips.",
            "error": "Internal server error.",
        }), 500


# ============================================================
# ACTIVITY LOG
# GET /api/admin/logs?type=&limit=&offset=
# ============================================================

@admin_bp.route("/logs", methods=["GET"])
def logs():
    try:
        _bypass_rls()

        limit = _as_int(request.args.get("limit"), 200, 1, 1000)
        offset = _as_int(request.args.get("offset"), 0, 0, 100000)

        query = ActivityLog.query
        event_type = request.args.get("type")
        if event_type:
            query = query.filter(ActivityLog.event_type == event_type)

        rows = query.order_by(ActivityLog.created_at.desc()).limit(limit).offset(offset).all()

        return jsonify({
            "success": True,
            "count": len(rows),
            "logs": [row.to_dict() for row in rows],
        }), 200
    except Exception as error:
        logger.exception("Admin logs failed")
        return jsonify({
            "success": False,
            "message": "Failed to load activity log.",
            "error": "Internal server error.",
        }), 500


# ============================================================
# PAGE-VIEW BEACON (PUBLIC)
# POST /api/admin/page-view
# ============================================================
#
# Intentionally NOT behind the admin token: it records screen visits from the
# public app (including anonymous visitors). Lightweight on purpose.

@admin_bp.route("/page-view", methods=["POST"])
def track_page_view():
    data = request.get_json(silent=True) or {}
    path_value = data.get("path")
    if not path_value or not str(path_value).strip():
        return jsonify({
            "success": False,
            "message": "path is required.",
        }), 400

    # Attribution comes only from a verified access token. A ``userId`` in
    # the body is ignored: this endpoint is public, so trusting it would let
    # anyone write events in another user's name.
    user_id = _optional_jwt_user_id()
    try:
        row = ActivityLog(
            event_type="page_view",
            path=str(path_value).strip()[:255],
            user_id=user_id,
            detail={"screen": str(path_value).strip()[:255]},
            ip_address=_client_ip(),
        )
        db.session.add(row)
        # Read the id before committing: after commit the row would be
        # reloaded with a SELECT, which Row-Level Security reserves for
        # admins (activity logs hold IP addresses).
        db.session.flush()
        log_id = row.id
        db.session.commit()
        return jsonify({
            "success": True,
            "logId": log_id,
        }), 201
    except Exception as error:
        db.session.rollback()
        logger.exception("Page-view tracking failed")
        return jsonify({
            "success": False,
            "message": "Failed to record page view.",
            "error": "Internal server error.",
        }), 500


def _optional_jwt_user_id():
    """Return the user id from a valid access token, or None.

    Missing, expired, revoked or malformed tokens are treated as anonymous;
    the beacon never fails because of them.
    """
    try:
        verify_jwt_in_request(optional=True)
        identity = get_jwt_identity()
    except Exception:
        return None
    try:
        user_id = int(identity)
    except (TypeError, ValueError):
        return None
    return user_id if user_id > 0 else None


def _client_ip():
    # Validated address from the trusted proxy chain (services/client_ip).
    # Reading X-Forwarded-For directly would store whatever the caller sent.
    return client_ip()


def _as_int(value, default, min_value, max_value):
    try:
        parsed = int(value)
    except (TypeError, ValueError):
        return default
    if parsed < min_value:
        return min_value
    if parsed > max_value:
        return max_value
    return parsed
