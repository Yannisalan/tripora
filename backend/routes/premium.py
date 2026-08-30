"""Premium subscription + premium-only feature endpoints.

All premium-only data endpoints are decorated with ``@require_premium`` so
entitlement is enforced server-side. The subscription/pricing endpoints
(below) let the client show the correct regional price and register a valid
store purchase.

NOTE on feature data: flight-price and weather-forecast values below are
deterministic ESTIMATES used to make the feature demonstrable and testable
before paid external providers (e.g. an aviation-data API or a weather API)
have been wired in. Replace the estimator calls with real provider calls when
you add the required third-party credentials.
"""

import logging
from datetime import date, datetime, timedelta

from flask import Blueprint, jsonify, request
from flask_jwt_extended import get_jwt_identity, jwt_required

from config.database import db
from models.subscription import Subscription
from models.user import User
from services.iap_service import IAPError, verify_app_store_receipt, verify_google_subscription
from services.pricing_service import tier_for_country
from services.subscription_service import (
    get_subscription_status,
    is_premium,
    require_premium,
)

logger = logging.getLogger(__name__)


premium_bp = Blueprint(
    "premium",
    __name__,
    url_prefix="/api/premium",
)


def _authenticated_user():
    user_id = get_jwt_identity()
    try:
        user = db.session.get(User, int(user_id))
    except (TypeError, ValueError):
        user = None
    return user


# ============================================================
# SUBSCRIPTION STATUS
# GET /api/premium/status
# ============================================================

@premium_bp.route("/status", methods=["GET"])
@jwt_required()
def status():
    user = _authenticated_user()
    if user is None:
        return jsonify({
            "success": False,
            "message": "User not found.",
        }), 404

    return jsonify({
        "success": True,
        "subscription": get_subscription_status(user),
    }), 200


# ============================================================
# VERIFY + APPLY A STORE PURCHASE
# POST /api/premium/verify-receipt
# ============================================================

@premium_bp.route("/verify-receipt", methods=["POST"])
@jwt_required()
def verify_receipt():
    user = _authenticated_user()
    if user is None:
        return jsonify({
            "success": False,
            "message": "User not found.",
        }), 404

    data = request.get_json(silent=True) or {}
    store = (data.get("store") or "").strip().lower()

    try:
        if store == "appstore":
            receipt_data = data.get("receiptData")
            if not receipt_data:
                return jsonify({
                    "success": False,
                    "message": "Receipt data is required for App Store purchases.",
                }), 400
            verified = verify_app_store_receipt(receipt_data)
        elif store == "googleplay":
            product_id = data.get("productId")
            purchase_token = data.get("purchaseToken")
            if not product_id or not purchase_token:
                return jsonify({
                    "success": False,
                    "message": "Product id and purchase token are required for Google Play.",
                }), 400
            verified = verify_google_subscription(product_id, purchase_token)
        else:
            return jsonify({
                "success": False,
                "message": "Store must be 'appstore' or 'googleplay'.",
            }), 400
    except IAPError as error:
        logger.warning("Purchase verification failed for user %s: %s", user.id, error)
        return jsonify({
            "success": False,
            "message": str(error),
        }), 400

    # Region tier decides which price tier this subscription belongs to.
    tier = tier_for_country(user.region_country)

    sub = user.subscription
    if sub is None:
        sub = Subscription(user_id=user.id)
        db.session.add(sub)

    sub.store = verified["store"]
    sub.store_product_id = verified["product_id"]
    sub.store_transaction_id = verified["transaction_id"]
    sub.tier = tier
    sub.period = "monthly"
    sub.status = "active"
    sub.active_until = verified["active_until"]

    db.session.commit()

    logger.info("Subscription active for user %s until %s", user.id, sub.active_until)

    return jsonify({
        "success": True,
        "message": "Subscription activated.",
        "subscription": get_subscription_status(user),
    }), 200


# ============================================================
# DEV/TEST ACTIVATION
# POST /api/premium/activate
# ============================================================
# NOTE: This is a development/test shortcut so the premium flow can be
# exercised before real store credentials are wired in. It grants a short
# entitlement and MUST be disabled (env PREMIUM_DEV_ACTIVATION=false) in
# production; never expose a client-triggerable grant against paid content.

@premium_bp.route("/activate", methods=["POST"])
@jwt_required()
def dev_activate():
    import os
    if os.getenv("PREMIUM_DEV_ACTIVATION", "true").lower() not in ("1", "true", "yes", "on"):
        return jsonify({
            "success": False,
            "message": "Not available.",
        }), 403

    user = _authenticated_user()
    if user is None:
        return jsonify({
            "success": False,
            "message": "User not found.",
        }), 404

    data = request.get_json(silent=True) or {}
    days = int(data.get("days", 3) or 3)
    days = max(1, min(days, 30))

    tier = tier_for_country(user.region_country)

    sub = user.subscription
    if sub is None:
        sub = Subscription(user_id=user.id)
        db.session.add(sub)

    base = datetime.utcnow()
    if sub.active_until and sub.is_active and sub.active_until > base:
        base = sub.active_until

    sub.store = "dev"
    sub.tier = tier
    sub.period = "monthly"
    sub.status = "active"
    sub.active_until = base + timedelta(days=days)

    db.session.commit()

    logger.info("DEV subscription activated for user %s until %s", user.id, sub.active_until)

    return jsonify({
        "success": True,
        "message": "Premium activated for development/testing.",
        "subscription": get_subscription_status(user),
    }), 200


# ============================================================
# PREMIUM: FLIGHT PRICE CHECK
# GET /api/premium/flights/price
# ============================================================

@premium_bp.route("/flights/price", methods=["GET"])
@jwt_required()
@require_premium
def flight_price():
    from services.pricing_service import normalize_country
    from services.travel_estimate_service import estimate_flight_price

    origin = (request.args.get("from") or "").strip()
    destination = (request.args.get("to") or "").strip()
    travel_date = request.args.get("date")
    passengers = request.args.get("passengers")

    if not origin or not destination:
        return jsonify({
            "success": False,
            "message": "Both 'from' and 'to' airports are required.",
        }), 400

    if len(origin) != 3 or len(destination) != 3:
        return jsonify({
            "success": False,
            "message": "Airport codes must be 3-letter IATA codes.",
        }), 400

    if not travel_date:
        return jsonify({
            "success": False,
            "message": "A travel 'date' is required.",
        }), 400

    try:
        parsed_date = date.fromisoformat(travel_date[:10])
    except ValueError:
        return jsonify({
            "success": False,
            "message": "Date must be an ISO date (YYYY-MM-DD).",
        }), 400

    try:
        passenger_count = int(passengers) if passengers else 1
    except (TypeError, ValueError):
        return jsonify({
            "success": False,
            "message": "Passengers must be a whole number.",
        }), 400

    if passenger_count < 1 or passenger_count > 9:
        return jsonify({
            "success": False,
            "message": "Passengers must be between 1 and 9.",
        }), 400

    estimate = estimate_flight_price(
        origin=origin.upper(),
        destination=destination.upper(),
        travel_date=parsed_date,
        passengers=passenger_count,
    )

    return jsonify({
        "success": True,
        "message": "Estimated flight price (premium).",
        "price": estimate,
    }), 200


# ============================================================
# PREMIUM: DAILY WEATHER FORECAST
# GET /api/premium/weather/forecast
# ============================================================

@premium_bp.route("/weather/forecast", methods=["GET"])
@jwt_required()
@require_premium
def weather_forecast():
    from services.travel_estimate_service import estimate_weather_forecast

    destination = (request.args.get("destination") or "").strip()
    start_date = request.args.get("startDate")
    end_date = request.args.get("endDate")

    if not destination:
        return jsonify({
            "success": False,
            "message": "A 'destination' is required.",
        }), 400

    try:
        start = date.fromisoformat((start_date or "")[:10]) if start_date else date.today()
        end = date.fromisoformat((end_date or "")[:10]) if end_date else start + timedelta(days=5)
    except ValueError:
        return jsonify({
            "success": False,
            "message": "Dates must be ISO dates (YYYY-MM-DD).",
        }), 400

    if end < start:
        return jsonify({
            "success": False,
            "message": "End date cannot be before start date.",
        }), 400
    if (end - start).days > 14:
        return jsonify({
            "success": False,
            "message": "Forecast is limited to 14 days.",
        }), 400

    forecast = estimate_weather_forecast(destination, start, end)

    return jsonify({
        "success": True,
        "message": "Daily weather forecast (premium).",
        "forecast": forecast,
    }), 200
