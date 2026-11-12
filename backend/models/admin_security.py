"""Administrator MFA, sessions and audit trail.

Administrators are ordinary ``users`` rows with ``role = 'admin'``. On top of
their password they must pass a TOTP second factor; the resulting admin session
is an opaque random token (only its SHA-256 is stored) that expires, can be
revoked, and is checked server-side on every ``/api/admin/*`` request.

Every row here references ``users.id`` with ``ON DELETE CASCADE`` (audit rows
use ``SET NULL`` so the trail survives an account deletion).
"""

from datetime import datetime

from config.database import db


ADMIN_SESSION_PENDING_MFA = "pending_mfa"
ADMIN_SESSION_ACTIVE = "active"


class AdminMfa(db.Model):
    """TOTP enrollment for one administrator."""

    __tablename__ = "admin_mfa"

    user_id = db.Column(
        db.Integer,
        db.ForeignKey("users.id", ondelete="CASCADE"),
        primary_key=True,
    )

    # Fernet-encrypted base32 TOTP secret (key: MFA_ENCRYPTION_KEY).
    secret_encrypted = db.Column(db.Text, nullable=False)

    # NULL until the admin proves possession of the authenticator.
    enabled_at = db.Column(db.DateTime, nullable=True)

    # Highest TOTP time-step already accepted; blocks code replay.
    last_used_step = db.Column(db.BigInteger, nullable=True)

    created_at = db.Column(
        db.DateTime, nullable=False, default=datetime.utcnow,
    )


class AdminRecoveryCode(db.Model):
    """Single-use MFA recovery code (hash only)."""

    __tablename__ = "admin_recovery_codes"

    id = db.Column(db.Integer, primary_key=True)

    user_id = db.Column(
        db.Integer,
        db.ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )

    code_hash = db.Column(db.String(64), nullable=False, unique=True)

    used_at = db.Column(db.DateTime, nullable=True)

    created_at = db.Column(
        db.DateTime, nullable=False, default=datetime.utcnow,
    )


class AdminSession(db.Model):
    """Server-side admin session (pending-MFA or fully authenticated)."""

    __tablename__ = "admin_sessions"

    id = db.Column(db.Integer, primary_key=True)

    user_id = db.Column(
        db.Integer,
        db.ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )

    token_hash = db.Column(db.String(64), nullable=False, unique=True)

    # ``pending_mfa``: password verified, second factor outstanding.
    # ``active``: password + second factor verified.
    state = db.Column(db.String(20), nullable=False)

    # Failed second-factor attempts on a pending session.
    mfa_attempts = db.Column(db.Integer, nullable=False, default=0)

    created_at = db.Column(
        db.DateTime, nullable=False, default=datetime.utcnow,
    )
    expires_at = db.Column(db.DateTime, nullable=False, index=True)
    last_seen_at = db.Column(db.DateTime, nullable=True)
    revoked_at = db.Column(db.DateTime, nullable=True)

    # Copied from users.token_version: a password change/reset ends sessions.
    token_version = db.Column(db.Integer, nullable=False, default=1)

    ip_address = db.Column(db.String(64), nullable=True)
    user_agent = db.Column(db.String(255), nullable=True)


class AdminAuditLog(db.Model):
    """Append-only record of administrator authentication and access."""

    __tablename__ = "admin_audit_log"

    # Append-only from the app: no RETURNING, so RLS needs no SELECT policy
    # for writers; only authorized admin reads may see audit rows.
    __table_args__ = {"implicit_returning": False}

    id = db.Column(db.Integer, primary_key=True)

    admin_user_id = db.Column(
        db.Integer,
        db.ForeignKey("users.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )

    # e.g. login_password_ok, login_failed, mfa_enrolled, mfa_failed,
    # session_started, logout, access, legacy_token_access
    action = db.Column(db.String(40), nullable=False, index=True)

    method = db.Column(db.String(10), nullable=True)
    path = db.Column(db.String(255), nullable=True)
    status_code = db.Column(db.Integer, nullable=True)
    ip_address = db.Column(db.String(64), nullable=True)
    detail = db.Column(db.JSON, nullable=True)

    created_at = db.Column(
        db.DateTime, nullable=False, default=datetime.utcnow, index=True,
    )
