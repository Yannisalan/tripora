"""Subscription entitlement helpers and the premium-gating decorator.

``require_premium`` protects premium routes by looking up the authenticated
user's subscription and rejecting the request with HTTP 403 when they are not
actively subscribed. Enforcement is always server-side: the client flag is
only a UI convenience, never trusted for gating.
"""

import functools
import logging

from flask import jsonify
from flask_jwt_extended import get_jwt_identity

from config.database import db
from models.subscription import Subscription
from models.user import User
from services.pricing_service import tier_for_country, tier_price

logger = logging.getLogger(__name__)

# Statuses that grant entitlement (in addition to an un-expired window).
ACTIVE_STATUSES = {"active", "trialing"}


def is_premium(subscription):
    """Return True if a Subscription (or None) grants premium access."""
    if subscription is None:
        return False
    if subscription.status not in ACTIVE_STATUSES:
        return False
    return subscription.is_active


def get_premium_requirement_response():
    """Build the (message, status) pair returned for a non-premium request."""
    return (
        jsonify({
            "success": False,
            "message": (
                "This feature is part of the Tripora premium subscription. "
                "Please upgrade to continue."
            ),
            "error": "premium_required",
            "code": "PREMIUM_REQUIRED",
        }),
        403,
    )


def require_premium(func):
    """Decorator: allow only authenticated, actively-subscribed users.

    Assumes the decorated view is JWT-protected (via ``@jwt_required()``) and
    reads the user id from the JWT identity. Returns 403 (never 401) when the
    user is not subscribed, so the client can route non-subscribers to the
    paywall.
    """

    @functools.wraps(func)
    def wrapper(*args, **kwargs):
        user_id = get_jwt_identity()
        try:
            user_id = int(user_id)
        except (TypeError, ValueError):
            resp, _ = get_premium_requirement_response()
            return resp, 403

        user = db.session.get(User, user_id)
        if user is None:
            resp, _ = get_premium_requirement_response()
            return resp, 403

        if not is_premium(user.subscription):
            resp, _ = get_premium_requirement_response()
            return resp, 403

        return func(*args, **kwargs)

    return wrapper


def get_subscription_status(user):
    """Return the serializable premium status dict for a user.

    Always resolves the region tier so the paywall can show the correct price
    even for free users.
    """
    sub = user.subscription
    active = is_premium(sub)
    tier = (sub.tier if sub and sub.tier else tier_for_country(user.region_country))

    return {
        "isPremium": active,
        "tier": tier,
        "tierLabel": tier_price(tier)["label"],
        "price": tier_price(tier)["price"],
        "currency": tier_price(tier)["currency"],
        "period": sub.period if sub else "monthly",
        "activeUntil": sub.active_until.isoformat() if sub and sub.active_until else None,
        "store": sub.store if sub else None,
    }
