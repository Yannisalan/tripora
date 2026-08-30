import logging
from datetime import date

from flask import Blueprint, jsonify, request
from flask_jwt_extended import (
    get_jwt_identity,
    jwt_required,
)

from config.database import db
from models.trip import Trip
from services.cost_service import calculate_trip_cost
from services.itinerary_service import generate_itinerary

logger = logging.getLogger(__name__)


trips_bp = Blueprint(
    "trips",
    __name__,
    url_prefix="/api/trips",
)


def _get_authenticated_user_id():
    user_id = get_jwt_identity()

    try:
        return int(user_id)
    except (TypeError, ValueError) as error:
        raise ValueError("Invalid authenticated user.") from error


def _parse_trip_payload(data):
    if not data:
        raise ValueError("No trip data provided.")

    destination = data.get("destination")
    start_date = data.get("startDate")
    end_date = data.get("endDate")
    travelers = data.get("travelers")
    budget = data.get("budget")
    travel_style = data.get("travelStyle")
    interests = data.get("interests", [])

    if not destination or not str(destination).strip():
        raise ValueError("Destination is required.")

    if not start_date or not end_date:
        raise ValueError("Start date and end date are required.")

    # Dates must be ISO strings. Rejecting non-string values (e.g. integers
    # like 20260901) prevents them from slipping past fromisoformat (which
    # would parse "20260901" as 2026-09-01) and later crashing the cost
    # service with `int.split`.
    if not isinstance(start_date, str) or not isinstance(end_date, str):
        raise ValueError("Invalid date format.")

    if not isinstance(travelers, int) or travelers <= 0:
        raise ValueError("Travelers must be a positive number.")

    if not isinstance(interests, list):
        raise ValueError("Interests must be a list.")

    if budget is not None and not isinstance(budget, str):
        raise ValueError("Budget must be a text value.")

    try:
        start_date_obj = date.fromisoformat(start_date[:10])
        end_date_obj = date.fromisoformat(end_date[:10])
    except (ValueError, TypeError) as error:
        raise ValueError("Invalid date format.") from error

    if end_date_obj < start_date_obj:
        raise ValueError("End date cannot be before start date.")

    return {
        "destination": str(destination).strip(),
        "start_date": start_date,
        "end_date": end_date,
        "start_date_obj": start_date_obj,
        "end_date_obj": end_date_obj,
        "travelers": travelers,
        "budget": budget,
        "travel_style": travel_style,
        "interests": interests,
    }


def _build_cost(payload):
    return calculate_trip_cost(
        destination=payload["destination"],
        start_date=payload["start_date"],
        end_date=payload["end_date"],
        travelers=payload["travelers"],
        budget=payload["budget"],
    )


def _build_itinerary(payload):
    itinerary = generate_itinerary(
        destination=payload["destination"],
        start_date=payload["start_date"],
        end_date=payload["end_date"],
        travelers=payload["travelers"],
        budget=payload["budget"],
        travel_style=payload["travel_style"],
        interests=payload["interests"],
    )

    if not isinstance(itinerary, dict):
        raise ValueError("AI returned an invalid itinerary.")

    generated_itinerary = itinerary.get("itinerary", [])

    if not isinstance(generated_itinerary, list):
        raise ValueError("AI returned an invalid itinerary format.")

    return generated_itinerary


# ============================================================
# HELPER — CONVERT TRIP TO JSON
# ============================================================

def trip_to_dict(trip):
    return {
        "id": trip.id,

        "destination": trip.destination,

        "startDate": (
            trip.start_date.isoformat()
            if trip.start_date
            else None
        ),

        "endDate": (
            trip.end_date.isoformat()
            if trip.end_date
            else None
        ),

        "travelers": trip.travelers,

        "budget": trip.budget,

        "travelStyle": trip.travel_style,

        "interests": trip.interests or [],

        "estimatedCost": trip.estimated_cost,

        "itinerary": trip.itinerary or [],

        "createdAt": (
            trip.created_at.isoformat()
            if trip.created_at
            else None
        ),
    }


# ============================================================
# GENERATE AND SAVE TRIP
# POST /api/trips/generate
# ============================================================

@trips_bp.route("/generate", methods=["POST"])
@jwt_required()
def generate_trip():

    # --------------------------------------------------------
    # GET LOGGED-IN USER
    # --------------------------------------------------------

    try:
        user_id = _get_authenticated_user_id()
    except ValueError as error:
        return jsonify({
            "success": False,
            "message": str(error),
        }), 401

    logger.info("Generating trip for user: %s", user_id)

    data = request.get_json(silent=True)
    logger.debug("Received trip generation payload: %s", data)

    # --------------------------------------------------------
    # VALIDATE REQUEST
    # --------------------------------------------------------

    try:
        payload = _parse_trip_payload(data)
    except ValueError as error:
        return jsonify({
            "success": False,
            "message": str(error),
        }), 400

    # ========================================================
    # CALCULATE ESTIMATED COST
    # ========================================================

    try:

        cost = _build_cost(payload)

    except ValueError as error:

        logger.warning("Trip cost calculation failed: %s", error)

        return jsonify({
            "success": False,
            "message": str(error),
        }), 400

    except Exception as error:

        logger.exception("Trip cost service failed")

        return jsonify({
            "success": False,
            "message": "Failed to calculate trip cost.",
            "error": "Internal server error.",
        }), 500

    # ========================================================
    # GENERATE AI ITINERARY
    # ========================================================

    try:

        generated_itinerary = _build_itinerary(payload)

        logger.info("AI itinerary generated successfully for user: %s", user_id)

    except Exception as error:

        logger.exception("AI itinerary generation failed")

        return jsonify({
            "success": False,
            "message": "Failed to generate AI itinerary.",
            "error": "Internal server error.",
        }), 500

    # ========================================================
    # SAVE TRIP
    # ========================================================

    try:

        trip = Trip(
            # IMPORTANT
            # Attach trip to logged-in user
            user_id=user_id,

            destination=payload["destination"],

            start_date=payload["start_date_obj"],

            end_date=payload["end_date_obj"],

            travelers=payload["travelers"],

            budget=payload["budget"],

            travel_style=payload["travel_style"],

            interests=payload["interests"],

            itinerary=generated_itinerary,

            estimated_cost=cost,
        )

        db.session.add(trip)

        db.session.commit()

        logger.info("Trip saved successfully: %s (user: %s)", trip.id, trip.user_id)

    except Exception as error:

        db.session.rollback()

        logger.exception("Saving generated trip failed")

        return jsonify({
            "success": False,
            "message": "Failed to save trip to database.",
            "error": "Internal server error.",
        }), 500

    # ========================================================
    # RETURN TRIP
    # ========================================================

    return jsonify({
        "success": True,
        "message": "Trip generated and saved successfully.",
        "trip": trip_to_dict(trip),
    }), 200


# ============================================================
# GET ALL USER'S TRIPS
# GET /api/trips
# ============================================================

@trips_bp.route("", methods=["GET"])
@jwt_required()
def get_trips():

    try:
        user_id = _get_authenticated_user_id()
    except ValueError as error:
        return jsonify({
            "success": False,
            "message": str(error),
        }), 401

    try:

        trips = Trip.query.filter_by(
            user_id=user_id
        ).order_by(
            Trip.created_at.desc()
        ).all()

        trips_data = [
            trip_to_dict(trip)
            for trip in trips
        ]

        return jsonify({
            "success": True,
            "count": len(trips_data),
            "trips": trips_data,
        }), 200

    except Exception as error:

        logger.exception("Retrieving trips failed")

        return jsonify({
            "success": False,
            "message": "Failed to retrieve trips.",
            "error": "Internal server error.",
        }), 500


# ============================================================
# GET SINGLE USER TRIP
# GET /api/trips/<trip_id>
# ============================================================

@trips_bp.route("/<int:trip_id>", methods=["GET"])
@jwt_required()
def get_trip(trip_id):

    try:
        user_id = _get_authenticated_user_id()
    except ValueError as error:
        return jsonify({
            "success": False,
            "message": str(error),
        }), 401

    try:

        trip = Trip.query.filter_by(
            id=trip_id,
            user_id=user_id,
        ).first()

        if trip is None:

            return jsonify({
                "success": False,
                "message": "Trip not found.",
            }), 404

        return jsonify({
            "success": True,
            "trip": trip_to_dict(trip),
        }), 200

    except Exception as error:

        logger.exception("Retrieving single trip failed")

        return jsonify({
            "success": False,
            "message": "Failed to retrieve trip.",
            "error": "Internal server error.",
        }), 500


# ============================================================
# DELETE USER TRIP
# DELETE /api/trips/<trip_id>
# ============================================================

@trips_bp.route("/<int:trip_id>", methods=["DELETE"])
@jwt_required()
def delete_trip(trip_id):

    try:
        user_id = _get_authenticated_user_id()
    except ValueError as error:
        return jsonify({
            "success": False,
            "message": str(error),
        }), 401

    try:

        trip = Trip.query.filter_by(
            id=trip_id,
            user_id=user_id,
        ).first()

        # ----------------------------------------------------
        # TRIP NOT FOUND
        # ----------------------------------------------------

        if trip is None:

            return jsonify({
                "success": False,
                "message": "Trip not found.",
            }), 404

        # ----------------------------------------------------
        # DELETE
        # ----------------------------------------------------

        db.session.delete(trip)

        db.session.commit()

        logger.info("Trip deleted successfully: %s (user: %s)", trip_id, user_id)

        return jsonify({
            "success": True,
            "message": "Trip deleted successfully.",
            "tripId": trip_id,
        }), 200

    except Exception as error:

        db.session.rollback()

        logger.exception("Deleting trip failed")

        return jsonify({
            "success": False,
            "message": "Failed to delete trip.",
            "error": "Internal server error.",
        }), 500


@trips_bp.route("/<int:trip_id>", methods=["PATCH"])
@jwt_required()
def update_trip(trip_id):
    try:
        user_id = _get_authenticated_user_id()
    except ValueError as error:
        return jsonify({
            "success": False,
            "message": str(error),
        }), 401

    data = request.get_json(silent=True)

    try:
        payload = _parse_trip_payload(data)
        cost = _build_cost(payload)
    except ValueError as error:
        return jsonify({
            "success": False,
            "message": str(error),
        }), 400
    except Exception as error:
        logger.exception("Updating trip cost failed")
        return jsonify({
            "success": False,
            "message": "Failed to calculate trip cost.",
            "error": "Internal server error.",
        }), 500

    try:
        trip = Trip.query.filter_by(
            id=trip_id,
            user_id=user_id,
        ).first()

        if trip is None:
            return jsonify({
                "success": False,
                "message": "Trip not found.",
            }), 404

        dates_changed = (
            trip.start_date != payload["start_date_obj"]
            or trip.end_date != payload["end_date_obj"]
        )

        trip.destination = payload["destination"]
        trip.start_date = payload["start_date_obj"]
        trip.end_date = payload["end_date_obj"]
        trip.travelers = payload["travelers"]
        trip.budget = payload["budget"]
        trip.travel_style = payload["travel_style"]
        trip.interests = payload["interests"]
        trip.estimated_cost = cost

        if dates_changed:
            trip.itinerary = _build_itinerary(payload)

        db.session.commit()

        return jsonify({
            "success": True,
            "message": "Trip updated successfully.",
            "trip": trip_to_dict(trip),
        }), 200

    except Exception as error:
        db.session.rollback()
        logger.exception("Updating trip failed")
        return jsonify({
            "success": False,
            "message": "Failed to update trip.",
            "error": "Internal server error.",
        }), 500


@trips_bp.route("/<int:trip_id>/regenerate", methods=["POST"])
@jwt_required()
def regenerate_trip_itinerary(trip_id):
    try:
        user_id = _get_authenticated_user_id()
    except ValueError as error:
        return jsonify({
            "success": False,
            "message": str(error),
        }), 401

    try:
        trip = Trip.query.filter_by(
            id=trip_id,
            user_id=user_id,
        ).first()

        if trip is None:
            return jsonify({
                "success": False,
                "message": "Trip not found.",
            }), 404

        payload = {
            "destination": trip.destination,
            "start_date": trip.start_date.isoformat(),
            "end_date": trip.end_date.isoformat(),
            "travelers": trip.travelers,
            "budget": trip.budget,
            "travel_style": trip.travel_style,
            "interests": trip.interests or [],
        }

        trip.itinerary = _build_itinerary(payload)

        db.session.commit()

        return jsonify({
            "success": True,
            "message": "Itinerary regenerated successfully.",
            "trip": trip_to_dict(trip),
        }), 200

    except Exception as error:
        db.session.rollback()
        logger.exception("Regenerating itinerary failed")
        return jsonify({
            "success": False,
            "message": "Failed to regenerate itinerary.",
            "error": "Internal server error.",
        }), 500
