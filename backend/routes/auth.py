import hashlib
import hmac
import logging
import secrets
import time
import uuid
from datetime import datetime, timedelta
from flask import Blueprint, jsonify, request

from sqlalchemy import func, update

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
from config.settings import Config

from models.user import (
    User,
)

from models.activity_log import ActivityLog
from models.trip import Trip
from models.weather_cache import WeatherCache
from models.user_refresh_token import UserRefreshToken

from services.social_auth_service import (
    SocialAuthError,
    verify_identity_token,
)

from services.email_service import (
    send_existing_account_notice,
    send_password_reset_code,
    send_verification_code,
)
from models.admin_security import (
    AdminMfa,
    AdminRecoveryCode,
    AdminSession,
)
from models.expense import Expense
from services import bot_protection, turnstile
from services.client_errors import INVALID_SESSION_MESSAGE
from services.rate_limiter import (
    limiter,
    RateLimitExceeded,
    RateLimitUnavailable,
)


logger = logging.getLogger(__name__)


class InvalidIdentityError(ValueError):
    """Raised when the JWT identity is missing or not a valid user id."""


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

INVALID_LOGIN_MESSAGE = "Invalid email or password."

# ---- Email verification policy ----------------------------------------
VERIFY_CODE_LIFETIME_MINUTES = 30
VERIFY_MAX_ATTEMPTS = 5
VERIFY_RESEND_COOLDOWN_SECONDS = 60
# Minimum gap between "someone tried to register with your address" notices
# sent to an existing account, so the register endpoint cannot be used to
# flood a victim's inbox.
EXISTING_ACCOUNT_NOTICE_COOLDOWN_SECONDS = 3600

# Identical for new, unverified and existing addresses (no enumeration).
GENERIC_REGISTER_MESSAGE = (
    "Check your email for a verification code to finish creating "
    "your account."
)
INVALID_VERIFY_CODE_MESSAGE = "Invalid or expired verification code."
EMAIL_UNVERIFIED_ERROR = "email_unverified"

# Fresh provider sign-in required to delete a social-only account.
SOCIAL_REAUTH_MAX_AGE_SECONDS = 600

NAME_MAX_LENGTH = 100
EMAIL_MAX_LENGTH = 255

# Reset tokens are 256-bit random values; a fast hash with an index lookup is
# safe for them. Older tokens were stored with a password hash ("scrypt:" /
# "pbkdf2:" prefix) and are still accepted until they expire.
RESET_TOKEN_SHA256_PREFIX = "sha256$"

# ---- Password policy -------------------------------------------------
# One policy for registration, password reset and password change.
# 128 characters is far above any human-chosen password and bounds the
# hashing cost of a single request.
PASSWORD_MIN_LENGTH = 8
PASSWORD_MAX_LENGTH = 128

# Passwords that top every public breach list. A full breached-password
# check (e.g. HIBP k-anonymity) is a recommended follow-up; this list stops
# the most common choices without a network dependency.
COMMON_PASSWORDS = frozenset({
    "12345678", "123456789", "1234567890", "password", "password1",
    "password123", "qwertyuiop", "qwerty123", "11111111", "00000000",
    "iloveyou", "abc12345", "abcd1234", "1q2w3e4r", "sunshine",
    "princess", "football", "baseball", "welcome1", "admin123",
    "letmein1", "trustno1", "passw0rd", "87654321", "12341234",
    "tripora1", "tripora123",
})

# Pre-computed hash used to equalise login timing when the email does not
# exist, so response time does not reveal which accounts are registered.
_DUMMY_PASSWORD_HASH = generate_password_hash("tripora-timing-equaliser")


# ============================================================
# HELPERS
# ============================================================

def _password_policy_error(password, label="Password"):
    """Return a user-facing error for a password that fails policy, else None."""

    if not isinstance(password, str):
        return "{} must be text.".format(label)

    if len(password) < PASSWORD_MIN_LENGTH:
        return "{} must be at least {} characters.".format(
            label, PASSWORD_MIN_LENGTH,
        )

    if len(password) > PASSWORD_MAX_LENGTH:
        return "{} must be at most {} characters.".format(
            label, PASSWORD_MAX_LENGTH,
        )

    if not password.strip():
        return "{} cannot be only spaces.".format(label)

    if password.lower() in COMMON_PASSWORDS:
        return "{} is too common. Choose a less predictable one.".format(label)

    return None


def _looks_like_email(value):
    """Cheap structural check; ownership is proven by the emailed code."""
    if not value or len(value) > EMAIL_MAX_LENGTH or " " in value:
        return False
    local, sep, domain = value.rpartition("@")
    return bool(sep and local and "." in domain and not domain.startswith("."))


def _new_numeric_code():
    return "{:06d}".format(secrets.randbelow(1_000_000))


def _hash_reset_token(raw_token):
    return RESET_TOKEN_SHA256_PREFIX + hashlib.sha256(
        raw_token.encode("utf-8")
    ).hexdigest()


def _issue_verification_code(user, now=None):
    """Install a fresh verification code on ``user`` and return it.

    Only the hash is stored. Any previous code stops working.
    The caller commits and sends.
    """
    now = now or datetime.utcnow()
    code = _new_numeric_code()
    user.email_verification_code_hash = generate_password_hash(code)
    user.email_verification_expires_at = now + timedelta(
        minutes=VERIFY_CODE_LIFETIME_MINUTES
    )
    user.email_verification_attempts = 0
    user.email_verification_sent_at = now
    return code


def _clear_verification_fields(user):
    user.email_verification_code_hash = None
    user.email_verification_expires_at = None
    user.email_verification_attempts = 0


def _revoke_all_sessions(user_id, now=None):
    """Revoke every refresh token of ``user_id`` (no commit)."""
    UserRefreshToken.query.filter_by(
        user_id=user_id
    ).filter(
        UserRefreshToken.revoked_at.is_(None)
    ).update(
        {UserRefreshToken.revoked_at: now or datetime.utcnow()},
        synchronize_session=False,
    )


def email_unverified_response():
    """403 body shared by every route that requires a verified email."""
    return jsonify({
        "success": False,
        "error": EMAIL_UNVERIFIED_ERROR,
        "message": "Please verify your email address to continue.",
    }), 403


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

    if "turnstileToken" in safe:
        safe["turnstileToken"] = "[REDACTED]"

    if "website" in safe:
        # Honeypot: whatever a bot typed is not worth keeping in logs.
        safe["website"] = "[REDACTED]"

    if "code" in safe:
        safe["code"] = "[REDACTED]"

    if "email" in safe:
        safe["email"] = "[REDACTED]"

    return safe


def _user_response(user):
    """Return the public user representation."""

    return {
        "id": user.id,
        "name": user.name,
        "email": user.email,
        "emailVerified": bool(user.email_verified),
        "preferredLanguage": user.preferred_language,
        "preferredCurrency": user.preferred_currency,
        "authProvider": user.auth_provider,
        "createdAt": (
            user.created_at.isoformat()
            if user.created_at
            else None
        ),
    }


GENERIC_REFRESH_ERROR = (
    "Your session has expired. Please log in again."
)

# Raw refresh tokens are high-entropy random strings; only their SHA-256 hash
# is persisted. 64 random bytes give ~512 bits of entropy, far beyond any
# brute-force concern, so a fast hash (not a password hash) is appropriate.
REFRESH_TOKEN_BYTES = 64


# ============================================================
# HELPERS
# ============================================================

def _hash_refresh_token(raw_token):
    """Return the SHA-256 hex digest of a raw refresh token."""

    return hashlib.sha256(
        raw_token.encode("utf-8")
    ).hexdigest()


def _access_token_for(user):
    """Mint an access token for ``user``.

    The token carries the account's ``token_version`` in the ``ver`` claim so
    that bumping the version (password change / password reset) invalidates
    every token that was issued before the bump.
    """

    return create_access_token(
        identity=str(user.id),
        additional_claims={"ver": int(user.token_version or 1)},
    )


def _current_user_id():
    """Return the authenticated user's id as an int.

    The identity always comes from the verified JWT, never from the request
    body. A malformed identity (empty, non-numeric, negative) is treated as
    an invalid session rather than an internal error.
    """

    identity = get_jwt_identity()

    try:
        user_id = int(identity)
    except (TypeError, ValueError) as error:
        raise InvalidIdentityError(INVALID_SESSION_MESSAGE) from error

    if user_id <= 0:
        raise InvalidIdentityError(INVALID_SESSION_MESSAGE)

    return user_id


def _client_user_agent():
    """Return a (truncated) User-Agent string for the current request."""

    try:
        agent = request.headers.get("User-Agent") or ""
    except RuntimeError:
        agent = ""

    agent = agent.strip()

    return agent[:255] if agent else None


def _issue_refresh_token(user, family_id=None):
    """Mint, persist, and return a new raw refresh token for ``user``."""

    raw_token = secrets.token_urlsafe(REFRESH_TOKEN_BYTES)

    db.session.add(
        UserRefreshToken(
            user_id=user.id,
            token_hash=_hash_refresh_token(raw_token),
            family_id=family_id or uuid.uuid4().hex,
            expires_at=(
                datetime.utcnow()
                + timedelta(
                    days=Config.REFRESH_TOKEN_LIFETIME_DAYS
                )
            ),
            user_agent=_client_user_agent(),
        )
    )

    db.session.commit()

    return raw_token


def _revoke_refresh_family(family_id, when):
    """Revoke every still-active token in a rotation family."""

    UserRefreshToken.query.filter_by(
        family_id=family_id
    ).filter(
        UserRefreshToken.revoked_at.is_(None)
    ).update(
        {UserRefreshToken.revoked_at: when},
        synchronize_session=False,
    )


def _rotate_refresh_token(raw_token):
    """Rotate a refresh token and return ``(user, new_raw_token)``.

    Returns ``None`` when the presented token is missing, unknown, expired,
    or already revoked. Presenting an already-revoked token is treated as a
    replay of a stolen token: the entire family is revoked immediately.
    """

    if not raw_token or not isinstance(raw_token, str):
        return None

    now = datetime.utcnow()

    current = UserRefreshToken.query.filter_by(
        token_hash=_hash_refresh_token(raw_token)
    ).first()

    if current is None:
        return None

    # Replay of a rotated/revoked token -> assume theft, kill the family.
    if current.revoked_at is not None:
        _revoke_refresh_family(current.family_id, now)
        db.session.commit()
        return None

    if current.expires_at is not None and current.expires_at <= now:
        return None

    user = db.session.get(User, current.user_id)

    if user is None:
        return None

    raw_new = secrets.token_urlsafe(REFRESH_TOKEN_BYTES)
    new_hash = _hash_refresh_token(raw_new)

    # Consume the presented token atomically. Two concurrent refreshes with
    # the same token both pass the read above; only one may win this
    # conditional UPDATE. The loser is a replay of a consumed token, so the
    # whole family is revoked (same as presenting an old token later).
    consumed = db.session.execute(
        update(UserRefreshToken)
        .where(
            UserRefreshToken.id == current.id,
            UserRefreshToken.revoked_at.is_(None),
        )
        .values(
            revoked_at=now,
            last_used_at=now,
            replaced_by_hash=new_hash,
        )
        .execution_options(synchronize_session=False)
    )

    if consumed.rowcount != 1:
        db.session.rollback()
        _revoke_refresh_family(current.family_id, now)
        db.session.commit()
        return None

    db.session.add(
        UserRefreshToken(
            user_id=user.id,
            token_hash=new_hash,
            family_id=current.family_id,
            expires_at=(
                datetime.utcnow()
                + timedelta(
                    days=Config.REFRESH_TOKEN_LIFETIME_DAYS
                )
            ),
            user_agent=current.user_agent,
        )
    )

    db.session.commit()

    return user, raw_new


def _revoke_refresh_token(raw_token):
    """Revoke a single refresh token (used by logout). Best-effort."""

    if not raw_token or not isinstance(raw_token, str):
        return

    now = datetime.utcnow()

    row = UserRefreshToken.query.filter_by(
        token_hash=_hash_refresh_token(raw_token)
    ).first()

    if row is not None and row.revoked_at is None:
        row.revoked_at = now
        db.session.commit()


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

    # Bot protection (services/bot_protection.py). A filled honeypot gets the
    # normal generic answer and nothing else happens. The Turnstile token is
    # redeemed further down, after the cheap field checks, so a typo does not
    # burn the user's single-use token.
    if bot_protection.honeypot_triggered(data):
        logger.info("Register: honeypot triggered; request ignored.")
        return jsonify({
            "success": True,
            "message": GENERIC_REGISTER_MESSAGE,
            "verificationRequired": True,
        }), 201

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

    if len(name) > NAME_MAX_LENGTH:
        return jsonify({
            "success": False,
            "message": "Name must be at most 100 characters.",
        }), 400

    if not email:
        return jsonify({
            "success": False,
            "message": "Email cannot be empty.",
        }), 400

    if not _looks_like_email(email):
        return jsonify({
            "success": False,
            "message": "Email address is invalid.",
        }), 400

    password_error = _password_policy_error(password)

    if password_error:
        return jsonify({
            "success": False,
            "message": password_error,
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
    # BOT PROTECTION (before any database access)
    # --------------------------------------------------------

    bot_check = bot_protection.check(data, turnstile.ACTION_REGISTER)
    if not bot_check.passed:
        body, status = bot_protection.failure_response(bot_check)
        return jsonify(body), status

    # --------------------------------------------------------
    # DATABASE
    # --------------------------------------------------------

    # The response is identical whether the address is new, belongs to an
    # unverified account, or belongs to an existing verified account, so
    # registration cannot be used to discover who has an account. Every
    # branch pays for one password hash and one email.
    generic_response = (
        jsonify({
            "success": True,
            "message": GENERIC_REGISTER_MESSAGE,
            "verificationRequired": True,
        }),
        201,
    )

    try:

        now = datetime.utcnow()
        password_hash = generate_password_hash(password)

        existing_user = User.query.filter_by(
            email=email
        ).first()

        # ----------------------------------------------------
        # EXISTING, VERIFIED ACCOUNT -> notify the owner only
        # ----------------------------------------------------

        if existing_user is not None and existing_user.email_verified:
            last = existing_user.email_verification_sent_at
            if last is None or (now - last).total_seconds() >= (
                EXISTING_ACCOUNT_NOTICE_COOLDOWN_SECONDS
            ):
                existing_user.email_verification_sent_at = now
                db.session.commit()
                try:
                    send_existing_account_notice(existing_user.email)
                except Exception:
                    logger.error("Existing-account notice delivery failed.")
            else:
                db.session.rollback()
            logger.info("Register attempt for an existing account.")
            return generic_response

        # ----------------------------------------------------
        # NEW OR STILL-UNVERIFIED ACCOUNT
        # ----------------------------------------------------
        # An unverified account belongs to nobody yet: nobody has proven
        # control of the address. Re-registering replaces its credentials and
        # ends any session on it, so an attacker who pre-registered someone
        # else's address cannot keep a foothold. Only the person who can read
        # the inbox AND knows the current password can verify it (verification
        # requires a signed-in session).

        if existing_user is not None:
            user = existing_user
            user.name = name
            user.password_hash = password_hash
            user.preferred_language = preferred_language
            user.preferred_currency = preferred_currency
            user.token_version = int(user.token_version or 1) + 1
            _revoke_all_sessions(user.id, now)
        else:
            user = User(
                name=name,
                email=email,
                password_hash=password_hash,
                preferred_language=preferred_language,
                preferred_currency=preferred_currency,
                email_verified=False,
            )
            db.session.add(user)

        code = _issue_verification_code(user, now)
        db.session.commit()

        try:
            sent = bool(send_verification_code(user.email, code))
        except Exception:
            sent = False
        if not sent:
            # The account exists; the user can request a new code from the
            # verification screen once delivery works again.
            logger.error("Verification email delivery failed.")

        logger.info("User registered (unverified): %s", user.id)

        return generic_response

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

# ============================================================
# PER-ACCOUNT LOGIN THROTTLE (F3)
# ============================================================
#
# A second rate-limit bucket, independent of the per-IP auth limit enforced in
# app.before_request. It bounds login attempts for one account across every
# source IP, so distributed credential stuffing cannot be masked by rotating
# IPs. Properties:
#   * Atomic gate. Enforced with limiter.check() (atomic increment-and-compare,
#     the same primitive as the per-IP limiter), so a simultaneous distributed
#     burst cannot slip past: at most `limit` attempts per window are admitted,
#     the rest are refused BEFORE any password hash. A read-then-write gate
#     would let a cold-start burst bypass the limit entirely; this does not.
#   * Checked before verification, so a tripped account refuses even a correct
#     password (stops a stuffing run from winning on the attempt that guesses
#     right).
#   * Reset on success. A successful login clears the counter, so legitimate
#     use is never penalised -- the effective metric is consecutive failed
#     attempts, bounded also by the fixed window.
#   * Keyed on the normalized e-mail's keyed HMAC, never the raw address, and
#     applied whether or not an account exists, so a blocked response is
#     identical for registered and unknown addresses and never reveals which.
#   * Fails CLOSED on an unexpected limiter error (rejects rather than silently
#     admitting an unthrottled attempt); the designed Redis-outage fallback
#     (per-process counting) still keeps login available.
# See config.settings (RATE_LIMIT_LOGIN_ACCOUNT_*) and services.rate_limiter.

ACCOUNT_LOGIN_BUCKET = "auth.login_account"


def _account_login_key(normalized_email):
    """Return the HMAC-keyed rate-limit identifier for an e-mail.

    Only the keyed HMAC-SHA256 digest of the normalized e-mail is ever used as
    a rate-limit key (or logged); the raw address is not. The digest is
    domain-separated with a fixed label so it cannot collide with any other
    HMAC use of the same server secret.
    """
    secret = Config.login_rate_limit_hmac_key()
    message = ("login-throttle:v1:" + normalized_email).encode("utf-8")
    return hmac.new(secret, message, hashlib.sha256).hexdigest()


def _account_login_throttled_response(exc):
    """Build the generic 429 returned when an account's login budget is spent.

    Deliberately identical in shape and wording to the global per-IP 429
    (app.enforce_rate_limits), so a throttled account is not distinguishable
    from ordinary IP throttling and account existence is never revealed.
    """
    resp = jsonify({
        "success": False,
        "message": "Rate limit exceeded. Please try again later.",
    })
    resp.status_code = 429

    reset_at = getattr(exc, "reset_at", None)
    limit = getattr(exc, "limit", None)
    if reset_at is not None:
        resp.headers["Retry-After"] = str(max(0, int(reset_at) - int(time.time())))
        resp.headers["X-RateLimit-Reset"] = str(int(reset_at))
    if limit is not None:
        resp.headers["X-RateLimit-Limit"] = str(limit)
        resp.headers["X-RateLimit-Remaining"] = "0"
    return resp


def _login_throttle_unavailable_response():
    """Fail-closed 503 for a limiter error that is neither a hit nor an outage.

    Matches the global limiter's ``closed``-mode response. Returned when the
    per-account gate raises unexpectedly, so a limiter fault can never become a
    silent fail-open path that disables brute-force protection.
    """
    resp = jsonify({
        "success": False,
        "message": "Service temporarily unavailable. Please try again.",
    })
    resp.status_code = 503
    resp.headers["Retry-After"] = "30"
    return resp


def enforce_account_login_throttle(normalized_email):
    """Count one password attempt against the account; refuse when over.

    Shared by every endpoint that verifies an account password
    (``/api/auth/login`` and ``/api/admin/auth/login``), so both draw from the
    SAME per-account counter: failures on one count towards the other, and
    neither can be used to keep guessing once the account's budget is spent.
    Call it before any user lookup or password hash, for every address
    (registered or not), so the response never reveals account existence.

    Returns ``None`` when the attempt may proceed, otherwise the Flask
    response to return (generic 429, or a fail-closed 503).
    """
    account_key = _account_login_key(normalized_email)
    try:
        limiter.check(ACCOUNT_LOGIN_BUCKET, account_key)
    except RateLimitExceeded as exc:
        return _account_login_throttled_response(exc)
    except RateLimitUnavailable:
        logger.warning("Per-account login throttle unavailable (closed mode)")
        return _login_throttle_unavailable_response()
    except Exception:  # noqa: BLE001 - fail closed on an unexpected limiter error
        logger.exception(
            "Per-account login throttle failed; rejecting attempt (fail-closed)"
        )
        return _login_throttle_unavailable_response()
    return None


def clear_account_login_throttle(normalized_email):
    """Clear the account's counter after the user proved control of it.

    Called only after a verified password (login, admin password step) or a
    completed, committed password reset. Best-effort: never raises.
    """
    limiter.reset_key(
        ACCOUNT_LOGIN_BUCKET, _account_login_key(normalized_email)
    )


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

    # ----------------------------------------------------
    # PER-ACCOUNT THROTTLE GATE (atomic; before verification)
    # ----------------------------------------------------
    # One atomic increment-and-compare per attempt, keyed on the e-mail's HMAC.
    # Admits at most `limit` attempts per window regardless of how many source
    # IPs fire simultaneously, and refuses them before any password hash. A
    # successful login resets the counter (below), so legitimate use is never
    # penalised. An unexpected limiter error fails CLOSED.
    throttled = enforce_account_login_throttle(email)
    if throttled is not None:
        return throttled

    try:

        user = User.query.filter_by(
            email=email
        ).first()

        # ----------------------------------------------------
        # PASSWORD
        # ----------------------------------------------------
        # Unknown emails and social-only accounts (no password) get the
        # same response as a wrong password, and still pay for one hash
        # check, so neither the message nor the timing reveals whether an
        # account exists or how it signs in.

        stored_hash = (
            user.password_hash
            if user is not None and user.password_hash
            else None
        )

        password_ok = check_password_hash(
            stored_hash or _DUMMY_PASSWORD_HASH,
            password,
        )

        if stored_hash is None or not password_ok:
            # The attempt was already counted atomically by the gate above, so
            # nothing to do here but return the generic error.
            return jsonify({
                "success": False,
                "message": INVALID_LOGIN_MESSAGE,
            }), 401

        # Authentication succeeded: clear the account's failed-attempt budget
        # so a legitimate login is never penalised by earlier failures.
        clear_account_login_throttle(email)

        # ----------------------------------------------------
        # JWT
        # ----------------------------------------------------

        access_token = _access_token_for(user)

        refresh_token = _issue_refresh_token(user)

        logger.info(
            "Login successful for user: %s",
            user.id,
        )

        return jsonify({
            "success": True,
            "message": "Login successful.",
            "accessToken": access_token,
            "refreshToken": refresh_token,
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
        # Never merge a provider identity into an account it did not create.
        # Registration does not prove control of the email address, so an
        # attacker could pre-register the victim's address with a password
        # and wait for the victim to "Sign in with Google" into it
        # (pre-account-takeover). The legitimate owner of a password account
        # keeps using the password (or recovers it by email reset).
        raise SocialAccountConflictError(
            "Social identity for user {} not linked: email already "
            "registered with provider={}".format(
                user.id,
                user.auth_provider or "password",
            )
        )

    user = User(
        name=(
            (name if name else email.split("@")[0])[:100]
        ),
        email=email,
        password_hash=None,
        email_verified=True,
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
        # Library error text (clock values, audiences, key ids) stays in the
        # server log; the client gets a stable generic message.
        return {
            "success": False,
            "message": "Could not verify your %s sign-in. Please try again."
            % provider.capitalize(),
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

    email_verified = claims.get("email_verified") is True

    if not email_verified:
        # An unverified provider email proves nothing about who owns the
        # address, so it can never be used to create or enter an account.
        return {
            "success": False,
            "message": (
                "Your %s email address is not verified."
                % provider.capitalize()
            ),
        }, 403

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

    access_token = _access_token_for(user)

    refresh_token = _issue_refresh_token(user)

    logger.info(
        "Social login successful for user: %s",
        user.id,
    )

    return {
        "success": True,
        "message": "Login successful.",
        "accessToken": access_token,
        "refreshToken": refresh_token,
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
# REFRESH ACCESS TOKEN
# POST /api/auth/refresh
# ============================================================
#
# Exchanges a valid refresh token for a fresh access token (and a rotated
# refresh token). Called silently by the client when an access token expires,
# so the user stays signed in without re-entering credentials.

@auth_bp.route("/refresh", methods=["POST"])
def refresh():

    data = request.get_json(silent=True) or {}

    raw_token = data.get("refreshToken")

    if not raw_token:
        return jsonify({
            "success": False,
            "message": "Refresh token is required.",
        }), 400

    result = _rotate_refresh_token(raw_token)

    if result is None:
        return jsonify({
            "success": False,
            "message": GENERIC_REFRESH_ERROR,
        }), 401

    user, new_refresh_token = result

    access_token = _access_token_for(user)

    logger.info(
        "Access token refreshed for user: %s",
        user.id,
    )

    return jsonify({
        "success": True,
        "accessToken": access_token,
        "refreshToken": new_refresh_token,
        "user": _user_response(user),
    }), 200


# ============================================================
# LOGOUT
# POST /api/auth/logout
# ============================================================
#
# Revokes the presented refresh token server-side so it can never be renewed
# again. Always returns success (idempotent, and never reveals whether the
# token existed). Short-lived access tokens simply expire.

@auth_bp.route("/logout", methods=["POST"])
def logout():

    data = request.get_json(silent=True) or {}

    _revoke_refresh_token(data.get("refreshToken"))

    return jsonify({
        "success": True,
        "message": "Logged out.",
    }), 200


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

def _reset_fields_cleared_values():
    """Column values that remove every password-reset credential.

    Returned as a plain mapping so the transition can be applied with a single
    atomic ``UPDATE`` instead of an unguarded read/modify/write on an ORM row.
    """
    return {
        "reset_code_hash": None,
        "reset_code_expires_at": None,
        "reset_attempts": 0,
        "reset_token_hash": None,
        "reset_token_expires_at": None,
    }


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

    # Bot protection (services/bot_protection.py), before any lookup. A filled
    # honeypot gets the same generic answer as every other outcome. A failed
    # challenge is a 400/503 that is independent of the address, so it does
    # not reveal whether an account exists.
    if bot_protection.honeypot_triggered(data):
        logger.info("Forgot-password: honeypot triggered; request ignored.")
        return jsonify({
            "success": True,
            "message": GENERIC_RESET_MESSAGE,
        }), 200

    bot_check = bot_protection.check(data, turnstile.ACTION_FORGOT_PASSWORD)
    if not bot_check.passed:
        body, status = bot_protection.failure_response(bot_check)
        return jsonify(body), status

    email = str(email).strip().lower()

    try:
        user = User.query.filter_by(email=email).first()
    except Exception:
        # Do not log the lookup exception: database errors can contain the
        # submitted recipient address and other sensitive query details.
        logger.error("Forgot-password lookup failed.")
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

    # Capture what the remaining phases need, then end the read-only lookup
    # transaction.  Every transition below is a single conditional UPDATE
    # evaluated against the latest committed row, so a concurrent request can
    # never write back a stale object and resurrect an old code or token.
    user_id = user.id
    recipient = user.email
    observed_password_hash = user.password_hash
    db.session.rollback()

    # ------------------------------------------------------------------
    # Phase 1: invalidate every previously issued recovery credential and
    # commit that transition independently, before any email is sent.
    #
    # If this commit fails we do not attempt delivery.  Sending a code whose
    # hash could not be persisted would only leave the user with a useless
    # code, and leaving the old credential active while a new request is in
    # flight would defeat rotation.  The public response stays generic.
    # ------------------------------------------------------------------
    try:
        result = db.session.execute(
            update(User)
            .where(
                User.id == user_id,
                User.password_hash.isnot(None),
            )
            .values(**_reset_fields_cleared_values())
            .execution_options(synchronize_session=False)
        )
        if result.rowcount != 1:
            db.session.rollback()
            logger.error("Password reset credential invalidation failed.")
            return jsonify({
                "success": True,
                "message": GENERIC_RESET_MESSAGE,
            }), 200
        db.session.commit()
    except Exception:
        db.session.rollback()
        logger.error("Password reset credential invalidation failed.")
        return jsonify({
            "success": True,
            "message": GENERIC_RESET_MESSAGE,
        }), 200

    # ------------------------------------------------------------------
    # Phase 2: attempt delivery.  Only the cleared state is committed while
    # the email is in flight, so a delivery failure cannot resurrect the old
    # code or reset token.
    # ------------------------------------------------------------------
    try:
        sent = bool(send_password_reset_code(recipient, code))
    except Exception:
        # Never log provider exceptions: they can contain the recipient,
        # the message body, or the reset code.
        logger.error("Password reset delivery failed.")
        sent = False

    if not sent:
        logger.warning("Password reset delivery unavailable.")
        return jsonify({
            "success": True,
            "message": GENERIC_RESET_MESSAGE,
        }), 200

    # ------------------------------------------------------------------
    # Phase 3: persist the new code hash only after delivery succeeded.
    #
    # The conditional UPDATE installs the code only when the password has not
    # changed and no newer code has already been installed.  It also clears
    # any reset token a concurrent verification may have minted: a new reset
    # request invalidates every earlier recovery credential.
    #
    # If this update fails, rollback restores the cleared state committed in
    # phase 1 (not the previous credential), so the emailed code is unusable
    # and the old code/token remain invalid.
    # ------------------------------------------------------------------
    try:
        result = db.session.execute(
            update(User)
            .where(
                User.id == user_id,
                User.password_hash == observed_password_hash,
                User.reset_code_hash.is_(None),
            )
            .values(
                reset_code_hash=generate_password_hash(code),
                reset_code_expires_at=(
                    datetime.utcnow()
                    + timedelta(minutes=RESET_CODE_LIFETIME_MINUTES)
                ),
                reset_attempts=0,
                reset_token_hash=None,
                reset_token_expires_at=None,
            )
            .execution_options(synchronize_session=False)
        )
        if result.rowcount != 1:
            db.session.rollback()
            logger.error("Password reset recovery state was not persisted.")
        else:
            db.session.commit()
            logger.info("Password reset delivery succeeded.")
    except Exception:
        db.session.rollback()
        logger.error("Password reset recovery state was not persisted.")

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
        # Avoid logging query exceptions that may contain the recipient.
        logger.error("Reset-code verification lookup failed.")
        user = None

    if user is None:
        return jsonify({
            "success": False,
            "message": INVALID_RESET_CODE_MESSAGE,
        }), 400

    now = datetime.utcnow()

    # Snapshot the fields used for the decision.  ``reset_code_hash`` also acts
    # as the optimistic concurrency token for the conditional UPDATEs below.
    user_id = user.id
    observed_hash = user.reset_code_hash
    observed_expiry = user.reset_code_expires_at
    observed_attempts = user.reset_attempts or 0

    code_valid = (
        observed_hash is not None
        and observed_expiry is not None
        and observed_expiry > now
        and observed_attempts < RESET_MAX_ATTEMPTS
    )

    if not code_valid:
        return jsonify({
            "success": False,
            "message": INVALID_RESET_CODE_MESSAGE,
        }), 400

    # The hash check runs outside a database transaction; the conditional
    # UPDATE is the authority on whether the checked code is still current.
    # Closing the read transaction also lets SQLite upgrade to a write
    # transaction without a stale-snapshot error.
    db.session.rollback()

    if not check_password_hash(observed_hash, code):
        # Re-read the clock after hashing: the comparison deliberately takes
        # time, and the conditional statements must judge expiry at execution
        # time, not at the time the request was read.
        now = datetime.utcnow()

        # Atomic increment: one concurrent failure consumes exactly one
        # attempt, so a parallel brute force cannot exceed the lockout budget
        # through lost updates.
        result = db.session.execute(
            update(User)
            .where(
                User.id == user_id,
                User.reset_code_hash == observed_hash,
                User.reset_code_expires_at.isnot(None),
                User.reset_code_expires_at > now,
                func.coalesce(User.reset_attempts, 0) < RESET_MAX_ATTEMPTS,
            )
            .values(
                reset_attempts=func.coalesce(User.reset_attempts, 0) + 1,
            )
            .execution_options(synchronize_session=False)
        )

        if result.rowcount != 1:
            # A concurrent request rotated/consumed the code or locked the
            # account between our read and this update.
            db.session.rollback()
            return jsonify({
                "success": False,
                "message": INVALID_RESET_CODE_MESSAGE,
            }), 400

        db.session.commit()

        # Clear the code once the final allowed attempt has been recorded.
        # Doing this as its own atomic statement means a concurrent rotation
        # cannot be clobbered by a stale in-memory object.
        locked = db.session.execute(
            update(User)
            .where(
                User.id == user_id,
                func.coalesce(User.reset_attempts, 0) >= RESET_MAX_ATTEMPTS,
            )
            .values(**_reset_fields_cleared_values())
            .execution_options(synchronize_session=False)
        )
        db.session.commit()

        if locked.rowcount == 1:
            logger.warning(
                "Password reset locked out after failed attempts: %s",
                user_id,
            )

        return jsonify({
            "success": False,
            "message": INVALID_RESET_CODE_MESSAGE,
        }), 400

    # Code verified -> consume the code and issue the one-time reset token in
    # one conditional UPDATE.  Only the request whose observed hash is still
    # current can install a token, so a code can never mint two tokens even
    # when the verification requests race.
    now = datetime.utcnow()
    reset_token = secrets.token_urlsafe(32)

    result = db.session.execute(
        update(User)
        .where(
            User.id == user_id,
            User.reset_code_hash == observed_hash,
            User.reset_code_expires_at.isnot(None),
            User.reset_code_expires_at > now,
            func.coalesce(User.reset_attempts, 0) < RESET_MAX_ATTEMPTS,
        )
        .values(
            reset_code_hash=None,
            reset_code_expires_at=None,
            reset_attempts=0,
            reset_token_hash=_hash_reset_token(reset_token),
            reset_token_expires_at=(
                now + timedelta(minutes=RESET_TOKEN_LIFETIME_MINUTES)
            ),
        )
        .execution_options(synchronize_session=False)
    )

    if result.rowcount != 1:
        db.session.rollback()
        return jsonify({
            "success": False,
            "message": INVALID_RESET_CODE_MESSAGE,
        }), 400

    db.session.commit()

    logger.info("Password reset code verified for user: %s", user_id)

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

    password_error = _password_policy_error(password, label="New password")

    if password_error:
        return jsonify({
            "success": False,
            "message": password_error,
        }), 400

    now = datetime.utcnow()

    try:
        # Current tokens: indexed lookup by SHA-256 (the token is 256-bit
        # random, so a fast hash is safe). Legacy tokens issued before this
        # change were stored with a password hash and are matched by a scan
        # limited to those rows, until they expire.
        candidates = User.query.filter(
            User.reset_token_hash == _hash_reset_token(str(reset_token))
        ).all()

        legacy = User.query.filter(
            User.reset_token_hash.isnot(None),
            ~User.reset_token_hash.startswith(RESET_TOKEN_SHA256_PREFIX),
            User.reset_token_expires_at > now,
        ).limit(50).all()

        user = None
        observed_token_hash = None
        for candidate in candidates + legacy:
            if candidate.reset_token_hash.startswith(
                RESET_TOKEN_SHA256_PREFIX
            ):
                matches = candidate.reset_token_hash == _hash_reset_token(
                    str(reset_token)
                )
            else:
                matches = check_password_hash(
                    candidate.reset_token_hash,
                    str(reset_token),
                )
            if (
                matches
                and candidate.password_hash is not None
                and candidate.reset_token_expires_at is not None
                and candidate.reset_token_expires_at > now
            ):
                user = candidate
                observed_token_hash = candidate.reset_token_hash
                break

        if user is None:
            return jsonify({
                "success": False,
                "message": INVALID_RESET_TOKEN_MESSAGE,
            }), 400

        # Capture the values needed by the conditional UPDATE, then end the
        # read-only scan transaction.  The UPDATE re-checks the token, its
        # expiry, and the old password hash, so a token that was consumed or
        # invalidated by a concurrent request cannot still change the password.
        user_id = user.id
        observed_password_hash = user.password_hash
        account_email = str(user.email or "").strip().lower()
        db.session.rollback()

        if check_password_hash(observed_password_hash, password):
            return jsonify({
                "success": False,
                "message": "New password must be different from your old password."
            }), 400

        new_password_hash = generate_password_hash(password)

        # Judge token expiry at execution time, after the slow password hash.
        now = datetime.utcnow()

        result = db.session.execute(
            update(User)
            .where(
                User.id == user_id,
                User.reset_token_hash == observed_token_hash,
                User.reset_token_expires_at.isnot(None),
                User.reset_token_expires_at > now,
                User.password_hash == observed_password_hash,
            )
            .values(
                password_hash=new_password_hash,
                token_version=func.coalesce(User.token_version, 1) + 1,
                email_verified=True,
                email_verification_code_hash=None,
                email_verification_expires_at=None,
                email_verification_attempts=0,
                **_reset_fields_cleared_values(),
            )
            .execution_options(synchronize_session=False)
        )

        if result.rowcount != 1:
            # The token was already used, expired, or rotated, or the password
            # changed between the scan and this update.
            db.session.rollback()
            return jsonify({
                "success": False,
                "message": INVALID_RESET_TOKEN_MESSAGE,
            }), 400

        # A password reset ends every session that was started with the old
        # credentials (access tokens are invalidated by the token_version bump
        # above; stored refresh tokens are revoked in the same transaction).
        UserRefreshToken.query.filter_by(
            user_id=user_id
        ).filter(
            UserRefreshToken.revoked_at.is_(None)
        ).update(
            {UserRefreshToken.revoked_at: now},
            synchronize_session=False,
        )

        db.session.commit()

        # L1: the reset is committed, so the user has proven control of the
        # account's mailbox. Lift a lockout an attacker may have imposed with
        # failed logins. Only this account's counter; only after success.
        if account_email:
            clear_account_login_throttle(account_email)

        logger.info("Password reset completed for user: %s", user_id)

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

        user_id = _current_user_id()

        user = db.session.get(
            User,
            user_id,
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

    except InvalidIdentityError:

        return jsonify({
            "success": False,
            "message": INVALID_SESSION_MESSAGE,
        }), 401

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

        user_id = _current_user_id()

        user = db.session.get(
            User,
            user_id,
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

                if len(clean_email) > 255 or "@" not in clean_email:
                    return jsonify({
                        "success": False,
                        "message": "Email address is invalid.",
                    }), 400

                if not user.email_verified:
                    return jsonify({
                        "success": False,
                        "message": (
                            "Verify your current email before changing it."
                        ),
                    }), 403

                # The login email is the account-recovery channel: changing
                # it with nothing but a (possibly stolen) access token would
                # let an attacker redirect password resets to themselves.
                if not user.password_hash:
                    return jsonify({
                        "success": False,
                        "message": (
                            "The email of a social sign-in account "
                            "is managed by its provider."
                        ),
                    }), 400

                if current_password is None or not check_password_hash(
                    user.password_hash,
                    str(current_password),
                ):
                    return jsonify({
                        "success": False,
                        "message": (
                            "Enter your current password to "
                            "change your email."
                        ),
                    }), 401

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

            password_error = _password_policy_error(
                password_value,
                label="New password",
            )

            if password_error:

                return jsonify({
                    "success": False,
                    "message": password_error,
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

            # Changing the password ends every other session that was
            # started with the old credentials: the access tokens are
            # invalidated by bumping the token version, and the stored
            # refresh tokens are revoked so they cannot mint new ones.
            user.token_version = int(user.token_version or 1) + 1
            UserRefreshToken.query.filter_by(
                user_id=user.id
            ).filter(
                UserRefreshToken.revoked_at.is_(None)
            ).update(
                {UserRefreshToken.revoked_at: datetime.utcnow()},
                synchronize_session=False,
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

    except InvalidIdentityError:

        db.session.rollback()

        return jsonify({
            "success": False,
            "message": INVALID_SESSION_MESSAGE,
        }), 401

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
    """Permanently delete the account after re-authentication.

    Password accounts must send ``currentPassword``. Social-only accounts must
    send a FRESH provider token (``idToken``, plus ``nonce`` for Apple) for the
    same provider identity, issued within the last 10 minutes. A valid access
    token alone is not enough: it may be stolen or left on a shared device.

    Everything the user owns is removed in ONE transaction, children first,
    so the result never depends on database-level cascades.
    """

    try:

        user_id = _current_user_id()

        user = db.session.get(User, user_id)

        if user is None:
            return jsonify({
                "success": False,
                "message": "User not found.",
            }), 404

        data = request.get_json(silent=True) or {}

        # ------------------------------------------------------
        # RE-AUTHENTICATION
        # ------------------------------------------------------

        if user.password_hash:
            current_password = data.get("currentPassword")
            if not isinstance(current_password, str) or not current_password:
                return jsonify({
                    "success": False,
                    "error": "reauth_required",
                    "message": (
                        "Enter your password to delete your account."
                    ),
                }), 400
            if not check_password_hash(user.password_hash, current_password):
                return jsonify({
                    "success": False,
                    "error": "reauth_failed",
                    "message": "Your password is incorrect.",
                }), 401
        else:
            reauth_error = _verify_social_reauth(user, data)
            if reauth_error is not None:
                return reauth_error

        # ------------------------------------------------------
        # DELETE OWNED DATA (children first, one transaction)
        # ------------------------------------------------------

        trip_ids = [
            trip_id
            for (trip_id,) in db.session.query(Trip.id)
            .filter_by(user_id=user.id)
            .all()
        ]

        Expense.query.filter_by(user_id=user.id).delete(
            synchronize_session=False
        )

        if trip_ids:
            Expense.query.filter(
                Expense.trip_id.in_(trip_ids)
            ).delete(synchronize_session=False)

            # Weather cache rows are keyed by trip id (no FK).
            WeatherCache.query.filter(
                WeatherCache.trip_id.in_(trip_ids)
            ).delete(synchronize_session=False)

        Trip.query.filter_by(user_id=user.id).delete(
            synchronize_session=False
        )

        ActivityLog.query.filter_by(user_id=user.id).delete(
            synchronize_session=False
        )

        # Sessions and credentials. Admin audit rows keep a NULL actor
        # (ON DELETE SET NULL) so the security trail survives.
        UserRefreshToken.query.filter_by(user_id=user.id).delete(
            synchronize_session=False
        )
        AdminSession.query.filter_by(user_id=user.id).delete(
            synchronize_session=False
        )
        AdminRecoveryCode.query.filter_by(user_id=user.id).delete(
            synchronize_session=False
        )
        AdminMfa.query.filter_by(user_id=user.id).delete(
            synchronize_session=False
        )

        deleted_id = user.id
        db.session.delete(user)
        db.session.commit()

        logger.info("Account deleted: %s", deleted_id)

        return jsonify({
            "success": True,
            "message": "Account deleted successfully.",
        }), 200

    except InvalidIdentityError:

        db.session.rollback()

        return jsonify({
            "success": False,
            "message": INVALID_SESSION_MESSAGE,
        }), 401

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


def _verify_social_reauth(user, data):
    """Return an error response, or None when the fresh provider token is OK."""

    provider = (user.auth_provider or "").strip().lower()
    id_token_value = data.get("idToken")

    if provider not in {"google", "apple"} or not id_token_value:
        return jsonify({
            "success": False,
            "error": "reauth_required",
            "message": (
                "Sign in with your provider again to delete your account."
            ),
        }), 400

    try:
        claims = verify_identity_token(
            provider,
            id_token_value,
            nonce=data.get("nonce"),
        )
    except Exception as error:
        logger.warning("Delete re-authentication failed (%s): %s",
                       provider, error)
        claims = None

    issued_at = (claims or {}).get("iat")
    try:
        age = datetime.utcnow().timestamp() - float(issued_at)
    except (TypeError, ValueError):
        age = None

    if (
        claims is None
        or str(claims.get("provider_id") or "") != str(user.provider_id or "")
        or age is None
        or age > SOCIAL_REAUTH_MAX_AGE_SECONDS
    ):
        return jsonify({
            "success": False,
            "error": "reauth_failed",
            "message": (
                "We could not confirm your identity. "
                "Sign in with your provider again."
            ),
        }), 401

    return None


# ============================================================
# EMAIL VERIFICATION
# ============================================================
#
#   POST /api/auth/verify-email          {code}   (signed in)
#   POST /api/auth/verify-email/resend   {}       (signed in)
#
# Both require a signed-in session, so the person verifying must know the
# account password AND read the inbox. That also means neither endpoint can
# be used to probe which addresses are registered.

@auth_bp.route("/verify-email", methods=["POST"])
@jwt_required()
def verify_email():

    try:
        user_id = _current_user_id()
    except InvalidIdentityError:
        return jsonify({"success": False, "message": INVALID_SESSION_MESSAGE}), 401

    data = request.get_json(silent=True) or {}
    code = str(data.get("code") or "").strip()

    if not code.isdigit() or len(code) != 6:
        return jsonify({
            "success": False,
            "message": INVALID_VERIFY_CODE_MESSAGE,
        }), 400

    user = db.session.get(User, user_id)

    if user is None:
        return jsonify({"success": False, "message": "User not found."}), 404

    if user.email_verified:
        return jsonify({
            "success": True,
            "alreadyVerified": True,
            "message": "Your email is already verified.",
            "user": _user_response(user),
        }), 200

    now = datetime.utcnow()
    observed_hash = user.email_verification_code_hash
    observed_expiry = user.email_verification_expires_at
    attempts = user.email_verification_attempts or 0

    if (
        observed_hash is None
        or observed_expiry is None
        or observed_expiry <= now
        or attempts >= VERIFY_MAX_ATTEMPTS
    ):
        return jsonify({
            "success": False,
            "error": "code_expired",
            "message": (
                "This code has expired. Request a new one."
            ),
        }), 400

    db.session.rollback()

    if not check_password_hash(observed_hash, code):
        # Atomic increment guarded by the observed hash: parallel guesses
        # cannot exceed the attempt budget, and a rotated code is untouched.
        db.session.execute(
            update(User)
            .where(
                User.id == user_id,
                User.email_verification_code_hash == observed_hash,
                func.coalesce(User.email_verification_attempts, 0)
                < VERIFY_MAX_ATTEMPTS,
            )
            .values(
                email_verification_attempts=func.coalesce(
                    User.email_verification_attempts, 0
                ) + 1,
            )
            .execution_options(synchronize_session=False)
        )
        db.session.commit()
        return jsonify({
            "success": False,
            "message": INVALID_VERIFY_CODE_MESSAGE,
        }), 400

    # Single use: only the request that still sees the same code wins.
    result = db.session.execute(
        update(User)
        .where(
            User.id == user_id,
            User.email_verification_code_hash == observed_hash,
            User.email_verification_expires_at > datetime.utcnow(),
            func.coalesce(User.email_verification_attempts, 0)
            < VERIFY_MAX_ATTEMPTS,
        )
        .values(
            email_verified=True,
            email_verification_code_hash=None,
            email_verification_expires_at=None,
            email_verification_attempts=0,
        )
        .execution_options(synchronize_session=False)
    )

    if result.rowcount != 1:
        db.session.rollback()
        return jsonify({
            "success": False,
            "message": INVALID_VERIFY_CODE_MESSAGE,
        }), 400

    db.session.commit()

    user = db.session.get(User, user_id)
    db.session.refresh(user)

    logger.info("Email verified for user: %s", user_id)

    return jsonify({
        "success": True,
        "message": "Your email is verified.",
        "user": _user_response(user),
    }), 200


@auth_bp.route("/verify-email/resend", methods=["POST"])
@jwt_required()
def resend_verification_email():

    try:
        user_id = _current_user_id()
    except InvalidIdentityError:
        return jsonify({"success": False, "message": INVALID_SESSION_MESSAGE}), 401

    user = db.session.get(User, user_id)

    if user is None:
        return jsonify({"success": False, "message": "User not found."}), 404

    if user.email_verified:
        return jsonify({
            "success": True,
            "alreadyVerified": True,
            "message": "Your email is already verified.",
        }), 200

    now = datetime.utcnow()
    last = user.email_verification_sent_at

    if last is not None:
        wait = VERIFY_RESEND_COOLDOWN_SECONDS - (now - last).total_seconds()
        if wait > 0:
            resp = jsonify({
                "success": False,
                "error": "resend_cooldown",
                "retryAfter": int(wait) + 1,
                "message": "Please wait a moment before requesting a new code.",
            })
            resp.headers["Retry-After"] = str(int(wait) + 1)
            return resp, 429

    code = _issue_verification_code(user, now)
    db.session.commit()

    try:
        sent = bool(send_verification_code(user.email, code))
    except Exception:
        sent = False

    if not sent:
        logger.error("Verification email delivery failed.")
        return jsonify({
            "success": False,
            "message": (
                "We could not send the email right now. "
                "Please try again later."
            ),
        }), 503

    return jsonify({
        "success": True,
        "message": "A new verification code has been sent.",
    }), 200
