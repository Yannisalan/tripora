from datetime import datetime

from config.database import db


class PlaceCoordinate(db.Model):
    """Cached geocoding results for map markers on the travel map.

    Our itinerary activities carry a free-text ``location`` (an area/venue
    name), not coordinates. Before drawing anything on the map the backend
    resolves those names through Nominatim and caches the result here so
    neither the third-party service nor the database is hammered by repeated
    lookups of the same place.
    """

    __tablename__ = "place_coordinates"

    # ============================================================
    # PRIMARY KEY
    # ============================================================

    id = db.Column(
        db.Integer,
        primary_key=True,
    )

    # ============================================================
    # QUERY (normalized, unique lookup key)
    # ============================================================
    # The ORM attribute is ``location_query`` because the database column is
    # named ``query`` -- a column called ``query`` would shadow SQLAlchemy's
    # ``Model.query`` constructor.

    location_query = db.Column(
        "query",
        db.String(255),
        unique=True,
        nullable=False,
        index=True,
    )

    # ============================================================
    # RESULT
    # ============================================================

    name = db.Column(
        db.String(255),
        nullable=True,
    )

    display_name = db.Column(
        db.String(512),
        nullable=True,
    )

    latitude = db.Column(
        db.Numeric(9, 6),
        nullable=True,
    )

    longitude = db.Column(
        db.Numeric(9, 6),
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

    def to_dict(self):
        return {
            "query": self.location_query,
            "name": self.name,
            "displayName": self.display_name,
            "latitude": (
                float(self.latitude) if self.latitude is not None else None
            ),
            "longitude": (
                float(self.longitude) if self.longitude is not None else None
            ),
        }