import secrets
from datetime import datetime

from config.database import db


def generate_verification_token():
    return secrets.token_urlsafe(32)


class User(db.Model):
    __tablename__ = "users"

    def __init__(self, **kwargs):
        if "preferred_language" not in kwargs:
            kwargs["preferred_language"] = "en"
        if "preferred_currency" not in kwargs:
            kwargs["preferred_currency"] = "USD"
        if "email_verified" not in kwargs:
            kwargs["email_verified"] = False
        if "verification_token" not in kwargs:
            kwargs["verification_token"] = generate_verification_token()
        super().__init__(**kwargs)

    # ============================================================
    # PRIMARY KEY
    # ============================================================

    id = db.Column(
        db.Integer,
        primary_key=True
    )

    # ============================================================
    # USER DETAILS
    # ============================================================

    name = db.Column(
        db.String(100),
        nullable=False
    )

    email = db.Column(
        db.String(255),
        unique=True,
        nullable=False,
        index=True
    )

    password_hash = db.Column(
        db.String(255),
        nullable=True
    )

    email_verified = db.Column(
        db.Boolean,
        nullable=False,
        default=False,
    )

    verification_token = db.Column(
        db.String(255),
        unique=True,
        nullable=True,
        default=generate_verification_token,
    )

    # ============================================================
    # SOCIAL AUTH
    # ============================================================

    auth_provider = db.Column(
        db.String(20),
        nullable=True,
    )

    provider_id = db.Column(
        db.String(255),
        nullable=True,
        index=True,
    )

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

    # Region (ISO 3166-1 alpha-2 country code) used to resolve the
    # subscription price tier. Derived from the account/locale; may be
    # empty until a signing/platform region is resolved.
    region_country = db.Column(
        db.String(2),
        nullable=True,
        index=True,
    )

    # ============================================================
    # SUBSCRIPTION
    # ============================================================

    subscription = db.relationship(
        "Subscription",
        uselist=False,
        back_populates="user",
        cascade="all, delete-orphan",
    )

    # ============================================================
    # CREATED AT
    # ============================================================

    created_at = db.Column(
        db.DateTime,
        default=datetime.utcnow,
        nullable=False
    )

    # ============================================================
    # TRIPS
    # ============================================================

    trips = db.relationship(
        "Trip",
        back_populates="user",
        lazy=True
    )