"""Premium-only live travel search endpoints (flights, stays, cars).

These endpoints proxy Duffel searches for subscribers. Entitlement is enforced
server-side with ``@require_premium`` (HTTP 403 for non-subscribers), so the
client flag is only a UI convenience. Provider credentials are read from the
server environment inside the service, never sent to or from the client.

Free users keep all existing features; itinerary generation is unaffected.
This module only adds live travel *search* (no booking, payments, or checkout).
"""

import logging
from datetime import date

from flask import Blueprint, jsonify, request
from flask_jwt_extended import jwt_required

from services.duffel_service import (
    DuffelError,
    search_cars,
    search_flights,
    search_stays,
)
from services.subscription_service import require_premium
from services.travelpayouts_service import (
    TravelpayoutsError,
    search_flight_prices,
)

logger = logging.getLogger(__name__)

travel_bp = Blueprint(
    "travel",
    __name__,
    url_prefix="/api/travel",
)


def _body():
    return request.get_json(silent=True) or {}


def _db_error_response(error):
    """Map a hard provider failure to a clean client-safe 502 response."""
    logger.warning("Travel search failed: %s", error)
    return jsonify({
        "success": False,
        "message": str(error),
        "error": "travel_provider_error",
        "code": "PROVIDER_ERROR",
    }), 502


def _iso_date(value, label):
    text = (value or "").strip()
    if not text:
        return None, None
    try:
        parsed = date.fromisoformat(text[:10])
    except ValueError:
        return None, f"{label} must be an ISO date (YYYY-MM-DD)."
    return parsed, None


# ============================================================
# FLIGHTS
# POST /api/travel/flights/search
# ============================================================

@travel_bp.route("/flights/search", methods=["POST"])
@jwt_required()
@require_premium
def search_flights_route():
    data = _body()

    origin = (data.get("origin") or "").strip().upper()
    destination = (data.get("destination") or "").strip().upper()
    depart_date_raw = (data.get("departDate") or "").strip()
    return_date_raw = (data.get("returnDate") or "").strip()

    if len(origin) != 3 or not origin.isalpha():
        return jsonify({
            "success": False,
            "message": "Origin must be a 3-letter IATA airport code.",
        }), 400
    if len(destination) != 3 or not destination.isalpha():
        return jsonify({
            "success": False,
            "message": "Destination must be a 3-letter IATA airport code.",
        }), 400
    if origin == destination:
        return jsonify({
            "success": False,
            "message": "Origin and destination must be different.",
        }), 400

    depart_date, err = _iso_date(depart_date_raw, "Depart date")
    if err:
        return jsonify({"success": False, "message": err}), 400
    if depart_date is None:
        return jsonify({
            "success": False,
            "message": "A 'departDate' is required.",
        }), 400

    return_date, err = _iso_date(return_date_raw, "Return date")
    if err:
        return jsonify({"success": False, "message": err}), 400
    if return_date is not None and return_date < depart_date:
        return jsonify({
            "success": False,
            "message": "Return date cannot be before the departure date.",
        }), 400

    try:
        passengers = int(data.get("passengers") or 1)
    except (TypeError, ValueError):
        passengers = 1
    if passengers < 1 or passengers > 9:
        return jsonify({
            "success": False,
            "message": "Passengers must be between 1 and 9.",
        }), 400

    cabin_class = (data.get("cabinClass") or "economy").strip().lower()
    allowed_cabins = {"economy", "premium_economy", "business", "first"}
    if cabin_class not in allowed_cabins:
        return jsonify({
            "success": False,
            "message": "cabinClass must be one of: economy, premium_economy, business, first.",
        }), 400

    try:
        results = search_flights(
            origin=origin,
            destination=destination,
            depart_date=depart_date.isoformat(),
            return_date=return_date.isoformat() if return_date else None,
            passengers=passengers,
            cabin_class=cabin_class,
        )
    except DuffelError as error:
        return _db_error_response(error)

    return jsonify({
        "success": True,
        "message": "Flight search results (premium).",
        "results": results,
    }), 200


# ============================================================
# FLIGHT PRICES
# POST /api/travel/flights/prices
#
# NOTE: This endpoint is intentionally NOT premium-gated -- any logged-in
# user can check real flight prices for their generated trip.
# ============================================================

@travel_bp.route("/flights/prices", methods=["POST"])
@jwt_required()
def flight_prices_route():
    data = _body()

    origin = (data.get("origin") or "").strip().upper()
    destination = (data.get("destination") or "").strip().upper()
    depart_date_raw = (data.get("departDate") or "").strip()

    if len(origin) != 3 or not origin.isalpha():
        return jsonify({
            "success": False,
            "message": "Origin must be a 3-letter IATA code.",
        }), 400
    if len(destination) != 3 or not destination.isalpha():
        return jsonify({
            "success": False,
            "message": "Destination must be a 3-letter IATA code.",
        }), 400
    if origin == destination:
        return jsonify({
            "success": False,
            "message": "Origin and destination must be different.",
        }), 400

    depart_date, err = _iso_date(depart_date_raw, "Depart date")
    if err:
        return jsonify({"success": False, "message": err}), 400
    if depart_date is None:
        return jsonify({
            "success": False,
            "message": "A 'departDate' is required.",
        }), 400

    currency = (data.get("currency") or "USD").strip().upper()
    try:
        results = search_flight_prices(
            origin=origin,
            destination=destination,
            depart_date=depart_date.isoformat(),
            currency=currency,
        )
    except TravelpayoutsError as error:
        return _db_error_response(error)

    return jsonify({
        "success": True,
        "message": "Flight price results.",
        "results": results,
    }), 200


# ============================================================
# STAYS
# POST /api/travel/stays/search
# ============================================================

@travel_bp.route("/stays/search", methods=["POST"])
@jwt_required()
@require_premium
def search_stays_route():
    data = _body()

    location = (data.get("location") or "").strip()
    if not location:
        return jsonify({
            "success": False,
            "message": "A 'location' is required.",
        }), 400

    check_in, err = _iso_date(data.get("checkIn") or "", "Check-in date")
    if err:
        return jsonify({"success": False, "message": err}), 400
    if check_in is None:
        return jsonify({
            "success": False,
            "message": "A 'checkIn' date is required.",
        }), 400

    check_out, err = _iso_date(data.get("checkOut") or "", "Check-out date")
    if err:
        return jsonify({"success": False, "message": err}), 400
    if check_out is None:
        return jsonify({
            "success": False,
            "message": "A 'checkOut' date is required.",
        }), 400
    if check_out <= check_in:
        return jsonify({
            "success": False,
            "message": "Check-out date must be after the check-in date.",
        }), 400

    try:
        guests = int(data.get("guests") or 2)
        rooms = int(data.get("rooms") or 1)
    except (TypeError, ValueError):
        return jsonify({
            "success": False,
            "message": "Guests and rooms must be whole numbers.",
        }), 400
    if guests < 1 or guests > 10:
        return jsonify({
            "success": False,
            "message": "Guests must be between 1 and 10.",
        }), 400
    if rooms < 1 or rooms > 5:
        return jsonify({
            "success": False,
            "message": "Rooms must be between 1 and 5.",
        }), 400

    try:
        results = search_stays(
            location=location,
            check_in=check_in.isoformat(),
            check_out=check_out.isoformat(),
            guests=guests,
            rooms=rooms,
        )
    except DuffelError as error:
        return _db_error_response(error)

    return jsonify({
        "success": True,
        "message": "Stay search results (premium).",
        "results": results,
    }), 200


# ============================================================
# CARS
# POST /api/travel/cars/search
# ============================================================

@travel_bp.route("/cars/search", methods=["POST"])
@jwt_required()
@require_premium
def search_cars_route():
    data = _body()

    pickup = (data.get("pickup") or "").strip()
    dropoff = (data.get("dropoff") or "").strip()
    if not pickup or not dropoff:
        return jsonify({
            "success": False,
            "message": "Both 'pickup' and 'dropoff' are required.",
        }), 400

    pickup_dt = (data.get("pickupDateTime") or "").strip()
    dropoff_dt = (data.get("dropoffDateTime") or "").strip()
    if not pickup_dt or not dropoff_dt:
        return jsonify({
            "success": False,
            "message": "Both 'pickupDateTime' and 'dropoffDateTime' are required.",
        }), 400

    try:
        from datetime import datetime
        pickup_parsed = datetime.fromisoformat(pickup_dt.replace("Z", "+00:00"))
        dropoff_parsed = datetime.fromisoformat(dropoff_dt.replace("Z", "+00:00"))
    except ValueError:
        return jsonify({
            "success": False,
            "message": "Dates must be ISO 8601 date-times (e.g. 2026-10-01T10:00:00).",
        }), 400

    if dropoff_parsed <= pickup_parsed:
        return jsonify({
            "success": False,
            "message": "Drop-off must be after pick-up.",
        }), 400

    try:
        driver_age = int(data.get("driverAge") or 30)
    except (TypeError, ValueError):
        return jsonify({
            "success": False,
            "message": "Driver age must be a whole number.",
        }), 400
    if driver_age < 18 or driver_age > 75:
        return jsonify({
            "success": False,
            "message": "Driver age must be between 18 and 75.",
        }), 400

    try:
        results = search_cars(
            pickup=pickup,
            dropoff=dropoff,
            pickup_datetime=pickup_parsed.isoformat(),
            dropoff_datetime=dropoff_parsed.isoformat(),
            driver_age=driver_age,
        )
    except DuffelError as error:
        return _db_error_response(error)

    return jsonify({
        "success": True,
        "message": "Car search results (premium).",
        "results": results,
    }), 200
