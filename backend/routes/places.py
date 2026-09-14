import logging
import re

import httpx
from flask import Blueprint, jsonify, request
from flask_jwt_extended import (
    get_jwt_identity,
    jwt_required,
)

from config.database import db
from models.place_coordinate import PlaceCoordinate

logger = logging.getLogger(__name__)


places_bp = Blueprint(
    "places",
    __name__,
    url_prefix="/api/places",
)

NOMINATIM_ENDPOINT = "https://nominatim.openstreetmap.org/search"
OSRM_ENDPOINT = "https://router.project-osrm.org/route/v1/driving"

# Nominatim's usage policy asks clients to identify themselves.
GEOCODING_USER_AGENT = "Tripora/1.0 (travel itinerary app; support@tripora.app)"

# Same-day cache: treat a cached resolution as fresh for 24h. Misses are
# cached too so an unresolvable place is not re-queried every visit.
CACHE_TTL_SECONDS = 24 * 60 * 60

_TIMEOUT = 12


def _normalize_query(query):
    return re.sub(r"\s+", " ", str(query or "").strip()).lower()


def _geo_geocode_via_nominatim(query):
    """Resolve a free-text place name to coordinates via Nominatim.

    Returns a dict with name/display_name/latitude/longitude (string lat/lng
    from the JSON API) or None when nothing matched. Raises on transport or
    parse errors; callers translate exceptions into a graceful response.
    """
    response = httpx.get(
        NOMINATIM_ENDPOINT,
        params={
            "q": query,
            "format": "json",
            "limit": 1,
            "addressdetails": 0,
            "accept-language": "en",
        },
        headers={"User-Agent": GEOCODING_USER_AGENT},
        timeout=_TIMEOUT,
    )
    response.raise_for_status()

    results = response.json()
    if not results:
        return None

    first = results[0]
    latitude = first.get("lat")
    longitude = first.get("lon")
    if latitude is None or longitude is None:
        return None

    return {
        "name": first.get("name") or query,
        "display_name": first.get("display_name") or query,
        "latitude": latitude,
        "longitude": longitude,
    }


def _geo_route_via_osrm(from_lat, from_lng, to_lat, to_lng):
    """Request a driving polyline from OSRM's public router.

    Returns a list of [latitude, longitude] pairs or [] when no route exists.
    Raises on transport/parse errors so callers can degrade gracefully.
    """
    url = "{}/{},{};{},{}?overview=full&geometries=geojson".format(
        OSRM_ENDPOINT, from_lng, from_lat, to_lng, to_lat
    )
    response = httpx.get(url, timeout=_TIMEOUT)
    response.raise_for_status()

    body = response.json()
    routes = body.get("routes") or []
    if not routes:
        return []

    geometry = routes[0].get("geometry") or {}
    coordinates = geometry.get("coordinates") or []
    # OSRM returns [lon, lat]; the map wants [lat, lon].
    return [
        [point[1], point[0]]
        for point in coordinates
        if isinstance(point, list) and len(point) >= 2
    ]


def _validate_lat_lng(value, field, minimum, maximum):
    try:
        parsed = float(value)
    except (TypeError, ValueError):
        raise ValueError(f"{field} must be a number.")
    if not (minimum <= parsed <= maximum):
        raise ValueError(f"{field} is out of range.")
    return parsed


# ============================================================
# GEOCODE
# GET /api/places/geocode?query=...
# ============================================================

@places_bp.route("/geocode", methods=["GET"])
@jwt_required()
def geocode():

    get_jwt_identity()

    query = request.args.get("query", "").strip()

    if not query:
        return jsonify({
            "success": False,
            "message": "Query is required.",
        }), 400

    if len(query) > 255:
        return jsonify({
            "success": False,
            "message": "Query is too long.",
        }), 400

    normalized = _normalize_query(query)

    try:

        # ----------------------------------------------------
        # Cache lookup (both hits and misses are cached so the
        # third-party geocoder is rarely called twice).
        # ----------------------------------------------------
        cached = PlaceCoordinate.query.filter_by(
            location_query=normalized
        ).first()

        if cached is not None:
            if cached.latitude is not None and cached.longitude is not None:
                return jsonify({
                    "success": True,
                    "geocoded": True,
                    "coordinate": cached.to_dict(),
                }), 200
            return jsonify({
                "success": True,
                "geocoded": False,
                "coordinate": None,
                "message": "Could not resolve that location.",
            }), 200

        # ----------------------------------------------------
        # Fresh resolution via Nominatim. Any upstream failure is
        # surfaced as 503 so the client keeps the map working.
        # ----------------------------------------------------
        try:
            result = _geo_geocode_via_nominatim(normalized)
        except Exception:
            logger.exception("Nominatim upstream error")
            return jsonify({
                "success": False,
                "message": "Location service is temporarily unavailable.",
            }), 503

        record = PlaceCoordinate(
            location_query=normalized,
            name=(result or {}).get("name"),
            display_name=(result or {}).get("display_name"),
            latitude=(
                float(result["latitude"]) if result else None
            ),
            longitude=(
                float(result["longitude"]) if result else None
            ),
        )
        db.session.add(record)
        db.session.commit()

        if result is None:
            return jsonify({
                "success": True,
                "geocoded": False,
                "coordinate": None,
                "message": "Could not resolve that location.",
            }), 200

        logger.info("Geocoded query cached: %s", normalized)

        return jsonify({
            "success": True,
            "geocoded": True,
            "coordinate": record.to_dict(),
        }), 200

    except httpx.HTTPStatusError:
        logger.exception("Nominatim upstream error")
        return jsonify({
            "success": False,
            "message": "Location service is temporarily unavailable.",
        }), 503

    except Exception:
        logger.exception("Geocoding failed")
        return jsonify({
            "success": False,
            "message": "Failed to resolve location.",
            "error": "Internal server error.",
        }), 500


# ============================================================
# ROUTE
# GET /api/places/route
#   ?from_lat=..&from_lng=..&to_lat=..&to_lng=..
# ============================================================

@places_bp.route("/route", methods=["GET"])
@jwt_required()
def route():

    get_jwt_identity()

    try:
        from_lat = _validate_lat_lng(
            request.args.get("from_lat"), "from_lat", -90.0, 90.0
        )
        from_lng = _validate_lat_lng(
            request.args.get("from_lng"), "from_lng", -180.0, 180.0
        )
        to_lat = _validate_lat_lng(
            request.args.get("to_lat"), "to_lat", -90.0, 90.0
        )
        to_lng = _validate_lat_lng(
            request.args.get("to_lng"), "to_lng", -180.0, 180.0
        )
    except ValueError as error:
        return jsonify({
            "success": False,
            "message": str(error),
        }), 400

    try:
        polyline = _geo_route_via_osrm(from_lat, from_lng, to_lat, to_lng)

        if not polyline:
            return jsonify({
                "success": True,
                "routed": False,
                "message": "No route found between those points.",
                "coordinates": [],
            }), 200

        return jsonify({
            "success": True,
            "routed": True,
            "coordinates": polyline,
        }), 200

    except Exception:
        logger.exception("Routing upstream failed")
        return jsonify({
            "success": True,
            "routed": False,
            "message": "Routing is temporarily unavailable.",
            "coordinates": [],
        }), 200