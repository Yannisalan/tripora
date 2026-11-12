"""Administrator authentication: password + mandatory TOTP, server sessions.

Flow (see routes/admin_auth.py):

1. ``POST /api/admin/auth/login`` with email + password of a user whose
   ``role`` is ``admin`` (granted only via the ``flask admin grant`` CLI).
   Returns a short-lived *pending* token. It can do nothing except complete
   the second factor.
2. First login only: ``/mfa/setup`` returns a new TOTP secret, and
   ``/mfa/activate`` confirms it with a code and returns one-time recovery
   codes. Enrollment is allowed only inside the window opened by
   ``flask admin grant`` / ``flask admin reset-mfa``, so a leaked password
   alone cannot enroll an attacker's authenticator later.
3. Later logins: ``/mfa/verify`` with a TOTP code or a recovery code.
4. Success rotates the token (the pending token dies) and returns an
   *active* admin session token: opaque, 256-bit, only its SHA-256 stored,
   idle timeout + absolute lifetime, revocable, bound to the user's
   ``token_version`` (a password change/reset ends it).

TOTP is RFC 6238 (SHA-1, 6 digits, 30 s) implemented with the standard
library. Codes are accepted for the current step +/- 1, and a step is never
accepted twice (replay protection via ``admin_mfa.last_used_step``).
TOTP secrets are encrypted at rest with Fernet (``MFA_ENCRYPTION_KEY``).
"""

import base64
import hashlib
import hmac
import logging
import os
import secrets
import struct
import time
from datetime import datetime, timedelta
from urllib.parse import quote

from config.database import db
from models.admin_security import (
    ADMIN_SESSION_ACTIVE,
    ADMIN_SESSION_PENDING_MFA,
    AdminAuditLog,
    AdminMfa,
    AdminRecoveryCode,
    AdminSession,
)
from models.user import ROLE_ADMIN, User

logger = logging.getLogger(__name__)

TOTP_STEP_SECONDS = 30
TOTP_DIGITS = 6
TOTP_DRIFT_STEPS = 1
TOTP_ISSUER = "Tripora Admin"

PENDING_SESSION_MINUTES = 5
MAX_MFA_ATTEMPTS = 5
ENROLLMENT_WINDOW_HOURS = 24
RECOVERY_CODE_COUNT = 10


class AdminAuthUnavailable(RuntimeError):
    """MFA cannot work because MFA_ENCRYPTION_KEY is missing or invalid."""


# ============================================================
# CONFIG
# ============================================================

def session_idle_minutes():
    return _int_env("ADMIN_SESSION_IDLE_MINUTES", 30, 5, 240)


def session_max_hours():
    return _int_env("ADMIN_SESSION_MAX_HOURS", 8, 1, 24)


def _int_env(name, default, low, high):
    try:
        value = int(os.getenv(name, str(default)))
    except ValueError:
        return default
    return max(low, min(high, value))


def _fernet():
    key = os.getenv("MFA_ENCRYPTION_KEY", "").strip()
    if not key:
        raise AdminAuthUnavailable("MFA_ENCRYPTION_KEY is not configured.")
    from cryptography.fernet import Fernet

    try:
        return Fernet(key.encode("ascii"))
    except Exception as error:
        raise AdminAuthUnavailable("MFA_ENCRYPTION_KEY is invalid.") from error


def mfa_available():
    try:
        _fernet()
        return True
    except AdminAuthUnavailable:
        return False


# ============================================================
# TOTP (RFC 6238)
# ============================================================

def new_totp_secret():
    return base64.b32encode(secrets.token_bytes(20)).decode("ascii")


def _hotp(secret_b32, counter):
    key = base64.b32decode(secret_b32, casefold=True)
    digest = hmac.new(key, struct.pack(">Q", counter), hashlib.sha1).digest()
    offset = digest[-1] & 0x0F
    value = struct.unpack(">I", digest[offset:offset + 4])[0] & 0x7FFFFFFF
    return str(value % (10 ** TOTP_DIGITS)).zfill(TOTP_DIGITS)


def current_step(now=None):
    return int((now if now is not None else time.time()) // TOTP_STEP_SECONDS)


def totp_code(secret_b32, step=None):
    return _hotp(secret_b32, current_step() if step is None else step)


def match_totp(secret_b32, code, last_used_step=None, now=None):
    """Return the matching time-step for ``code`` or None.

    Steps at or before ``last_used_step`` are rejected (no replay).
    """
    code = str(code or "").strip().replace(" ", "")
    if len(code) != TOTP_DIGITS or not code.isdigit():
        return None
    step = current_step(now)
    for candidate in range(step - TOTP_DRIFT_STEPS, step + TOTP_DRIFT_STEPS + 1):
        if last_used_step is not None and candidate <= last_used_step:
            continue
        if hmac.compare_digest(_hotp(secret_b32, candidate), code):
            return candidate
    return None


def otpauth_uri(secret_b32, account_email):
    label = quote("{}:{}".format(TOTP_ISSUER, account_email))
    return (
        "otpauth://totp/{label}?secret={secret}&issuer={issuer}"
        "&algorithm=SHA1&digits={digits}&period={period}"
    ).format(
        label=label,
        secret=secret_b32,
        issuer=quote(TOTP_ISSUER),
        digits=TOTP_DIGITS,
        period=TOTP_STEP_SECONDS,
    )


def encrypt_secret(secret_b32):
    return _fernet().encrypt(secret_b32.encode("ascii")).decode("ascii")


def decrypt_secret(token):
    return _fernet().decrypt(token.encode("ascii")).decode("ascii")


# ============================================================
# TOKENS / CODES
# ============================================================

def _sha256(value):
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def _new_token():
    return secrets.token_urlsafe(32)


def _normalise_recovery_code(code):
    return "".join(ch for ch in str(code or "").upper() if ch.isalnum())


def new_recovery_codes(user_id):
    """Replace the user's recovery codes; return the plaintext codes once."""
    AdminRecoveryCode.query.filter_by(user_id=user_id).delete(
        synchronize_session=False
    )
    alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    codes = []
    for _ in range(RECOVERY_CODE_COUNT):
        raw = "".join(secrets.choice(alphabet) for _ in range(12))
        codes.append("{}-{}-{}".format(raw[:4], raw[4:8], raw[8:]))
        db.session.add(AdminRecoveryCode(
            user_id=user_id,
            code_hash=_sha256(_normalise_recovery_code(raw)),
        ))
    return codes


def consume_recovery_code(user_id, code):
    normalised = _normalise_recovery_code(code)
    if len(normalised) != 12:
        return False
    result = AdminRecoveryCode.query.filter_by(
        user_id=user_id,
        code_hash=_sha256(normalised),
        used_at=None,
    ).update(
        {AdminRecoveryCode.used_at: datetime.utcnow()},
        synchronize_session=False,
    )
    return result == 1


# ============================================================
# SESSIONS
# ============================================================

def create_session(user, state, ip_address=None, user_agent=None):
    """Create a pending or active session and return the raw token."""
    now = datetime.utcnow()
    if state == ADMIN_SESSION_PENDING_MFA:
        expires = now + timedelta(minutes=PENDING_SESSION_MINUTES)
    else:
        expires = now + timedelta(hours=session_max_hours())
    raw = _new_token()
    db.session.add(AdminSession(
        user_id=user.id,
        token_hash=_sha256(raw),
        state=state,
        expires_at=expires,
        last_seen_at=now,
        token_version=int(user.token_version or 1),
        ip_address=(ip_address or "")[:64] or None,
        user_agent=(user_agent or "")[:255] or None,
    ))
    return raw, expires


def find_session(raw_token, state):
    """Return (session, user) for a live session in ``state``, else (None, None)."""
    if not raw_token or not isinstance(raw_token, str):
        return None, None
    session = AdminSession.query.filter_by(
        token_hash=_sha256(raw_token.strip())
    ).first()
    if session is None or session.state != state:
        return None, None

    now = datetime.utcnow()
    if session.revoked_at is not None or session.expires_at <= now:
        return None, None

    if state == ADMIN_SESSION_ACTIVE:
        idle = timedelta(minutes=session_idle_minutes())
        if session.last_seen_at is not None and now - session.last_seen_at > idle:
            return None, None

    user = db.session.get(User, session.user_id)
    if (
        user is None
        or user.role != ROLE_ADMIN
        or not user.email_verified
        or not user.password_hash
        or int(user.token_version or 1) != int(session.token_version or 1)
    ):
        return None, None

    return session, user


def touch(session):
    """Extend the idle timeout (at most once a minute to limit writes)."""
    now = datetime.utcnow()
    if session.last_seen_at is None or (now - session.last_seen_at).total_seconds() > 60:
        session.last_seen_at = now


def revoke_sessions(user_id):
    AdminSession.query.filter_by(user_id=user_id).filter(
        AdminSession.revoked_at.is_(None)
    ).update(
        {AdminSession.revoked_at: datetime.utcnow()},
        synchronize_session=False,
    )


# ============================================================
# ENROLLMENT WINDOW
# ============================================================

def open_enrollment(user_id):
    """(Re)open MFA enrollment: drop the old factor and recovery codes.

    Called only by the operator CLI (grant / reset-mfa). The placeholder row
    records when the window opened; it holds no usable secret until /setup.
    """
    AdminMfa.query.filter_by(user_id=user_id).delete(synchronize_session=False)
    AdminRecoveryCode.query.filter_by(user_id=user_id).delete(
        synchronize_session=False
    )
    db.session.add(AdminMfa(
        user_id=user_id,
        secret_encrypted="",
        enabled_at=None,
        created_at=datetime.utcnow(),
    ))


def enrollment_open(mfa_row):
    if mfa_row is None or mfa_row.enabled_at is not None:
        return False
    deadline = mfa_row.created_at + timedelta(hours=ENROLLMENT_WINDOW_HOURS)
    return datetime.utcnow() <= deadline


# ============================================================
# AUDIT
# ============================================================

def audit(action, user_id=None, request=None, status_code=None, detail=None,
          ip_address=None):
    """Append an audit record. Never raises (and never logs secrets)."""
    try:
        db.session.add(AdminAuditLog(
            admin_user_id=user_id,
            action=action[:40],
            method=getattr(request, "method", None),
            path=(getattr(request, "path", None) or "")[:255] or None,
            status_code=status_code,
            ip_address=(ip_address or "")[:64] or None,
            detail=detail,
        ))
        db.session.commit()
    except Exception:
        db.session.rollback()
        logger.exception("Failed to write admin audit record")
