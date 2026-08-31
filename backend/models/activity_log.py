from datetime import datetime

from config.database import db


class ActivityLog(db.Model):
    """A single recorded interaction with the Tripora service.

    Used by the admin analytics surface to show how people use the product.
    Two event types are captured:

    - ``api_request``: every (configurable) HTTP request handled by the
      backend, written by the ``after_request`` hook in ``app.py``.
    - ``page_view``: a client-side screen visit, reported by the Flutter app
      via ``POST /api/admin/page-view`` (the admin token is not required for
      this write; a light, rate-limited public beacon keeps data flowing even
      for anonymous users before they sign in).

    ``user_id`` may be null for anonymous page views and unauthenticated API
    requests.
    """

    __tablename__ = "activity_logs"

    # ============================================================
    # PRIMARY KEY
    # ============================================================

    id = db.Column(
        db.Integer,
        primary_key=True,
    )

    # ============================================================
    # EVENT
    # ============================================================

    event_type = db.Column(
        db.String(30),
        nullable=False,
        index=True,
    )

    # `api_request` -> HTTP path (e.g. "/api/trips/generate")
    # `page_view`   -> screen name (e.g. "/planner")
    path = db.Column(
        db.String(255),
        nullable=True,
        index=True,
    )

    method = db.Column(
        db.String(10),
        nullable=True,
    )

    status_code = db.Column(
        db.Integer,
        nullable=True,
    )

    # ============================================================
    # SUBJECT
    # ============================================================

    user_id = db.Column(
        db.Integer,
        db.ForeignKey("users.id"),
        nullable=True,
        index=True,
    )

    user = db.relationship(
        "User",
        foreign_keys=[user_id],
    )

    # Free-form JSON (e.g. page arguments, query params, error detail).
    detail = db.Column(
        db.JSON,
        nullable=True,
    )

    ip_address = db.Column(
        db.String(64),
        nullable=True,
    )

    # ============================================================
    # TIMESTAMP
    # ============================================================

    created_at = db.Column(
        db.DateTime,
        default=datetime.utcnow,
        nullable=False,
        index=True,
    )

    def to_dict(self):
        return {
            "id": self.id,
            "eventType": self.event_type,
            "path": self.path,
            "method": self.method,
            "statusCode": self.status_code,
            "userId": self.user_id,
            "detail": self.detail,
            "ipAddress": self.ip_address,
            "createdAt": (
                self.created_at.isoformat()
                if self.created_at
                else None
            ),
        }
