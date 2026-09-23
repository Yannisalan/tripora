import logging
import time
from datetime import date
from decimal import Decimal, InvalidOperation

from flask import Blueprint, jsonify, request
from flask_jwt_extended import (
    get_jwt_identity,
    jwt_required,
)
from sqlalchemy.orm.attributes import flag_modified

from config.database import db
from models.trip import Trip
from models.user import User
from routes.auth import VALID_CURRENCIES, VALID_LANGUAGES
from routes.rates import convert_cost_from_usd
from routes.weather import get_forecast_for_generation
from services.cost_service import calculate_trip_cost
from services.itinerary_service import (
    AIBusyError,
    GENERATION_BUDGET_SECONDS,
    SWAP_BUDGET_SECONDS,
    _validate_swap_activity,
    generate_activity_swap,
    generate_itinerary,
)

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
    budget_amount = data.get("budgetAmount")

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

    if budget_amount is not None:
        try:
            budget_amount = Decimal(str(budget_amount))
            if not budget_amount.is_finite() or budget_amount <= 0:
                raise InvalidOperation
            budget_amount = budget_amount.quantize(Decimal("0.01"))
        except (InvalidOperation, TypeError):
            raise ValueError(
                "Budget amount must be a positive number."
            ) from None

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
        "budget_amount": budget_amount,
        "travel_style": travel_style,
        "interests": interests,
    }


def _get_user_preferences(user_id):
    """Return the user's preferred (language, currency).

    Offline preferences sync from PATCH /api/auth/me; trip generation
    falls back gracefully to the defaults when the user has none set.
    """
    user = db.session.get(User, user_id)

    language = (user.preferred_language if user is not None else "") or "en"
    currency = (user.preferred_currency if user is not None else "") or "USD"

    if language not in VALID_LANGUAGES:
        language = "en"

    if currency not in VALID_CURRENCIES:
        currency = "USD"

    return language, currency


def _build_cost(payload, currency="USD"):
    cost = calculate_trip_cost(
        destination=payload["destination"],
        start_date=payload["start_date"],
        end_date=payload["end_date"],
        travelers=payload["travelers"],
        budget=payload["budget"],
    )

    return convert_cost_from_usd(cost, currency)


def _build_itinerary(payload, language="en", trip_id=None, deadline=None):
    if deadline is None:
        deadline = time.monotonic() + GENERATION_BUDGET_SECONDS

    weather = []
    try:
        weather_start = (
            payload["start_date_obj"]
            if "start_date_obj" in payload
            else date.fromisoformat(payload["start_date"][:10])
        )
        weather_end = (
            payload["end_date_obj"]
            if "end_date_obj" in payload
            else date.fromisoformat(payload["end_date"][:10])
        )
        weather = get_forecast_for_generation(
            payload["destination"],
            weather_start,
            weather_end,
            trip_id=trip_id,
        )
    except Exception:
        logger.exception("Skipping weather enrichment for itinerary")

    itinerary = generate_itinerary(
        destination=payload["destination"],
        start_date=payload["start_date"],
        end_date=payload["end_date"],
        travelers=payload["travelers"],
        budget=payload["budget"],
        travel_style=payload["travel_style"],
        interests=payload["interests"],
        language=language,
        weather=weather,
        deadline=deadline,
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

        "budgetAmount": (
            float(trip.budget_amount)
            if trip.budget_amount is not None
            else None
        ),

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

    # --------------------------------------------------------
    # RESOLVE USER PREFERENCES
    # --------------------------------------------------------

    preferred_language, preferred_currency = _get_user_preferences(user_id)

    # The client can override the saved account preferences for this
    # request (used when the app re-syncs after a preference change).
    request_language = (
        str(data.get("preferredLanguage") or "").strip().lower()
        if isinstance(data, dict)
        else ""
    )
    request_currency = (
        str(data.get("preferredCurrency") or "").strip().upper()
        if isinstance(data, dict)
        else ""
    )

    if request_language:
        if request_language not in VALID_LANGUAGES:
            return jsonify({
                "success": False,
                "message": "Language is invalid.",
            }), 400
        preferred_language = request_language

    if request_currency:
        if request_currency not in VALID_CURRENCIES:
            return jsonify({
                "success": False,
                "message": "Currency is invalid.",
            }), 400
        preferred_currency = request_currency

    # ========================================================
    # CALCULATE ESTIMATED COST
    # ========================================================

    try:

        cost = _build_cost(payload, currency=preferred_currency)

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

    # Hard deadline for the whole generate request (weather + Gemini +
    # parsing), kept comfortably below the client's 60s request timeout.
    deadline = time.monotonic() + GENERATION_BUDGET_SECONDS

    try:

        generated_itinerary = _build_itinerary(
            payload,
            language=preferred_language,
            deadline=deadline,
        )

        logger.info("AI itinerary generated successfully for user: %s", user_id)

    except AIBusyError as error:

        logger.warning("AI busy for user %s: %s", user_id, error)

        return jsonify({
            "error": "ai_busy",
            "message": "The AI is busy right now, please try again in a minute.",
        }), 503

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

    # Never persist a trip once the time budget has expired: the client has
    # already given up, so saving here would only create an orphan trip (and
    # a duplicate on retry).
    if time.monotonic() >= deadline:
        logger.warning(
            "Skipping save for user %s: time budget expired.", user_id
        )
        return jsonify({
            "error": "ai_busy",
            "message": "The AI is busy right now, please try again in a minute.",
        }), 503

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

            budget_amount=payload["budget_amount"],

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
    except ValueError as error:
        return jsonify({
            "success": False,
            "message": str(error),
        }), 400

    preferred_language, preferred_currency = _get_user_preferences(user_id)

    try:
        cost = _build_cost(payload, currency=preferred_currency)
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
        trip.budget_amount = payload["budget_amount"]
        trip.travel_style = payload["travel_style"]
        trip.interests = payload["interests"]
        trip.estimated_cost = cost

        if dates_changed:
            trip.itinerary = _build_itinerary(
                payload,
                language=preferred_language,
                trip_id=trip_id,
                deadline=time.monotonic() + GENERATION_BUDGET_SECONDS,
            )

        db.session.commit()

        return jsonify({
            "success": True,
            "message": "Trip updated successfully.",
            "trip": trip_to_dict(trip),
        }), 200

    except AIBusyError as error:
        db.session.rollback()
        logger.warning("AI busy updating trip %s: %s", trip_id, error)
        return jsonify({
            "error": "ai_busy",
            "message": "The AI is busy right now, please try again in a minute.",
        }), 503

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

        preferred_language, _ = _get_user_preferences(user_id)

        payload = {
            "destination": trip.destination,
            "start_date": trip.start_date.isoformat(),
            "end_date": trip.end_date.isoformat(),
            "travelers": trip.travelers,
            "budget": trip.budget,
            "travel_style": trip.travel_style,
            "interests": trip.interests or [],
        }

        trip.itinerary = _build_itinerary(
            payload,
            language=preferred_language,
            trip_id=trip_id,
            deadline=time.monotonic() + GENERATION_BUDGET_SECONDS,
        )

        db.session.commit()

        return jsonify({
            "success": True,
            "message": "Itinerary regenerated successfully.",
            "trip": trip_to_dict(trip),
        }), 200

    except AIBusyError as error:
        db.session.rollback()
        logger.warning("AI busy regenerating trip %s: %s", trip_id, error)
        return jsonify({
            "error": "ai_busy",
            "message": "The AI is busy right now, please try again in a minute.",
        }), 503

    except Exception as error:
        db.session.rollback()
        logger.exception("Regenerating itinerary failed")
        return jsonify({
            "success": False,
            "message": "Failed to regenerate itinerary.",
            "error": "Internal server error.",
        }), 500


# ============================================================
# SWAP A SINGLE ACTIVITY
# POST /api/trips/<trip_id>/swap-activity
# ============================================================

@trips_bp.route("/<int:trip_id>/swap-activity", methods=["POST"])
@jwt_required()
def swap_activity(trip_id):
    try:
        user_id = _get_authenticated_user_id()
    except ValueError as error:
        return jsonify({
            "success": False,
            "message": str(error),
        }), 401

    data = request.get_json(silent=True)

    if not isinstance(data, dict):
        return jsonify({
            "success": False,
            "message": "No activity data provided.",
        }), 400

    day_number = data.get("day")
    time_slot = data.get("time")

    if not isinstance(day_number, int) or day_number <= 0:
        return jsonify({
            "success": False,
            "message": "A valid day number is required.",
        }), 400

    if time_slot not in (
        "Morning",
        "Afternoon",
        "Evening",
    ):
        return jsonify({
            "success": False,
            "message": "Time slot must be Morning, Afternoon or Evening.",
        }), 400

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

        itinerary = trip.itinerary or []

        if not isinstance(itinerary, list):
            raise ValueError("Trip itinerary is corrupt.")

        target_day = next(
            (
                day
                for day in itinerary
                if isinstance(day, dict)
                and day.get("day") == day_number
            ),
            None,
        )

        if target_day is None:
            return jsonify({
                "success": False,
                "message": "Itinerary day not found.",
            }), 404

        activities = target_day.get("activities")

        if not isinstance(activities, list):
            raise ValueError("Trip itinerary is corrupt.")

        target_index = next(
            (
                index
                for index, activity in enumerate(activities)
                if isinstance(activity, dict)
                and activity.get("time") == time_slot
            ),
            None,
        )

        if target_index is None:
            return jsonify({
                "success": False,
                "message": "Activity slot not found.",
            }), 404

        current_activity = activities[target_index]

        # Every title elsewhere in the trip, so a replacement can never
        # duplicate an existing activity. Identity compares against the
        # activity being replaced (dicts would compare equal to a copy).
        existing_titles = []
        for day in itinerary:
            if not isinstance(day, dict):
                continue
            day_activities = day.get("activities")
            if not isinstance(day_activities, list):
                continue
            for activity in day_activities:
                if not isinstance(activity, dict):
                    continue
                if activity is current_activity:
                    continue
                title = str(activity.get("title") or "").strip()
                if title:
                    existing_titles.append(title)

        preferred_language, preferred_currency = _get_user_preferences(user_id)

        # Best-effort: reuse the Task 1 forecast helper for this day's
        # weather. An unavailable forecast means the model simply gets no
        # weather guidance for the swap.
        day_weather = []
        day_date = str(target_day.get("date") or "")
        forecast = get_forecast_for_generation(
            trip.destination,
            trip.start_date,
            trip.end_date,
            trip_id=trip.id,
        )
        for entry in forecast:
            if isinstance(entry, dict) and entry.get("date") == day_date:
                day_weather = [entry]
                break

        replacement = generate_activity_swap(
            destination=trip.destination,
            day_number=day_number,
            day_date=day_date,
            time_slot=time_slot,
            current_activity=current_activity,
            day_activities=activities,
            existing_titles=existing_titles,
            travelers=trip.travelers,
            budget=trip.budget,
            travel_style=trip.travel_style,
            interests=trip.interests or [],
            language=preferred_language,
            day_weather=day_weather,
            deadline=time.monotonic() + SWAP_BUDGET_SECONDS,
        )

        # Server-side safety net before the trip is touched.
        _validate_swap_activity(
            replacement,
            time_slot,
            existing_titles,
        )

        # Reassign the whole itinerary so the JSON column change is tracked
        # by SQLAlchemy (in-place list mutation is not detected on commit).
        activities_copy = list(activities)
        activities_copy[target_index] = replacement
        day_copy = dict(target_day)
        day_copy["activities"] = activities_copy
        trip.itinerary = [
            day_copy if day is target_day else day
            for day in itinerary
        ]

        # Mark the column modified explicitly: plain JSON attribute
        # reassignment can be treated as a no-op by SQLAlchemy's history
        # tracking (old/new compare by value), silently dropping the update.
        flag_modified(trip, "itinerary")

        # Refresh the derived estimate so the returned trip stays
        # consistent with generate/update (the figure itself is
        # itinerary-independent, but it is recomputed through the same
        # path).
        trip.estimated_cost = _build_cost(
            {
                "destination": trip.destination,
                "start_date": trip.start_date.isoformat(),
                "end_date": trip.end_date.isoformat(),
                "travelers": trip.travelers,
                "budget": trip.budget,
            },
            currency=preferred_currency,
        )
        flag_modified(trip, "estimated_cost")

        db.session.commit()

        return jsonify({
            "success": True,
            "message": "Activity swapped successfully.",
            "trip": trip_to_dict(trip),
        }), 200

    except AIBusyError as error:
        db.session.rollback()
        logger.warning("AI busy swapping activity on trip %s: %s", trip_id, error)
        return jsonify({
            "error": "ai_busy",
            "message": "The AI is busy right now, please try again in a minute.",
        }), 503

    except RuntimeError as error:
        db.session.rollback()
        logger.error("Activity swap generation failed: %s", error)
        return jsonify({
            "success": False,
            "message": str(error),
            "error": "Internal server error.",
        }), 500

    except Exception as error:
        db.session.rollback()
        logger.exception("Swapping activity failed")
        return jsonify({
            "success": False,
            "message": "Failed to swap activity.",
            "error": "Internal server error.",
        }), 500
