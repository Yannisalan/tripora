from datetime import datetime

from config.database import db


# ============================================================
# USER MODEL
# ============================================================

class User(db.Model):
    __tablename__ = "users"

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
    # SUBSCRIPTION
    # ========================================================

    subscription = db.relationship(
        "Subscription",
        uselist=False,
        back_populates="user",
        cascade="all, delete-orphan",
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