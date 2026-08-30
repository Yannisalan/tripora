import logging
import secrets

from flask import Blueprint, jsonify, request
from werkzeug.security import (
    check_password_hash,
    generate_password_hash,
)

from flask_jwt_extended import (
    create_access_token,
    jwt_required,
    get_jwt_identity,
)

from config.database import db
from models.user import User
from services.email_service import send_verification_email
from services.social_auth_service import (
    SocialAuthError,
    verify_identity_token,
)

logger = logging.getLogger(__name__)


def _redact_sensitive(data):
    """Return a copy of the request payload safe to log.

    Credentials (e.g. ``password``) must never be written to logs.
    """
    if not isinstance(data, dict):
        return data
    safe = dict(data)
    if "password" in safe:
        safe["password"] = "[REDACTED]"
    if "currentPassword" in safe:
        safe["currentPassword"] = "[REDACTED]"
    return safe


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

    logger.debug("REGISTER REQUEST: %s", _redact_sensitive(data))

    # --------------------------------------------------------
    # VALIDATE REQUEST
    # --------------------------------------------------------

    if not data:
        return jsonify({
            "success": False,
            "message": "No registration data provided.",
        }), 400

    name = data.get("name")
    email = data.get("email")
    password = data.get("password")
    preferred_language = data.get("preferredLanguage", "en")
    preferred_currency = data.get("preferredCurrency", "USD")

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

    preferred_language = str(preferred_language).strip().lower() or "en"
    preferred_currency = str(preferred_currency).strip().upper() or "USD"

    valid_languages = {"en", "es", "fr", "de", "it", "pt"}
    valid_currencies = {"USD", "EUR", "GBP", "CAD", "AUD", "AED", "JPY", "CHF"}

    if preferred_language not in valid_languages:
        return jsonify({
            "success": False,
            "message": "Preferred language is invalid.",
        }), 400

    if preferred_currency not in valid_currencies:
        return jsonify({
            "success": False,
            "message": "Preferred currency is invalid.",
        }), 400

    # --------------------------------------------------------
    # CHECK EXISTING USER
    # --------------------------------------------------------

    try:

        existing_user = User.query.filter_by(
            email=email
        ).first()

        if existing_user:

            return jsonify({
                "success": False,
                "message": "An account with this email already exists.",
            }), 409

        # ----------------------------------------------------
        # HASH PASSWORD
        # ----------------------------------------------------

        password_hash = generate_password_hash(
            password
        )

        # ----------------------------------------------------
        # CREATE USER
        # ----------------------------------------------------

        user = User(
            name=name,
            email=email,
            password_hash=password_hash,
            preferred_language=preferred_language,
            preferred_currency=preferred_currency,
        )

        db.session.add(user)
        db.session.commit()

        logger.info("User registered successfully: %s", user.id)

        # ----------------------------------------------------
        # SEND VERIFICATION EMAIL
        # ----------------------------------------------------

        # The token is NOT returned to the client. It is sent to
        # the user's email address instead.
        send_verification_email(user.email, user.verification_token)

        return jsonify({
            "success": True,
            "message": (
                "Registration successful. A verification code has "
                "been sent to your email address."
            ),
            "user": {
                "id": user.id,
                "name": user.name,
                "email": user.email,
                "emailVerified": user.email_verified,
                "preferredLanguage": user.preferred_language,
                "preferredCurrency": user.preferred_currency,
                "createdAt": (
                    user.created_at.isoformat()
                    if user.created_at
                    else None
                ),
            },
        }), 201

    except Exception as error:

        db.session.rollback()

        logger.exception("Register request failed")

        return jsonify({
            "success": False,
            "message": "Failed to register user.",
            "error": "Internal server error.",
        }), 500


# ============================================================
# LOGIN
# POST /api/auth/login
# ============================================================

@auth_bp.route("/verify-email", methods=["POST"])
def verify_email():
    data = request.get_json(silent=True) or {}
    token = str(data.get("token", "")).strip()

    if not token:
        return jsonify({
            "success": False,
            "message": "Verification token is required.",
        }), 400

    user = User.query.filter_by(verification_token=token).first()

    if user is None:
        return jsonify({
            "success": False,
            "message": "Invalid or expired verification token.",
        }), 404

    user.email_verified = True
    user.verification_token = secrets.token_urlsafe(32)
    db.session.commit()

    return jsonify({
        "success": True,
        "message": "Email verified successfully.",
        "user": {
            "id": user.id,
            "name": user.name,
            "email": user.email,
            "emailVerified": user.email_verified,
            "preferredLanguage": user.preferred_language,
            "preferredCurrency": user.preferred_currency,
        },
    }), 200


@auth_bp.route("/resend-verification", methods=["POST"])
def resend_verification():
    data = request.get_json(silent=True) or {}
    email = str(data.get("email", "")).strip().lower()

    if not email:
        return jsonify({
            "success": False,
            "message": "Email is required.",
        }), 400

    user = User.query.filter_by(email=email).first()

    if user is None:
        return jsonify({
            "success": False,
            "message": "No account was found for that email.",
        }), 404

    if user.email_verified:
        return jsonify({
            "success": True,
            "message": "This email address is already verified.",
            "user": {
                "id": user.id,
                "email": user.email,
                "emailVerified": True,
            },
        }), 200

    user.verification_token = secrets.token_urlsafe(32)
    db.session.commit()

    # The token is sent to the user's email, not returned to the
    # client/UI.
    send_verification_email(user.email, user.verification_token)

    return jsonify({
        "success": True,
        "message": (
            "A new verification code has been sent to your email address."
        ),
        "user": {
            "id": user.id,
            "email": user.email,
            "emailVerified": False,
        },
    }), 200


@auth_bp.route("/login", methods=["POST"])
def login():

    data = request.get_json(silent=True)

    logger.debug("LOGIN REQUEST: %s", _redact_sensitive(data))

    # --------------------------------------------------------
    # VALIDATE REQUEST
    # --------------------------------------------------------

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

    # --------------------------------------------------------
    # CLEAN DATA
    # --------------------------------------------------------

    email = str(email).strip().lower()
    password = str(password)

    # --------------------------------------------------------
    # FIND USER
    # --------------------------------------------------------

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
        # CHECK PASSWORD
        # ----------------------------------------------------

        if not check_password_hash(
            user.password_hash,
            password,
        ):

            return jsonify({
                "success": False,
                "message": "Invalid email or password.",
            }), 401

        if not user.email_verified:
            return jsonify({
                "success": False,
                "message": "Please verify your email address before signing in.",
            }), 403

        # ----------------------------------------------------
        # CREATE JWT
        # ----------------------------------------------------

        access_token = create_access_token(
            identity=str(user.id)
        )

        logger.info("Login successful for user: %s", user.id)

        # ----------------------------------------------------
        # RETURN LOGIN RESPONSE
        # ----------------------------------------------------

        return jsonify({
            "success": True,
            "message": "Login successful.",

            # IMPORTANT:
            # Flutter expects accessToken
            "accessToken": access_token,

            "user": {
                "id": user.id,
                "name": user.name,
                "email": user.email,
                "emailVerified": user.email_verified,
                "preferredLanguage": user.preferred_language,
                "preferredCurrency": user.preferred_currency,
                "createdAt": (
                    user.created_at.isoformat()
                    if user.created_at
                    else None
                ),
            },
        }), 200

    except Exception as error:

        logger.exception("Login request failed")

        return jsonify({
            "success": False,
            "message": "Failed to login.",
            "error": "Internal server error.",
        }), 500


# ============================================================
# SOCIAL LOGIN (GOOGLE / APPLE)
# POST /api/auth/social
# ============================================================

@auth_bp.route("/social", methods=["POST"])
def social_login():

    data = request.get_json(silent=True) or {}

    logger.debug("SOCIAL LOGIN REQUEST PROVIDER: %s", data.get("provider"))

    provider = data.get("provider")
    id_token_value = data.get("idToken")
    nonce = data.get("nonce")

    if not provider:
        return jsonify({
            "success": False,
            "message": "Provider is required.",
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
        logger.warning("Social login verification failed: %s", error)
        return jsonify({
            "success": False,
            "message": str(error),
        }), 401

    email = claims["email"]
    name = claims.get("name") or ""

    if not email:
        return jsonify({
            "success": False,
            "message": "Your %s account did not provide an email address." % 
            provider.capitalize(),
        }), 400

    provider_id = claims["provider_id"]
    email_verified = bool(claims.get("email_verified"))

    try:
        # --------------------------------------------------------
        # FIND EXISTING USER BY EMAIL
        # --------------------------------------------------------
        user = User.query.filter_by(email=email).first()

        if user is None:
            # ----------------------------------------------------
            # CREATE NEW ACCOUNT FROM SOCIAL LOGIN
            # ----------------------------------------------------
            user = User(
                name=name if name else email.split("@")[0],
                email=email,
                password_hash=None,
                email_verified=email_verified,
                auth_provider=provider,
                provider_id=provider_id,
            )

            db.session.add(user)
            db.session.commit()

            logger.info("Social account created for user: %s", user.id)

        else:
            # ----------------------------------------------------
            # LINK PROVIDER TO EXISTING ACCOUNT
            # ----------------------------------------------------
            existing_provider = user.auth_provider

            if existing_provider and existing_provider != provider:
                return jsonify({
                    "success": False,
                    "message": (
                        "This email is linked to a different sign-in "
                        "method. Please sign in with that method instead."
                    ),
                }), 409

            user.auth_provider = provider
            user.provider_id = provider_id

            if email_verified:
                user.email_verified = True

            db.session.commit()

        # --------------------------------------------------------
        # CREATE JWT
        # --------------------------------------------------------
        access_token = create_access_token(identity=str(user.id))

        logger.info("Social login successful for user: %s", user.id)

        # --------------------------------------------------------
        # RETURN SOCIAL LOGIN RESPONSE
        # --------------------------------------------------------
        return jsonify({
            "success": True,
            "message": "Login successful.",
            "accessToken": access_token,
            "user": {
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
            },
        }), 200

    except Exception as error:
        db.session.rollback()
        logger.exception("Social login request failed")
        return jsonify({
            "success": False,
            "message": "Failed to sign in with %s." % provider.capitalize(),
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

        # ----------------------------------------------------
        # GET USER ID FROM JWT
        # ----------------------------------------------------

        user_id = get_jwt_identity()

        # ----------------------------------------------------
        # FIND USER
        # ----------------------------------------------------

        user = db.session.get(
            User,
            int(user_id),
        )

        if user is None:

            return jsonify({
                "success": False,
                "message": "User not found.",
            }), 404

        # ----------------------------------------------------
        # RETURN USER
        # ----------------------------------------------------

        return jsonify({
            "success": True,
            "user": {
                "id": user.id,
                "name": user.name,
                "email": user.email,
                "emailVerified": user.email_verified,
                "preferredLanguage": user.preferred_language,
                "preferredCurrency": user.preferred_currency,
                "createdAt": (
                    user.created_at.isoformat()
                    if user.created_at
                    else None
                ),
            },
        }), 200

    except Exception as error:

        logger.exception("Get current user failed")

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
        user = db.session.get(User, int(user_id))

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

        if name is not None:
            clean_name = str(name).strip()
            if not clean_name:
                return jsonify({
                    "success": False,
                    "message": "Name cannot be empty.",
                }), 400
            user.name = clean_name

        if email is not None:
            clean_email = str(email).strip().lower()
            if not clean_email:
                return jsonify({
                    "success": False,
                    "message": "Email cannot be empty.",
                }), 400

            if clean_email != user.email:
                existing_user = User.query.filter_by(email=clean_email).first()
                if existing_user is not None:
                    return jsonify({
                        "success": False,
                        "message": "An account with this email already exists.",
                    }), 409
                user.email = clean_email
                user.email_verified = False
                user.verification_token = secrets.token_urlsafe(32)

        if preferred_language is not None:
            clean_language = str(preferred_language).strip().lower()
            valid_languages = {"en", "es", "fr", "de", "it", "pt"}
            if clean_language not in valid_languages:
                return jsonify({
                    "success": False,
                    "message": "Preferred language is invalid.",
                }), 400
            user.preferred_language = clean_language

        if preferred_currency is not None:
            clean_currency = str(preferred_currency).strip().upper()
            valid_currencies = {"USD", "EUR", "GBP", "CAD", "AUD", "AED", "JPY", "CHF"}
            if clean_currency not in valid_currencies:
                return jsonify({
                    "success": False,
                    "message": "Preferred currency is invalid.",
                }), 400
            user.preferred_currency = clean_currency

        if password is not None:
            password_value = str(password)
            if len(password_value) < 6:
                return jsonify({
                    "success": False,
                    "message": "New password must be at least 6 characters.",
                }), 400

            if current_password is None:
                return jsonify({
                    "success": False,
                    "message": "Current password is required to change your password.",
                }), 400

            if not check_password_hash(user.password_hash, str(current_password)):
                return jsonify({
                    "success": False,
                    "message": "Current password is incorrect.",
                }), 401

            user.password_hash = generate_password_hash(password_value)

        db.session.commit()

        return jsonify({
            "success": True,
            "message": "Account updated successfully.",
            "user": {
                "id": user.id,
                "name": user.name,
                "email": user.email,
                "emailVerified": user.email_verified,
                "preferredLanguage": user.preferred_language,
                "preferredCurrency": user.preferred_currency,
                "createdAt": (
                    user.created_at.isoformat()
                    if user.created_at
                    else None
                ),
            },
        }), 200

    except Exception as error:
        db.session.rollback()
        logger.exception("Update current user failed")
        return jsonify({
            "success": False,
            "message": "Failed to update account.",
            "error": "Internal server error.",
        }), 500