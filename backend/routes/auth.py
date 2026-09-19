import logging
import secrets
from datetime import datetime, timedelta
from werkzeug.security import check_password_hash, generate_password_hash
from flask import Blueprint, jsonify, request

from werkzeug.security import (
    check_password_hash,
    generate_password_hash,
)

from flask_jwt_extended import (
    create_access_token,
    get_jwt_identity,
    jwt_required,
)

from config.database import db

from models.user import (
    User,
)

from models.activity_log import ActivityLog
from models.trip import Trip

from services.social_auth_service import (
    SocialAuthError,
    verify_identity_token,
)

from services.email_service import (
    send_password_reset_code,
)


logger = logging.getLogger(__name__)


# ============================================================
# CONSTANTS
# ============================================================

VALID_LANGUAGES = {
    "en",
    "es",
    "fr",
    "de",
    "it",
    "pt",
}

VALID_CURRENCIES = {
    "USD",
    "EUR",
    "GBP",
    "CAD",
    "AUD",
    "AED",
    "JPY",
    "CHF",
    "INR",
    "CFA",
}

# ---- Password reset policy -----------------------------------------
# The email code lives for 15 minutes, the post-verification token for 30.
RESET_CODE_LIFETIME_MINUTES = 15
RESET_TOKEN_LIFETIME_MINUTES = 30
RESET_MAX_ATTEMPTS = 5

GENERIC_RESET_MESSAGE = (
    "A password reset code has been sent."
)
INVALID_RESET_CODE_MESSAGE = "Invalid or expired reset code."
INVALID_RESET_TOKEN_MESSAGE = "Invalid or expired reset token."


# ============================================================
# HELPERS
# ============================================================

def _redact_sensitive(data):
    """Return a copy of request data safe for logging."""

    if not isinstance(data, dict):
        return data

    safe = dict(data)

    if "password" in safe:
        safe["password"] = "[REDACTED]"

    if "currentPassword" in safe:
        safe["currentPassword"] = "[REDACTED]"

    if "idToken" in safe:
        safe["idToken"] = "[REDACTED]"

    if "token" in safe:
        safe["token"] = "[REDACTED]"

    if "resetToken" in safe:
        safe["resetToken"] = "[REDACTED]"

    if "code" in safe:
        safe["code"] = "[REDACTED]"

    return safe


def _user_response(user):
    """Return the public user representation."""

    return {
        "id": user.id,
        "name": user.name,
        "email": user.email,
        "emailVerified": user.email_verified,
        "preferredLanguage": user.preferred_language,
        "preferredCurrency": user.preferred_currency,
        "authProvider": user.auth_provider,
        "createdAt": (
            user.created_at.isoformat()
            if user.created_at
            else None
        ),
    }


# ============================================================
# BLUEPRINT
# ============================================================

auth_bp = Blueprint(
    "auth",
    __name__,
    url_prefix="/api/auth",
)


# ============================================================
# REGISTER
# POST /api/auth/register
# ============================================================

@auth_bp.route("/register", methods=["POST"])
def register():

    data = request.get_json(silent=True)

    logger.debug(
        "REGISTER REQUEST: %s",
        _redact_sensitive(data),
    )

    if not data:
        return jsonify({
            "success": False,
            "message": "No registration data provided.",
        }), 400

    name = data.get("name")
    email = data.get("email")
    password = data.get("password")

    preferred_language = data.get(
        "preferredLanguage",
        "en",
    )

    preferred_currency = data.get(
        "preferredCurrency",
        "USD",
    )

    # --------------------------------------------------------
    # REQUIRED FIELDS
    # --------------------------------------------------------

    if not name:
        return jsonify({
            "success": False,
            "message": "Name is required.",
        }), 400

    if not email:
        return jsonify({
            "success": False,
            "message": "Email is required.",
        }), 400

    if not password:
        return jsonify({
            "success": False,
            "message": "Password is required.",
        }), 400

    # --------------------------------------------------------
    # CLEAN DATA
    # --------------------------------------------------------

    name = str(name).strip()
    email = str(email).strip().lower()
    password = str(password)

    preferred_language = (
        str(preferred_language).strip().lower()
        or "en"
    )

    preferred_currency = (
        str(preferred_currency).strip().upper()
        or "USD"
    )

    if not name:
        return jsonify({
            "success": False,
            "message": "Name cannot be empty.",
        }), 400

    if not email:
        return jsonify({
            "success": False,
            "message": "Email cannot be empty.",
        }), 400

    if len(password) < 6:
        return jsonify({
            "success": False,
            "message": "Password must be at least 6 characters.",
        }), 400

    if preferred_language not in VALID_LANGUAGES:
        return jsonify({
            "success": False,
            "message": "Preferred language is invalid.",
        }), 400

    if preferred_currency not in VALID_CURRENCIES:
        return jsonify({
            "success": False,
            "message": "Preferred currency is invalid.",
        }), 400

    # --------------------------------------------------------
    # DATABASE
    # --------------------------------------------------------

    try:

        existing_user = User.query.filter_by(
            email=email
        ).first()

        if existing_user:
            return jsonify({
                "success": False,
                "message": (
                    "An account with this email already exists."
                ),
            }), 409

        # ----------------------------------------------------
        # PASSWORD HASH
        # ----------------------------------------------------

        password_hash = generate_password_hash(password)

        # ----------------------------------------------------
        # CREATE USER
        # ----------------------------------------------------

        user = User(
            name=name,
            email=email,
            password_hash=password_hash,
            preferred_language=preferred_language,
            preferred_currency=preferred_currency,
            email_verified=True,
        )

        db.session.add(user)
        db.session.commit()

        logger.info(
            "User registered successfully: %s",
            user.id,
        )

        return jsonify({
            "success": True,
            "message": "Registration successful.",
            "user": _user_response(user),
        }), 201

    except Exception:

        db.session.rollback()

        logger.exception(
            "Register request failed"
        )

        return jsonify({
            "success": False,
            "message": "Failed to register user.",
            "error": "Internal server error.",
        }), 500


# ============================================================
# LOGIN
# POST /api/auth/login
# ============================================================

@auth_bp.route("/login", methods=["POST"])
def login():

    data = request.get_json(silent=True)

    logger.debug(
        "LOGIN REQUEST: %s",
        _redact_sensitive(data),
    )

    if not data:
        return jsonify({
            "success": False,
            "message": "No login data provided.",
        }), 400

    email = data.get("email")
    password = data.get("password")

    if not email:
        return jsonify({
            "success": False,
            "message": "Email is required.",
        }), 400

    if not password:
        return jsonify({
            "success": False,
            "message": "Password is required.",
        }), 400

    email = str(email).strip().lower()
    password = str(password)

    try:

        user = User.query.filter_by(
            email=email
        ).first()

        if user is None:
            return jsonify({
                "success": False,
                "message": "Invalid email or password.",
            }), 401

        # ----------------------------------------------------
        # SOCIAL-ONLY ACCOUNT
        # ----------------------------------------------------

        if not user.password_hash:

            return jsonify({
                "success": False,
                "message": (
                    "This account uses social sign-in. "
                    "Please sign in with your social provider."
                ),
            }), 401

        # ----------------------------------------------------
        # PASSWORD
        # ----------------------------------------------------

        if not check_password_hash(
            user.password_hash,
            password,
        ):
            return jsonify({
                "success": False,
                "message": "Invalid email or password.",
            }), 401

        # ----------------------------------------------------
        # JWT
        # ----------------------------------------------------

        access_token = create_access_token(
            identity=str(user.id)
        )

        logger.info(
            "Login successful for user: %s",
            user.id,
        )

        return jsonify({
            "success": True,
            "message": "Login successful.",
            "accessToken": access_token,
            "user": _user_response(user),
        }), 200

    except Exception:

        logger.exception(
            "Login request failed"
        )

        return jsonify({
            "success": False,
            "message": "Failed to login.",
            "error": "Internal server error.",
        }), 500


# ============================================================
# SOCIAL LOGIN HELPERS
# ============================================================
#
# Both the generic ``/api/auth/social`` (provider + idToken) and the focused
# ``/api/auth/google`` (idToken) endpoints run the same verified pipeline:
#
#   verify the provider ID/identity token server-side
#     -> resolve/create the matching Tripora account
#     -> issue the normal Tripora JWTs and return the login payload
#
# Keeping the logic here (rather than embedded in Google-specific routes)
# keeps the authentication layer provider-agnostic, so adding providers
# (e.g. Sign in with Apple) never requires touching this code.
# ============================================================

class SocialAccountConflictError(Exception):
    """Raised when a verified email is already bound to a different provider."""


def _resolve_social_user(provider, provider_id, email, name, email_verified):
    """Find or create the Tripora user for a *verified* social identity.

    Resolution order:
      1. An account already linked to this exact provider identity
         (``auth_provider`` + ``provider_id``). Precise match, no ambiguity.
      2. An account with the same email:
         - Already linked to the same provider  -> reuse it.
         - A proven email/password account with no provider yet -> link it to
           this identity (safe: the provider verified control of the email,
           so no duplicate account is created and the user keeps their
           existing email/password account too).
         - Linked to a *different* provider -> raise ``SocialAccountConflictError``
           so the endpoint can return 409 instead of silently creating a
           duplicate or hijacking the other identity's account.
      3. No match -> create a new social-only account (no password stored).

    Email/password accounts and social-only accounts share the same ``users``
    table and the email uniqueness constraint, so there is never more than one
    row per identity.
    """
    user = User.query.filter_by(
        auth_provider=provider,
        provider_id=provider_id,
    ).first()

    if user is not None:
        return user

    user = User.query.filter_by(email=email).first()

    if user is not None:
        existing_provider = user.auth_provider

        if existing_provider and existing_provider != provider:
            raise SocialAccountConflictError(
                "Email {} is linked to provider {} for user {}".format(
                    email,
                    existing_provider,
                    user.id,
                )
            )

        user.auth_provider = provider
        user.provider_id = provider_id

        if email_verified:
            user.email_verified = True

        db.session.commit()

        logger.info(
            "Linked %s identity to existing user: %s",
            provider,
            user.id,
        )

        return user

    user = User(
        name=(
            name
            if name
            else email.split("@")[0]
        ),
        email=email,
        password_hash=None,
        email_verified=email_verified,
        auth_provider=provider,
        provider_id=provider_id,
        verification_token=None,
        verification_token_expires_at=None,
    )

    db.session.add(user)
    db.session.commit()

    logger.info(
        "Social account created for user: %s",
        user.id,
    )

    return user


def _social_login(provider, id_token_value, nonce=None):
    """Run the verified social sign-in pipeline and build the response.

    Returns a ``(payload_dict, status_code)`` tuple shared by both endpoints.
    """
    provider = str(provider or "").strip().lower()

    if provider not in {"google", "apple"}:
        return {
            "success": False,
            "message": "Unsupported social provider.",
        }, 400

    if not id_token_value:
        return {
            "success": False,
            "message": "Identity token is required.",
        }, 400

    try:
        claims = verify_identity_token(
            provider,
            id_token_value,
            nonce=nonce,
        )
    except SocialAuthError as error:
        logger.warning(
            "Social login verification failed (%s): %s",
            provider,
            error,
        )
        return {
            "success": False,
            "message": str(error),
        }, 401
    except Exception:
        logger.exception(
            "Unexpected social token verification error (%s)",
            provider,
        )
        return {
            "success": False,
            "message": "Failed to verify social identity.",
        }, 401

    email = claims.get("email")

    if not email:
        return {
            "success": False,
            "message": (
                "Your %s account did not provide "
                "an email address."
                % provider.capitalize()
            ),
        }, 400

    email = str(email).strip().lower()

    name = claims.get("name") or ""

    provider_id = claims.get("provider_id")

    if not provider_id:
        return {
            "success": False,
            "message": "Social provider ID is missing.",
        }, 400

    email_verified = bool(claims.get("email_verified"))

    try:
        user = _resolve_social_user(
            provider,
            provider_id,
            email,
            name,
            email_verified,
        )
    except SocialAccountConflictError as error:
        db.session.rollback()
        logger.warning("Social login blocked: %s", error)
        return {
            "success": False,
            "message": (
                "This email is linked to a different "
                "sign-in method. Please sign in with "
                "that method instead."
            ),
        }, 409
    except Exception:
        db.session.rollback()
        logger.exception(
            "Social login request failed (%s)",
            provider,
        )
        return {
            "success": False,
            "message": (
                "Failed to sign in with %s."
                % provider.capitalize()
            ),
            "error": "Internal server error.",
        }, 500

    access_token = create_access_token(
        identity=str(user.id)
    )

    logger.info(
        "Social login successful for user: %s",
        user.id,
    )

    return {
        "success": True,
        "message": "Login successful.",
        "accessToken": access_token,
        "user": _user_response(user),
    }, 200


# ============================================================
# SOCIAL LOGIN
# POST /api/auth/social
# ============================================================
#
# Generic provider-agnostic endpoint (used for Sign in with Apple and any
# provider added later). Accepts ``{provider, idToken, nonce?}``.

@auth_bp.route("/social", methods=["POST"])
def social_login():

    data = request.get_json(silent=True) or {}

    logger.debug(
        "SOCIAL LOGIN REQUEST PROVIDER: %s",
        data.get("provider"),
    )

    provider = data.get("provider")

    if not provider:
        return jsonify({
            "success": False,
            "message": "Provider is required.",
        }), 400

    id_token_value = data.get("idToken")
    nonce = data.get("nonce")

    payload, status = _social_login(
        provider,
        id_token_value,
        nonce=nonce,
    )

    return jsonify(payload), status


# ============================================================
# GOOGLE LOGIN
# POST /api/auth/google
# ============================================================
#
# Focused Google Sign-In endpoint, used by the mobile app. Accepts a Google
# ID token (``{idToken, nonce?}``). The token is verified server-side with
# Google's official verification mechanism (``google-auth``); the email and
# profile information come from the verified token claims, never from the
# client payload.

@auth_bp.route("/google", methods=["POST"])
def google_login():

    data = request.get_json(silent=True) or {}

    logger.debug(
        "GOOGLE LOGIN REQUEST: %s",
        _redact_sensitive(data),
    )

    id_token_value = data.get("idToken")
    nonce = data.get("nonce")

    payload, status = _social_login(
        "google",
        id_token_value,
        nonce=nonce,
    )

    return jsonify(payload), status


# ============================================================
# PASSWORD RESET
# ============================================================
#
# Flow:
#   1. POST /api/auth/forgot-password  {email}
#        -> emails a 6-digit one-time code (generic response either way;
#           no account enumeration).
#   2. POST /api/auth/forgot-password/verify {email, code}
#        -> verifies the code, and on success returns a short-lived
#           one-time `resetToken`. Wrong codes are rate limited and
#           lock out after RESET_MAX_ATTEMPTS failed tries.
#   3. POST /api/auth/reset-password {resetToken, password}
#        -> verifies the token, sets the new password, and clears ALL
#           reset fields so nothing can be replayed.
#
# Codes and tokens are stored ONLY as hashes. Successful requests are logged
# with the user id but never with the code/token/password/email.

def _clear_reset_fields(user):
    """Remove every password-reset field (code, token, attempts)."""
    user.reset_code_hash = None
    user.reset_code_expires_at = None
    user.reset_attempts = 0
    user.reset_token_hash = None
    user.reset_token_expires_at = None


# ------------------------------------------------------------------
# FORGOT PASSWORD
# POST /api/auth/forgot-password
# ------------------------------------------------------------------

@auth_bp.route("/forgot-password", methods=["POST"])
def forgot_password():

    data = request.get_json(silent=True) or {}

    logger.debug(
        "FORGOT PASSWORD REQUEST: %s",
        _redact_sensitive(data),
    )

    email = data.get("email")

    if not email:
        return jsonify({
            "success": False,
            "message": "Email is required.",
        }), 400

    email = str(email).strip().lower()

    try:
        user = User.query.filter_by(email=email).first()
    except Exception:
        logger.exception("Forgot-password lookup failed")
        user = None

    if user is None:
        # Do not reveal whether the account exists.
        logger.info("Forgot-password requested for unknown email")
        return jsonify({
            "success": True,
            "message": GENERIC_RESET_MESSAGE,
        }), 200

    # Social-only accounts have no password to reset; respond generically so
    # we never leak that the account is social-only through this endpoint.
    if not user.password_hash:
        logger.info("Forgot-password skipped for social-only user: %s", user.id)
        return jsonify({
            "success": True,
            "message": GENERIC_RESET_MESSAGE,
        }), 200

    code = "{:06d}".format(secrets.randbelow(1_000_000))

    user.reset_code_hash = generate_password_hash(code)
    user.reset_code_expires_at = datetime.utcnow() + timedelta(
        minutes=RESET_CODE_LIFETIME_MINUTES
    )
    user.reset_attempts = 0
    # A new code invalidates any previously issued reset token.
    user.reset_token_hash = None
    user.reset_token_expires_at = None

    try:
        db.session.commit()
        sent = send_password_reset_code(user.email, code)
    except Exception:
        db.session.rollback()
        logger.exception("Failed to persist password-reset code")
        sent = False

    logger.info("Password reset code issued to user: %s (delivered=%s)", user.id, sent)

    # Even if delivery failed we keep the generic message; the user can retry.
    return jsonify({
        "success": True,
        "message": GENERIC_RESET_MESSAGE,
    }), 200


# ------------------------------------------------------------------
# VERIFY RESET CODE
# POST /api/auth/forgot-password/verify
# ------------------------------------------------------------------

@auth_bp.route("/forgot-password/verify", methods=["POST"])
def verify_reset_code():

    data = request.get_json(silent=True) or {}

    logger.debug(
        "VERIFY RESET CODE REQUEST: %s",
        _redact_sensitive(data),
    )

    email = data.get("email")
    code = data.get("code")

    if not email or not code:
        return jsonify({
            "success": False,
            "message": "Email and code are required.",
        }), 400

    email = str(email).strip().lower()
    code = str(code).strip()

    try:
        user = User.query.filter_by(email=email).first()
    except Exception:
        logger.exception("Reset-code verification lookup failed")
        user = None

    if user is None:
        return jsonify({
            "success": False,
            "message": INVALID_RESET_CODE_MESSAGE,
        }), 400

    now = datetime.utcnow()
    code_valid = (
        user.reset_code_hash is not None
        and user.reset_code_expires_at is not None
        and user.reset_code_expires_at > now
        and user.reset_attempts < RESET_MAX_ATTEMPTS
    )

    if not code_valid:
        return jsonify({
            "success": False,
            "message": INVALID_RESET_CODE_MESSAGE,
        }), 400

    if not check_password_hash(user.reset_code_hash, code):
        user.reset_attempts = (user.reset_attempts or 0) + 1
        locked = user.reset_attempts >= RESET_MAX_ATTEMPTS
        if locked:
            # Brute-force protection: force the user to request a new code.
            _clear_reset_fields(user)
        db.session.commit()
        if locked:
            logger.warning(
                "Password reset locked out after failed attempts: %s", user.id
            )
        return jsonify({
            "success": False,
            "message": INVALID_RESET_CODE_MESSAGE,
        }), 400

    # Code verified -> issue the one-time reset token.
    reset_token = secrets.token_urlsafe(32)
    user.reset_attempts = 0
    user.reset_token_hash = generate_password_hash(reset_token)
    user.reset_token_expires_at = now + timedelta(
        minutes=RESET_TOKEN_LIFETIME_MINUTES
    )
    db.session.commit()

    logger.info("Password reset code verified for user: %s", user.id)

    return jsonify({
        "success": True,
        "message": "Code verified. You can now reset your password.",
        "resetToken": reset_token,
    }), 200


# ------------------------------------------------------------------
# RESET PASSWORD
# POST /api/auth/reset-password
# ------------------------------------------------------------------

@auth_bp.route("/reset-password", methods=["POST"])
def reset_password():

    data = request.get_json(silent=True) or {}

    logger.debug(
        "RESET PASSWORD REQUEST: %s",
        _redact_sensitive(data),
    )

    reset_token = data.get("resetToken")
    password = data.get("password")

    if not reset_token:
        return jsonify({
            "success": False,
            "message": "Reset token is required.",
        }), 400

    if not password:
        return jsonify({
            "success": False,
            "message": "New password is required.",
        }), 400

    password = str(password)

    if len(password) < 8:
        return jsonify({
            "success": False,
            "message": "New password must be at least 8 characters.",
        }), 400

    now = datetime.utcnow()

    try:
        # Reset tokens are stored hashed, so match by scanning only the small
        # set of users holding an (unexpired) token.
        candidates = User.query.filter(
            User.reset_token_hash.isnot(None)
        ).all()

        user = None
        for candidate in candidates:
            if (
                candidate.reset_token_expires_at is not None
                and candidate.reset_token_expires_at > now
                and check_password_hash(
                    candidate.reset_token_hash,
                    str(reset_token),
                )
            ):
                user = candidate
                break

        if user is None:
            return jsonify({
                "success": False,
                "message": INVALID_RESET_TOKEN_MESSAGE,
            }), 400
        
        if check_password_hash(user.passwod_hash, password):
            return jsonify({
                "succes": False,
                "message": "New password must be different from your old password."
            })

        user.password_hash = generate_password_hash(password)
        _clear_reset_fields(user)
        db.session.commit()

        logger.info("Password reset completed for user: %s", user.id)

        return jsonify({
            "success": True,
            "message": "Password reset successfully. You can now sign in.",
        }), 200

    except Exception:
        db.session.rollback()
        logger.exception("Password reset failed")
        return jsonify({
            "success": False,
            "message": "Failed to reset password.",
            "error": "Internal server error.",
        }), 500


# ============================================================
# GET CURRENT USER
# GET /api/auth/me
# ============================================================

@auth_bp.route("/me", methods=["GET"])
@jwt_required()
def get_current_user():

    try:

        user_id = get_jwt_identity()

        user = db.session.get(
            User,
            int(user_id),
        )

        if user is None:
            return jsonify({
                "success": False,
                "message": "User not found.",
            }), 404

        return jsonify({
            "success": True,
            "user": _user_response(user),
        }), 200

    except Exception:

        logger.exception(
            "Get current user failed"
        )

        return jsonify({
            "success": False,
            "message": "Failed to retrieve current user.",
            "error": "Internal server error.",
        }), 500


# ============================================================
# UPDATE CURRENT USER
# PATCH /api/auth/me
# ============================================================

@auth_bp.route("/me", methods=["PATCH"])
@jwt_required()
def update_current_user():

    try:

        user_id = get_jwt_identity()

        user = db.session.get(
            User,
            int(user_id),
        )

        if user is None:
            return jsonify({
                "success": False,
                "message": "User not found.",
            }), 404

        data = request.get_json(silent=True) or {}

        if not data:
            return jsonify({
                "success": False,
                "message": "No account data provided.",
            }), 400

        name = data.get("name")
        email = data.get("email")
        password = data.get("password")
        current_password = data.get("currentPassword")
        preferred_language = data.get("preferredLanguage")
        preferred_currency = data.get("preferredCurrency")

        # ----------------------------------------------------
        # UPDATE NAME
        # ----------------------------------------------------

        if name is not None:

            clean_name = str(name).strip()

            if not clean_name:
                return jsonify({
                    "success": False,
                    "message": "Name cannot be empty.",
                }), 400

            user.name = clean_name

        # ----------------------------------------------------
        # UPDATE EMAIL
        # ----------------------------------------------------

        if email is not None:

            clean_email = str(email).strip().lower()

            if not clean_email:
                return jsonify({
                    "success": False,
                    "message": "Email cannot be empty.",
                }), 400

            if clean_email != user.email:

                existing_user = User.query.filter_by(
                    email=clean_email
                ).first()

                if existing_user is not None:

                    return jsonify({
                        "success": False,
                        "message": (
                            "An account with this email "
                            "already exists."
                        ),
                    }), 409

                user.email = clean_email

        # ----------------------------------------------------
        # UPDATE LANGUAGE
        # ----------------------------------------------------

        if preferred_language is not None:

            clean_language = (
                str(preferred_language)
                .strip()
                .lower()
            )

            if clean_language not in VALID_LANGUAGES:

                return jsonify({
                    "success": False,
                    "message": "Preferred language is invalid.",
                }), 400

            user.preferred_language = clean_language

        # ----------------------------------------------------
        # UPDATE CURRENCY
        # ----------------------------------------------------

        if preferred_currency is not None:

            clean_currency = (
                str(preferred_currency)
                .strip()
                .upper()
            )

            if clean_currency not in VALID_CURRENCIES:

                return jsonify({
                    "success": False,
                    "message": "Preferred currency is invalid.",
                }), 400

            user.preferred_currency = clean_currency

        # ----------------------------------------------------
        # UPDATE PASSWORD
        # ----------------------------------------------------

        if password is not None:

            password_value = str(password)

            if len(password_value) < 6:

                return jsonify({
                    "success": False,
                    "message": (
                        "New password must be at least "
                        "6 characters."
                    ),
                }), 400

            if current_password is None:

                return jsonify({
                    "success": False,
                    "message": (
                        "Current password is required to "
                        "change your password."
                    ),
                }), 400

            # Social-only accounts have no password.
            if not user.password_hash:

                return jsonify({
                    "success": False,
                    "message": (
                        "This account does not have a password. "
                        "Please use the appropriate account "
                        "recovery or sign-in method."
                    ),
                }), 400

            if not check_password_hash(
                user.password_hash,
                str(current_password),
            ):

                return jsonify({
                    "success": False,
                    "message": "Current password is incorrect.",
                }), 401

            user.password_hash = generate_password_hash(
                password_value
            )

        # ----------------------------------------------------
        # SAVE CHANGES
        # ----------------------------------------------------

        db.session.commit()

        return jsonify({
            "success": True,
            "message": "Account updated successfully.",
            "user": _user_response(user),
        }), 200

    except Exception:

        db.session.rollback()

        logger.exception(
            "Update current user failed"
        )

        return jsonify({
            "success": False,
            "message": "Failed to update account.",
            "error": "Internal server error.",
        }), 500


# ============================================================
# DELETE CURRENT USER (ACCOUNT DELETION)
# DELETE /api/auth/account
# ============================================================
#
# Permanently deletes the authenticated user and all of their
# owned data. There is no DB-level ON DELETE CASCADE in this
# schema, so child rows (activity logs, trips)
# are removed explicitly here, in dependency order, before the
# user row itself. The whole operation is transactional.
#
# Note: the account is deleted immediately; the returned table
# of contents is intentionally minimal since the row is gone.

@auth_bp.route("/account", methods=["DELETE"])
@jwt_required()
def delete_current_user():

    try:

        user_id = get_jwt_identity()

        user = db.session.get(
            User,
            int(user_id),
        )

        if user is None:
            return jsonify({
                "success": False,
                "message": "User not found.",
            }), 404

        # ------------------------------------------------------
        # Delete the user's owned data (no DB-level cascade).
        # ------------------------------------------------------

        ActivityLog.query.filter_by(user_id=user.id).delete(
            synchronize_session=False
        )
        Trip.query.filter_by(user_id=user.id).delete(
            synchronize_session=False
        )

        db.session.delete(user)
        db.session.commit()

        logger.info("Account deleted: %s", user.id)

        return jsonify({
            "success": True,
            "message": "Account deleted successfully.",
        }), 200

    except Exception:

        db.session.rollback()

        logger.exception(
            "Delete current user failed"
        )

        return jsonify({
            "success": False,
            "message": "Failed to delete account.",
            "error": "Internal server error.",
        }), 500