from datetime import datetime

from config.database import db


class Subscription(db.Model):
    """A user's 1:1 subscription record.

    ``is_active`` is computed from ``status`` + ``active_until`` rather than
    being a stored boolean, so it can never drift out of sync with the plan
    the IAP provider actually granted. Store/transaction ids are kept so the
    receipt/order can be re-verified later.
    """

    __tablename__ = "subscriptions"

    # ============================================================
    # PRIMARY KEY
    # ============================================================

    id = db.Column(
        db.Integer,
        primary_key=True,
    )

    # ============================================================
    # USER (1:1)
    # ============================================================

    user_id = db.Column(
        db.Integer,
        db.ForeignKey("users.id"),
        nullable=False,
        unique=True,
    )

    user = db.relationship(
        "User",
        back_populates="subscription",
    )

    # ============================================================
    # PLAN
    # ============================================================

    # One of the configured tiers (e.g. "tier_1", "tier_2", "tier_3").
    tier = db.Column(
        db.String(20),
        nullable=False,
        default="tier_1",
    )

    # monthly / yearly
    period = db.Column(
        db.String(20),
        nullable=False,
        default="monthly",
    )

    # active / expired / cancelled / refunded
    status = db.Column(
        db.String(20),
        nullable=False,
        default="active",
    )

    # ============================================================
    # STORE / BILLING
    # ============================================================

    # appstore / googleplay
    store = db.Column(
        db.String(20),
        nullable=True,
    )

    store_product_id = db.Column(
        db.String(255),
        nullable=True,
    )

    store_transaction_id = db.Column(
        db.String(255),
        nullable=True,
        index=True,
    )

    # ============================================================
    # ENTITLEMENT WINDOW
    # ============================================================

    active_until = db.Column(
        db.DateTime,
        nullable=True,
    )

    # ============================================================
    # TIMESTAMPS
    # ============================================================

    created_at = db.Column(
        db.DateTime,
        default=datetime.utcnow,
        nullable=False,
    )

    updated_at = db.Column(
        db.DateTime,
        default=datetime.utcnow,
        onupdate=datetime.utcnow,
        nullable=False,
    )

    # ============================================================
    # HELPERS
    # ============================================================

    @property
    def is_active(self):
        if self.status != "active":
            return False
        if self.active_until is None:
            return True
        return self.active_until > datetime.utcnow()
