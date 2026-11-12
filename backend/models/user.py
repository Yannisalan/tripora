from datetime import datetime

from config.database import db


# ============================================================
# USER MODEL
# ============================================================

ROLE_USER = "user"
ROLE_ADMIN = "admin"
VALID_ROLES = (ROLE_USER, ROLE_ADMIN)


class User(db.Model):
    __tablename__ = "users"

    # A provider identity (e.g. Google ``sub``) may only ever resolve to one
    # Tripora account. Mirrors the ``ix_users_social_identity`` Alembic index;
    # the partial predicate only applies on Postgres (SQLite treats NULLs as
    # distinct, which is the same intent for conventional accounts).
    __table_args__ = (
        db.Index(
            "ix_users_social_identity",
            "auth_provider",
            "provider_id",
            unique=True,
            postgresql_where=db.text("auth_provider IS NOT NULL"),
        ),
    )

    def __init__(self, **kwargs):
        # Default preferences
        kwargs.setdefault("preferred_language", "en")
        kwargs.setdefault("preferred_currency", "USD")

        # Secure default: an account is unverified until its owner proves
        # control of the address (email code) or a provider asserts it.
        kwargs.setdefault("email_verified", False)
        kwargs.setdefault("role", ROLE_USER)

        super().__init__(**kwargs)

    # ========================================================
    # PRIMARY KEY
    # ========================================================

    id = db.Column(
        db.Integer,
        primary_key=True,
    )

    # ========================================================
    # USER DETAILS
    # ========================================================

    name = db.Column(
        db.String(100),
        nullable=False,
    )

    email = db.Column(
        db.String(255),
        unique=True,
        nullable=False,
        index=True,
    )

    password_hash = db.Column(
        db.String(255),
        nullable=True,
    )

    # ========================================================
    # EMAIL VERIFICATION
    # ========================================================

    email_verified = db.Column(
        db.Boolean,
        nullable=False,
        default=False,
    )

    verification_token = db.Column(
        db.String(255),
        unique=True,
        nullable=True,
    )

    verification_token_expires_at = db.Column(
        db.DateTime,
        nullable=True,
    )

    # 6-digit email-verification code (hash only), its expiry, failed attempt
    # counter and when it was last sent (resend cooldown). Cleared on success.
    email_verification_code_hash = db.Column(
        db.String(255),
        nullable=True,
    )

    email_verification_expires_at = db.Column(
        db.DateTime,
        nullable=True,
    )

    email_verification_attempts = db.Column(
        db.Integer,
        nullable=False,
        default=0,
    )

    email_verification_sent_at = db.Column(
        db.DateTime,
        nullable=True,
    )

    # ========================================================
    # AUTHORIZATION ROLE
    # ========================================================
    # Server-side only. No API endpoint writes this column; administrators
    # are granted with the `flask admin grant` CLI command.
    # ========================================================

    role = db.Column(
        db.String(20),
        nullable=False,
        default=ROLE_USER,
        server_default=ROLE_USER,
    )

    # ========================================================
    # SOCIAL AUTH
    # ========================================================

    auth_provider = db.Column(
        db.String(20),
        nullable=True,
    )

    provider_id = db.Column(
        db.String(255),
        nullable=True,
        index=True,
    )

    # ========================================================
    # TOKEN VERSION (ACCESS-TOKEN REVOCATION)
    # ========================================================
    # ``token_version`` is copied into every issued access token as the
    # ``ver`` claim. Bumping it invalidates every access token that was
    # minted before the bump, so a password change / password reset can
    # kick out sessions that are still inside their (short) expiry window.
    # ========================================================

    token_version = db.Column(
        db.Integer,
        nullable=False,
        default=1,
    )

    # ========================================================
    # PASSWORD RESET
    # ========================================================
    # ``reset_code_hash`` holds the 6-digit one-time code sent by email and
    # ``reset_token_hash`` holds the one-time token returned by the verify
    # step. Both are stored as hashes (never plaintext). ``reset_attempts``
    # counts failed code attempts so a locked-out user must request a new
    # code. Every field is cleared once the password is reset.
    # ========================================================

    reset_code_hash = db.Column(
        db.String(255),
        nullable=True,
    )

    reset_code_expires_at = db.Column(
        db.DateTime,
        nullable=True,
    )

    reset_attempts = db.Column(
        db.Integer,
        nullable=False,
        default=0,
    )

    reset_token_hash = db.Column(
        db.String(255),
        nullable=True,
        index=True,
    )

    reset_token_expires_at = db.Column(
        db.DateTime,
        nullable=True,
    )

    # ========================================================
    # PREFERENCES
    # ========================================================

    preferred_language = db.Column(
        db.String(10),
        nullable=False,
        default="en",
    )

    preferred_currency = db.Column(
        db.String(10),
        nullable=False,
        default="USD",
    )

    # ========================================================
    # REGION
    # ========================================================

    region_country = db.Column(
        db.String(2),
        nullable=True,
        index=True,
    )

    # ========================================================
    # CREATED AT
    # ========================================================

    created_at = db.Column(
        db.DateTime,
        default=datetime.utcnow,
        nullable=False,
    )

    # ========================================================
    # TRIPS
    # ========================================================

    trips = db.relationship(
        "Trip",
        back_populates="user",
        lazy=True,
    )