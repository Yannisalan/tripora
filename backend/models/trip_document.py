from datetime import datetime

from config.database import db


class TripDocument(db.Model):
    """A single travel document stored in a trip's Vault.

    Only metadata lives in the database. The actual file is stored in the
    configured object-storage backend (S3-compatible by default, local disk
    for local development only) under ``storage_key`` and is served back
    exclusively through the authenticated ``GET /api/documents/<id>`` route.

    Ownership model:

    - ``trip_id``  → the owning trip (cascade deletes with the trip).
    - ``user_id``  → the owner, denormalised so RLS/authorization checks are
      one simple lookup and requests never have to join through ``trips``.

    ``user_id`` is intentionally a real column (not just a relationship), so
    the PostgreSQL Row-Level Security policies on this table can enforce
    ownership at the database layer exactly like they do for ``trips``.
    """

    __tablename__ = "trip_documents"

    # ============================================================
    # PRIMARY KEY
    # ============================================================

    id = db.Column(
        db.Integer,
        primary_key=True,
    )

    # ============================================================
    # OWNERSHIP
    # ============================================================

    trip_id = db.Column(
        db.Integer,
        db.ForeignKey("trips.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )

    user_id = db.Column(
        db.Integer,
        db.ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )

    trip = db.relationship(
        "Trip",
        back_populates="documents",
    )

    user = db.relationship(
        "User",
        foreign_keys=[user_id],
    )

    # ============================================================
    # METADATA
    # ============================================================

    # Display name chosen by the user (e.g. "Flight Ticket").
    name = db.Column(
        db.String(255),
        nullable=False,
    )

    # One of: flight, hotel, visa, insurance, transport, activity, other.
    document_type = db.Column(
        db.String(30),
        nullable=False,
    )

    # Original file name, kept only for display. Never used as a storage path.
    file_name = db.Column(
        db.String(255),
        nullable=False,
    )

    # Safe, generated key in the storage backend
    # (e.g. "trips/<trip_id>/<uuid>.pdf"). Never includes the user's name.
    storage_key = db.Column(
        db.String(255),
        nullable=False,
    )

    mime_type = db.Column(
        db.String(100),
        nullable=False,
    )

    file_size = db.Column(
        db.BigInteger,
        nullable=False,
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

    def to_dict(self):
        return {
            "id": self.id,
            "tripId": self.trip_id,
            "name": self.name,
            "documentType": self.document_type,
            "fileName": self.file_name,
            "mimeType": self.mime_type,
            "fileSize": self.file_size,
            "createdAt": (
                self.created_at.isoformat()
                if self.created_at
                else None
            ),
        }