"""
Admin / analytics API.

Everything under ``/api/admin`` is gated by a single shared secret
(``ADMIN_API_TOKEN``) presented as ``Authorization: Bearer <token>``. The
endpoints expose read-only analytics over users, trips, subscriptions and the
activity log so the product owner can see how the site is being used.

Row-Level Security
------------------
``trips`` and ``subscriptions`` have RLS FORCED on. This backend connects as
the owning role (e.g. ``neondb_owner``), and the owner is subject to forced
RLS, so a plain SELECT would only ever surface the requesting user's own rows.
The admin view is meant to be cross-user, so each admin request runs inside a
transaction where we ``SET LOCAL row_security = off``. The flag is scoped to
the current transaction (per request) and never leaks elsewhere. ``users`` is
RLS-enabled but not forced, so the owning role can already read all rows there.
"""

import logging
from datetime import datetime, timedelta

from flask import Blueprint, jsonify, request
from sqlalchemy import func, text

from config.database import db
from config.settings import Config
from models.activity_log import ActivityLog
from models.subscription import Subscription
from models.trip import Trip
from models.user import User

logger = logging.getLogger(__name__)


admin_bp = Blueprint(
    "admin",
    __name__,
    url_prefix="/api/admin",
)


def _authorize():
    """Return True if the request carries the configured admin token."""
    token = Config.ADMIN_API_TOKEN
    if not token:
        return False
    auth = request.headers.get("Authorization", "")
    if not auth.startswith("Bearer "):
        return False
    provided = auth[len("Bearer "):].strip()
    if not provided:
        return False
    # Constant-time comparison to avoid trivial timing oracle.
    return len(provided) == len(token) and all(
        ord(a) == ord(b) for a, b in zip(provided, token)
    )


def _require_admin():
    """Return a (json_response_or_None) helper.

    When the request is not authorized, this returns a Flask response to send
    back; otherwise it returns None so the route can proceed.
    """
    if _authorize():
        return None
    return jsonify({
        "success": False,
        "message": "Admin authentication required.",
    }), 401


def _bypass_rls():
    """Disable RLS for the current transaction (scoped to this request).

    Postgres-only: ``SET LOCAL row_security`` has no meaning on other
    backends (e.g. the SQLite test DB), which have no RLS to begin with.
    """
    if db.engine.dialect.name != "postgresql":
        return
    with db.session.connection() as conn:
        conn.execute(text("SET LOCAL row_security = off"))


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
            return response
    return None


@admin_bp.after_request
def _set_admin_headers(response):
    """Prevent the admin API from being cached by any intermediary."""
    if _authorize():
        response.headers["Cache-Control"] = "no-store"
    return response


# ============================================================
# LOGIN STATUS
# GET /api/admin/login-status
# ============================================================

@admin_bp.route("/login-status", methods=["GET"])
def login_status():
    """Return whether the supplied admin token is valid."""
    return jsonify({
        "success": True,
        "authenticated": _authorize(),
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
        subs_total = db.session.query(
            func.count(Subscription.id)
        ).scalar() or 0
        subs_active = db.session.query(
            func.count(Subscription.id)
        ).filter(Subscription.status == "active").scalar() or 0

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
                "subscriptions": {
                    "total": subs_total,
                    "active": subs_active,
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

    user_id = data.get("userId")
    try:
        row = ActivityLog(
            event_type="page_view",
            path=str(path_value).strip()[:255],
            user_id=int(user_id) if user_id else None,
            detail={"screen": str(path_value).strip()[:255]},
            ip_address=_client_ip(),
        )
        db.session.add(row)
        db.session.commit()
        return jsonify({
            "success": True,
            "logId": row.id,
        }), 201
    except Exception as error:
        db.session.rollback()
        logger.exception("Page-view tracking failed")
        return jsonify({
            "success": False,
            "message": "Failed to record page view.",
            "error": "Internal server error.",
        }), 500


def _client_ip():
    forwarded = request.headers.get("X-Forwarded-For")
    if forwarded:
        return str(forwarded).split(",")[0].strip()[:64]
    return (request.remote_addr or "")[:64] or None


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
