"""Administrator login with mandatory TOTP. See services/admin_auth.py."""

import logging
from datetime import datetime

from flask import Blueprint, jsonify, request
from werkzeug.security import check_password_hash

from config.database import db
from models.admin_security import (
    ADMIN_SESSION_ACTIVE,
    ADMIN_SESSION_PENDING_MFA,
    AdminMfa,
)
from models.user import ROLE_ADMIN, User
from services import admin_auth
from services.client_ip import client_ip

logger = logging.getLogger(__name__)

admin_auth_bp = Blueprint(
    "admin_auth",
    __name__,
    url_prefix="/api/admin/auth",
)

GENERIC_LOGIN_FAILURE = "Invalid credentials."
GENERIC_MFA_FAILURE = "Invalid or expired verification code."

# Same cost as a real password check when the account does not qualify.
from routes.auth import _DUMMY_PASSWORD_HASH  # noqa: E402

# Shared per-account login throttle (F3 / M1).
from routes.auth import (  # noqa: E402
    clear_account_login_throttle,
    enforce_account_login_throttle,
)


def _bearer():
    header = request.headers.get("Authorization", "")
    if header.startswith("Bearer "):
        return header[len("Bearer "):].strip()
    return None


def _json():
    data = request.get_json(silent=True)
    return data if isinstance(data, dict) else {}


def _ua():
    return (request.headers.get("User-Agent") or "")[:255]


def _unavailable():
    return jsonify({
        "success": False,
        "message": "Administrator sign-in is not configured.",
    }), 503


def _pending_session():
    token = _json().get("pendingToken")
    return admin_auth.find_session(token, ADMIN_SESSION_PENDING_MFA)


def _fail_pending(session, user_id, action):
    """Count a failed second-factor attempt; burn the session at the limit."""
    session.mfa_attempts = int(session.mfa_attempts or 0) + 1
    if session.mfa_attempts >= admin_auth.MAX_MFA_ATTEMPTS:
        session.revoked_at = datetime.utcnow()
    db.session.commit()
    admin_auth.audit(action, user_id, request, 401, ip_address=client_ip())
    return jsonify({"success": False, "message": GENERIC_MFA_FAILURE}), 401


def _activate(session, user, action, extra=None):
    """Replace the pending session with an active one (token rotation)."""
    session.revoked_at = datetime.utcnow()
    raw, expires = admin_auth.create_session(
        user, ADMIN_SESSION_ACTIVE, client_ip(), _ua(),
    )
    db.session.commit()
    admin_auth.audit(action, user.id, request, 200, ip_address=client_ip())
    body = {
        "success": True,
        "sessionToken": raw,
        "expiresAt": expires.isoformat() + "Z",
        "idleTimeoutMinutes": admin_auth.session_idle_minutes(),
        "admin": {"email": user.email, "name": user.name},
    }
    body.update(extra or {})
    return jsonify(body), 200


# ============================================================
# STEP 1: PASSWORD
# ============================================================

@admin_auth_bp.route("/login", methods=["POST"])
def admin_login():
    if not admin_auth.mfa_available():
        return _unavailable()

    data = _json()
    email = str(data.get("email") or "").strip().lower()
    password = data.get("password")

    if not email or not isinstance(password, str) or not password:
        return jsonify({"success": False, "message": GENERIC_LOGIN_FAILURE}), 401

    # M1: the SAME per-account counter as /api/auth/login (shared HMAC key and
    # bucket), applied before the lookup and the password hash, for every
    # address. Without it this endpoint was a password oracle for admin
    # accounts limited only per IP.
    throttled = enforce_account_login_throttle(email)
    if throttled is not None:
        admin_auth.audit(
            "login_throttled", None, request, throttled.status_code,
            ip_address=client_ip(),
        )
        return throttled

    user = User.query.filter_by(email=email).first()
    qualifies = (
        user is not None
        and user.role == ROLE_ADMIN
        and user.email_verified
        and bool(user.password_hash)
    )
    password_ok = check_password_hash(
        user.password_hash if qualifies else _DUMMY_PASSWORD_HASH,
        password,
    )

    if not (qualifies and password_ok):
        db.session.rollback()
        admin_auth.audit(
            "login_failed",
            user.id if (user is not None and user.role == ROLE_ADMIN) else None,
            request, 401, ip_address=client_ip(),
        )
        return jsonify({"success": False, "message": GENERIC_LOGIN_FAILURE}), 401

    # Verified password: same reset-on-success rule as the user login. The
    # second factor (TOTP / recovery code) is still required below.
    clear_account_login_throttle(email)

    mfa = db.session.get(AdminMfa, user.id)
    enrolled = mfa is not None and mfa.enabled_at is not None

    if not enrolled and not admin_auth.enrollment_open(mfa):
        db.session.rollback()
        admin_auth.audit(
            "enrollment_closed", user.id, request, 403, ip_address=client_ip(),
        )
        return jsonify({
            "success": False,
            "message": (
                "Two-factor enrollment is not open for this account. "
                "Ask an operator to run `flask admin reset-mfa`."
            ),
        }), 403

    raw, expires = admin_auth.create_session(
        user, ADMIN_SESSION_PENDING_MFA, client_ip(), _ua(),
    )
    db.session.commit()
    admin_auth.audit("login_password_ok", user.id, request, 200,
                     ip_address=client_ip())

    return jsonify({
        "success": True,
        "pendingToken": raw,
        "expiresAt": expires.isoformat() + "Z",
        "mfaEnrolled": enrolled,
    }), 200


# ============================================================
# STEP 2a: FIRST-TIME ENROLLMENT
# ============================================================

@admin_auth_bp.route("/mfa/setup", methods=["POST"])
def admin_mfa_setup():
    if not admin_auth.mfa_available():
        return _unavailable()

    session, user = _pending_session()
    if session is None:
        return jsonify({"success": False, "message": GENERIC_MFA_FAILURE}), 401

    mfa = db.session.get(AdminMfa, user.id)
    if not admin_auth.enrollment_open(mfa):
        return jsonify({
            "success": False,
            "message": "Two-factor enrollment is not open for this account.",
        }), 403

    secret = admin_auth.new_totp_secret()
    mfa.secret_encrypted = admin_auth.encrypt_secret(secret)
    db.session.commit()
    admin_auth.audit("mfa_setup_started", user.id, request, 200,
                     ip_address=client_ip())

    return jsonify({
        "success": True,
        "secret": secret,
        "otpauthUri": admin_auth.otpauth_uri(secret, user.email),
        "digits": admin_auth.TOTP_DIGITS,
        "period": admin_auth.TOTP_STEP_SECONDS,
    }), 200


@admin_auth_bp.route("/mfa/activate", methods=["POST"])
def admin_mfa_activate():
    if not admin_auth.mfa_available():
        return _unavailable()

    session, user = _pending_session()
    if session is None:
        return jsonify({"success": False, "message": GENERIC_MFA_FAILURE}), 401

    mfa = db.session.get(AdminMfa, user.id)
    if not admin_auth.enrollment_open(mfa) or not mfa.secret_encrypted:
        return jsonify({"success": False, "message": GENERIC_MFA_FAILURE}), 401

    secret = admin_auth.decrypt_secret(mfa.secret_encrypted)
    step = admin_auth.match_totp(secret, _json().get("code"))
    if step is None:
        return _fail_pending(session, user.id, "mfa_activate_failed")

    mfa.enabled_at = datetime.utcnow()
    mfa.last_used_step = step
    codes = admin_auth.new_recovery_codes(user.id)

    return _activate(session, user, "mfa_enrolled", {"recoveryCodes": codes})


# ============================================================
# STEP 2b: VERIFY (ENROLLED)
# ============================================================

@admin_auth_bp.route("/mfa/verify", methods=["POST"])
def admin_mfa_verify():
    if not admin_auth.mfa_available():
        return _unavailable()

    session, user = _pending_session()
    if session is None:
        return jsonify({"success": False, "message": GENERIC_MFA_FAILURE}), 401

    mfa = db.session.get(AdminMfa, user.id)
    if mfa is None or mfa.enabled_at is None:
        return jsonify({"success": False, "message": GENERIC_MFA_FAILURE}), 401

    data = _json()
    recovery_code = data.get("recoveryCode")

    if recovery_code:
        if not admin_auth.consume_recovery_code(user.id, recovery_code):
            return _fail_pending(session, user.id, "mfa_recovery_failed")
        return _activate(session, user, "mfa_recovery_used")

    secret = admin_auth.decrypt_secret(mfa.secret_encrypted)
    step = admin_auth.match_totp(
        secret, data.get("code"), last_used_step=mfa.last_used_step,
    )
    if step is None:
        return _fail_pending(session, user.id, "mfa_failed")

    # Conditional update: two requests racing with the same code cannot both
    # succeed (the second sees last_used_step already advanced).
    advanced = AdminMfa.query.filter(
        AdminMfa.user_id == user.id,
        (AdminMfa.last_used_step.is_(None)) | (AdminMfa.last_used_step < step),
    ).update({AdminMfa.last_used_step: step}, synchronize_session=False)
    if advanced != 1:
        return _fail_pending(session, user.id, "mfa_replay_blocked")

    return _activate(session, user, "session_started")


# ============================================================
# SESSION
# ============================================================

@admin_auth_bp.route("/me", methods=["GET"])
def admin_me():
    session, user = admin_auth.find_session(_bearer(), ADMIN_SESSION_ACTIVE)
    if session is None:
        return jsonify({"success": False, "message": "Admin authentication required."}), 401
    admin_auth.touch(session)
    db.session.commit()
    return jsonify({
        "success": True,
        "admin": {"email": user.email, "name": user.name},
        "expiresAt": session.expires_at.isoformat() + "Z",
    }), 200


@admin_auth_bp.route("/logout", methods=["POST"])
def admin_logout():
    session, user = admin_auth.find_session(_bearer(), ADMIN_SESSION_ACTIVE)
    if session is not None:
        session.revoked_at = datetime.utcnow()
        db.session.commit()
        admin_auth.audit("logout", user.id, request, 200, ip_address=client_ip())
    return jsonify({"success": True}), 200


@admin_auth_bp.route("/mfa/recovery-codes", methods=["POST"])
def admin_regenerate_recovery_codes():
    """Issue a new set of recovery codes (requires a current TOTP code)."""
    session, user = admin_auth.find_session(_bearer(), ADMIN_SESSION_ACTIVE)
    if session is None:
        return jsonify({"success": False, "message": "Admin authentication required."}), 401

    mfa = db.session.get(AdminMfa, user.id)
    secret = admin_auth.decrypt_secret(mfa.secret_encrypted)
    step = admin_auth.match_totp(
        secret, _json().get("code"), last_used_step=mfa.last_used_step,
    )
    if step is None:
        admin_auth.audit("recovery_regen_failed", user.id, request, 401,
                         ip_address=client_ip())
        return jsonify({"success": False, "message": GENERIC_MFA_FAILURE}), 401

    mfa.last_used_step = step
    codes = admin_auth.new_recovery_codes(user.id)
    db.session.commit()
    admin_auth.audit("recovery_codes_regenerated", user.id, request, 200,
                     ip_address=client_ip())
    return jsonify({"success": True, "recoveryCodes": codes}), 200
