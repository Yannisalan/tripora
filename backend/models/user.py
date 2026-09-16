from datetime import datetime

from config.database import db


# ============================================================
# USER MODEL
# ============================================================

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

        kwargs.setdefault("email_verified", True)

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