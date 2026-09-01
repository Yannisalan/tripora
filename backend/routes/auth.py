import logging
from datetime import datetime

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
    generate_verification_expiry,
    generate_verification_token,
)

from models.activity_log import ActivityLog
from models.subscription import Subscription
from models.trip import Trip

from services.email_service import send_verification_email

from services.social_auth_service import (
    SocialAuthError,
    verify_identity_token,
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


def _verification_code_expired(user):
    """Return True when the user's verification code has expired."""

    if user.verification_token_expires_at is None:
        return True

    return datetime.utcnow() > user.verification_token_expires_at


def _generate_new_verification_code(user):
    """Generate a new verification code and its expiry."""

    user.verification_token = generate_verification_token()
    user.verification_token_expires_at = (
        generate_verification_expiry()
    )


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
        # VERIFICATION CODE + EXPIRY
        # ----------------------------------------------------

        verification_token = generate_verification_token()
        verification_expiry = generate_verification_expiry()

        # ----------------------------------------------------
        # CREATE USER
        # ----------------------------------------------------

        user = User(
            name=name,
            email=email,
            password_hash=password_hash,
            preferred_language=preferred_language,
            preferred_currency=preferred_currency,
            email_verified=False,
            verification_token=verification_token,
            verification_token_expires_at=verification_expiry,
        )

        db.session.add(user)
        db.session.commit()

        logger.info(
            "User registered successfully: %s",
            user.id,
        )

        # ----------------------------------------------------
        # SEND VERIFICATION EMAIL
        # ----------------------------------------------------

        email_sent = send_verification_email(
            user.email,
            user.verification_token,
        )

        if not email_sent:
            logger.warning(
                "Verification email could not be sent to %s",
                user.email,
            )

        return jsonify({
            "success": True,
            "message": (
                "Registration successful. A verification code "
                "has been sent to your email address."
            ),
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
# VERIFY EMAIL
# POST /api/auth/verify-email
# ============================================================

@auth_bp.route("/verify-email", methods=["POST"])
def verify_email():

    data = request.get_json(silent=True) or {}

    logger.debug(
        "VERIFY EMAIL REQUEST: %s",
        _redact_sensitive(data),
    )

    token = str(
        data.get("token", "")
    ).strip()

    if not token:
        return jsonify({
            "success": False,
            "message": "Verification code is required.",
        }), 400

    try:

        user = User.query.filter_by(
            verification_token=token
        ).first()

        if user is None:
            return jsonify({
                "success": False,
                "message": "Invalid or expired verification code.",
            }), 404

        # ----------------------------------------------------
        # CHECK EXPIRY
        # ----------------------------------------------------

        if _verification_code_expired(user):

            user.verification_token = None
            user.verification_token_expires_at = None

            db.session.commit()

            return jsonify({
                "success": False,
                "message": (
                    "This verification code has expired. "
                    "Please request a new code."
                ),
            }), 400

        # ----------------------------------------------------
        # VERIFY EMAIL
        # ----------------------------------------------------

        user.email_verified = True

        # Invalidate code after successful verification.
        user.verification_token = None
        user.verification_token_expires_at = None

        db.session.commit()

        logger.info(
            "Email verified successfully for user: %s",
            user.id,
        )

        return jsonify({
            "success": True,
            "message": "Email verified successfully.",
            "user": _user_response(user),
        }), 200

    except Exception:

        db.session.rollback()

        logger.exception(
            "Email verification failed"
        )

        return jsonify({
            "success": False,
            "message": "Failed to verify email.",
            "error": "Internal server error.",
        }), 500


# ============================================================
# RESEND VERIFICATION
# POST /api/auth/resend-verification
# ============================================================

@auth_bp.route("/resend-verification", methods=["POST"])
def resend_verification():

    data = request.get_json(silent=True) or {}

    email = str(
        data.get("email", "")
    ).strip().lower()

    if not email:
        return jsonify({
            "success": False,
            "message": "Email is required.",
        }), 400

    try:

        user = User.query.filter_by(
            email=email
        ).first()

        if user is None:
            return jsonify({
                "success": False,
                "message": "No account was found for that email.",
            }), 404

        if user.email_verified:
            return jsonify({
                "success": True,
                "message": (
                    "This email address is already verified."
                ),
                "user": _user_response(user),
            }), 200

        # ----------------------------------------------------
        # GENERATE NEW CODE + NEW EXPIRY
        # ----------------------------------------------------

        _generate_new_verification_code(user)

        db.session.commit()

        # ----------------------------------------------------
        # SEND EMAIL
        # ----------------------------------------------------

        email_sent = send_verification_email(
            user.email,
            user.verification_token,
        )

        if not email_sent:

            logger.warning(
                "Verification email could not be sent to %s",
                user.email,
            )

            return jsonify({
                "success": False,
                "message": "Failed to send verification email.",
            }), 500

        return jsonify({
            "success": True,
            "message": (
                "A new verification code has been sent "
                "to your email address."
            ),
            "user": _user_response(user),
        }), 200

    except Exception:

        db.session.rollback()

        logger.exception(
            "Resend verification failed"
        )

        return jsonify({
            "success": False,
            "message": "Failed to resend verification code.",
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
        # EMAIL VERIFICATION
        # ----------------------------------------------------

        if not user.email_verified:

            return jsonify({
                "success": False,
                "message": (
                    "Please verify your email address "
                    "before signing in."
                ),
            }), 403

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
# SOCIAL LOGIN
# POST /api/auth/social
# ============================================================

@auth_bp.route("/social", methods=["POST"])
def social_login():

    data = request.get_json(silent=True) or {}

    logger.debug(
        "SOCIAL LOGIN REQUEST PROVIDER: %s",
        data.get("provider"),
    )

    provider = data.get("provider")
    id_token_value = data.get("idToken")
    nonce = data.get("nonce")

    if not provider:
        return jsonify({
            "success": False,
            "message": "Provider is required.",
        }), 400

    provider = str(provider).strip().lower()

    if provider not in {"google", "apple"}:
        return jsonify({
            "success": False,
            "message": "Unsupported social provider.",
        }), 400

    if not id_token_value:
        return jsonify({
            "success": False,
            "message": "Identity token is required.",
        }), 400

    try:

        claims = verify_identity_token(
            provider,
            id_token_value,
            nonce=nonce,
        )

    except SocialAuthError as error:

        logger.warning(
            "Social login verification failed: %s",
            error,
        )

        return jsonify({
            "success": False,
            "message": str(error),
        }), 401

    except Exception:

        logger.exception(
            "Unexpected social token verification error"
        )

        return jsonify({
            "success": False,
            "message": "Failed to verify social identity.",
        }), 401

    email = claims.get("email")

    if not email:
        return jsonify({
            "success": False,
            "message": (
                "Your %s account did not provide "
                "an email address."
                % provider.capitalize()
            ),
        }), 400

    email = str(email).strip().lower()

    name = claims.get("name") or ""

    provider_id = claims.get("provider_id")

    if not provider_id:
        return jsonify({
            "success": False,
            "message": "Social provider ID is missing.",
        }), 400

    email_verified = bool(
        claims.get("email_verified")
    )

    try:

        # ----------------------------------------------------
        # FIND EXISTING USER
        # ----------------------------------------------------

        user = User.query.filter_by(
            email=email
        ).first()

        if user is None:

            # ------------------------------------------------
            # CREATE SOCIAL ACCOUNT
            # ------------------------------------------------

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

        else:

            # ------------------------------------------------
            # CHECK PROVIDER
            # ------------------------------------------------

            existing_provider = user.auth_provider

            if (
                existing_provider
                and existing_provider != provider
            ):
                return jsonify({
                    "success": False,
                    "message": (
                        "This email is linked to a different "
                        "sign-in method. Please sign in with "
                        "that method instead."
                    ),
                }), 409

            # ------------------------------------------------
            # UPDATE PROVIDER INFORMATION
            # ------------------------------------------------

            user.auth_provider = provider
            user.provider_id = provider_id

            if email_verified:
                user.email_verified = True

            db.session.commit()

        # ----------------------------------------------------
        # CREATE JWT
        # ----------------------------------------------------

        access_token = create_access_token(
            identity=str(user.id)
        )

        logger.info(
            "Social login successful for user: %s",
            user.id,
        )

        return jsonify({
            "success": True,
            "message": "Login successful.",
            "accessToken": access_token,
            "user": _user_response(user),
        }), 200

    except Exception:

        db.session.rollback()

        logger.exception(
            "Social login request failed"
        )

        return jsonify({
            "success": False,
            "message": (
                "Failed to sign in with %s."
                % provider.capitalize()
            ),
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

        email_changed = False

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
                user.email_verified = False

                # New email = new verification code + new expiry.
                _generate_new_verification_code(user)

                email_changed = True

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

        # ----------------------------------------------------
        # SEND VERIFICATION EMAIL AFTER EMAIL CHANGE
        # ----------------------------------------------------

        if email_changed:

            email_sent = send_verification_email(
                user.email,
                user.verification_token,
            )

            if not email_sent:

                logger.warning(
                    "Verification email could not be sent "
                    "after email change to %s",
                    user.email,
                )

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
# schema, so child rows (activity logs, trips, subscriptions)
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
        Subscription.query.filter_by(user_id=user.id).delete(
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