from datetime import datetime

from config.database import db


class Trip(db.Model):
    __tablename__ = "trips"

    # ============================================================
    # PRIMARY KEY
    # ============================================================

    id = db.Column(
        db.Integer,
        primary_key=True
    )

    # ============================================================
    # USER
    # ============================================================

    user_id = db.Column(
        db.Integer,
        db.ForeignKey("users.id"),
        nullable=True
    )

    user = db.relationship(
        "User",
        back_populates="trips"
    )

    # ============================================================
    # TRIP DETAILS
    # ============================================================

    destination = db.Column(
        db.String(255),
        nullable=False
    )

    start_date = db.Column(
        db.Date,
        nullable=False
    )

    end_date = db.Column(
        db.Date,
        nullable=False
    )

    travelers = db.Column(
        db.Integer,
        nullable=False
    )

    budget = db.Column(
        db.String(50),
        nullable=True
    )

    # Numeric budget (trip currency is the user's preferred currency at read
    # time). Kept alongside the categorical ``budget`` label (Budget /
    # Moderate / Luxury) which existing API clients rely on.
    budget_amount = db.Column(
        db.Numeric(12, 2),
        nullable=True
    )

    travel_style = db.Column(
        db.String(100),
        nullable=True
    )

    # ============================================================
    # JSON DATA
    # ============================================================

    interests = db.Column(
        db.JSON,
        nullable=True
    )

    itinerary = db.Column(
        db.JSON,
        nullable=True
    )

    estimated_cost = db.Column(
        db.JSON,
        nullable=True
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
    # DOCUMENTS (VAULT)
    # ============================================================

    documents = db.relationship(
        "TripDocument",
        back_populates="trip",
        cascade="all, delete-orphan",
        passive_deletes=True,
    )

    # ============================================================
    # EXPENSES
    # ============================================================

    expenses = db.relationship(
        "Expense",
        back_populates="trip",
        cascade="all, delete-orphan",
        passive_deletes=True,
    )