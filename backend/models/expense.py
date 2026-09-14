from datetime import datetime

from sqlalchemy import Index

from config.database import db

# ============================================================
# EXPENSE CONSTANTS (shared by API validation + frontend labels)
# ============================================================

EXPENSE_CATEGORIES = (
    "transport",
    "accommodation",
    "food",
    "activities",
    "shopping",
    "health",
    "other",
)

PAYMENT_METHODS = ("cash", "card", "mobile", "other")

VALID_CURRENCIES = (
    "USD", "EUR", "GBP", "JPY", "CNY", "INR", "CAD", "AUD",
    "CHF", "SEK", "NOK", "DKK", "SGD", "HKD", "NZD", "KRW",
    "BRL", "MXN", "ZAR", "AED", "SAR", "TRY",
)


class Expense(db.Model):
    __tablename__ = "trip_expenses"
    __table_args__ = (
        Index("ix_trip_expenses_trip_id_date", "trip_id", "date"),
        Index("ix_trip_expenses_user_id", "user_id"),
    )

    # ============================================================
    # PRIMARY KEY
    # ============================================================

    id = db.Column(
        db.Integer,
        primary_key=True,
    )

    # ============================================================
    # OWNERSHIP (implicitly enforced by RLS + explicit queries)
    # ============================================================

    trip_id = db.Column(
        db.Integer,
        db.ForeignKey("trips.id", ondelete="CASCADE"),
        nullable=False,
    )

    trip = db.relationship(
        "Trip",
        back_populates="expenses",
    )

    user_id = db.Column(
        db.Integer,
        db.ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )

    user = db.relationship("User")

    # ============================================================
    # AMOUNT
    # ============================================================

    amount = db.Column(
        db.Numeric(12, 2),
        nullable=False,
    )

    currency = db.Column(
        db.String(10),
        nullable=False,
        default="USD",
    )

    # ============================================================
    # DETAILS
    # ============================================================

    category = db.Column(
        db.String(30),
        nullable=False,
    )

    description = db.Column(
        db.String(255),
        nullable=True,
    )

    date = db.Column(
        db.Date,
        nullable=False,
    )

    payment_method = db.Column(
        db.String(30),
        nullable=True,
    )

    # ============================================================
    # TIMESTAMPS
    # ============================================================

    created_at = db.Column(
        db.DateTime,
        nullable=False,
        default=datetime.utcnow,
    )

    updated_at = db.Column(
        db.DateTime,
        nullable=False,
        default=datetime.utcnow,
        onupdate=datetime.utcnow,
    )

    # ============================================================
    # SERIALIZATION
    # ============================================================

    def to_dict(self):
        from datetime import timezone

        return {
            "id": self.id,
            "tripId": self.trip_id,
            "amount": float(self.amount) if self.amount is not None else 0.0,
            "currency": self.currency,
            "category": self.category,
            "description": self.description or "",
            "date": self.date.isoformat() if self.date else None,
            "paymentMethod": self.payment_method or "",
            "createdAt": (
                self.created_at.replace(tzinfo=timezone.utc).isoformat()
                if self.created_at else None
            ),
            "updatedAt": (
                self.updated_at.replace(tzinfo=timezone.utc).isoformat()
                if self.updated_at else None
            ),
        }