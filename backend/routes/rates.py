import logging
import time

import requests
from flask import Blueprint, jsonify, request

logger = logging.getLogger(__name__)


rates_bp = Blueprint(
    "rates",
    __name__,
    url_prefix="/api/rates",
)


# ============================================================
# SUPPORTED CURRENCIES
# ============================================================
#
# Every currency the user can pick as `preferredCurrency` (kept in sync
# with `VALID_CURRENCIES` in routes/auth.py). The live provider below
# (Frankfurter, which publishes ECB reference rates) covers most of them,
# but it does NOT quote AED or the CFA franc, so those two use fixed
# approximations (AED is pegged to USD; XOF is pegged to EUR).

LIVE_CURRENCIES = [
    "EUR",
    "GBP",
    "JPY",
    "CHF",
    "CAD",
    "AUD",
    "INR",
]

# Static approximate USD -> local rate for currencies the live provider
# (ECB/Frankfurter) does not quote.
STATIC_USD_RATES = {
    "AED": 3.6725,   # UAE dirham, pegged to USD since 1997.
    "CFA": 590.0,    # XOF/CFA franc, approximate (pegged to EUR at 655.957).
}

_CACHE_TTL_SECONDS = 6 * 60 * 60  # 6 hours

_cache = {
    "usd_rates": None,
    "fetched_at": None,
}


# ============================================================
# RATE PROVISION
# ============================================================

def _fetch_live_usd_rates():
    """Fetch live USD -> {currency} rates from Frankfurter (ECB data).

    Returns a dict of the currencies in LIVE_CURRENCIES, or raises on
    failure so callers can fall back to the cache / static rates.
    """
    symbols = ",".join(LIVE_CURRENCIES)

    response = requests.get(
        "https://api.frankfurter.app/latest",
        params={"base": "USD", "symbols": symbols},
        timeout=8,
    )

    if response.status_code != 200:
        raise RuntimeError(
            "Currency provider returned HTTP %s" % response.status_code
        )

    data = response.json()

    rates = data.get("rates")

    if not isinstance(rates, dict):
        raise RuntimeError("Currency provider returned invalid data")

    result = {
        "USD": 1.0,
    }

    for code in LIVE_CURRENCIES:
        value = rates.get(code)
        numeric = (
            float(value) if isinstance(value, (int, float)) else None
        )
        if numeric is None or numeric <= 0:
            raise RuntimeError(
                "Currency provider returned invalid rate for %s" % code
            )
        result[code] = numeric

    return result


def get_usd_rates(force_refresh=False):
    """Return a map {currency_code: units per 1 USD} for every supported
    currency, or raise if no rate data is available at all.

    Uses an in-memory 6-hour cache. When the live provider fails we keep
    serving the last good snapshot (stale-while-error); AED/CFA never go
    stale because they come from the static table.
    """
    now = time.time()

    cached = _cache["usd_rates"]
    fetched_at = _cache["fetched_at"]

    if (
        not force_refresh
        and cached is not None
        and fetched_at is not None
        and (now - fetched_at) < _CACHE_TTL_SECONDS
    ):
        return dict(cached)

    if force_refresh or cached is None:
        try:
            live = _fetch_live_usd_rates()
        except Exception as error:
            logger.warning(
                "Live currency rates unavailable: %s", error
            )
            if cached is not None:
                # Serve the last good snapshot instead of failing.
                return dict(cached)
            raise

        _cache["usd_rates"] = live
        _cache["fetched_at"] = now
        return dict(live)

    # Cache is fresh from a previous run of this process.
    return dict(cached)


def build_full_usd_map():
    """Combine live/static rates into one {currency: rate_per_usd} map."""
    merged = dict(STATIC_USD_RATES)

    for code, rate in get_usd_rates().items():
        merged[code] = rate

    return merged


def convert_from_usd(amount, currency):
    """Convert a USD amount into ``currency``.

    Returns the converted float. Raises when no rate data can reach
    ``currency`` so callers can decide how to degrade gracefully.
    """
    rates = build_full_usd_map()

    rate = rates.get(currency)

    if rate is None or rate <= 0:
        raise ValueError(
            "No conversion rate available for %s" % currency
        )

    return round(float(amount) * rate, 2)


def convert_cost_from_usd(cost, currency):
    """Return ``cost`` (from cost_service, priced in USD) converted into
    ``currency``.

    If the target currency is USD, or no rate data is available, the cost
    is returned unchanged so trip generation never fails because of a
    conversion hiccup.
    """
    if currency is None or currency == "USD":
        return cost

    try:
        converted_total = convert_from_usd(cost["estimatedTotal"], currency)
    except (ValueError, KeyError, TypeError):
        logger.warning(
            "Cost conversion to %s unavailable; keeping USD", currency
        )
        return cost

    breakdown = cost.get("breakdown") or {}

    converted_cost = dict(cost)
    converted_cost["currency"] = currency
    converted_cost["estimatedTotal"] = converted_total

    converted_breakdown = {}
    for key in ("accommodation", "food", "transportation", "activities"):
        value = breakdown.get(key)
        try:
            converted_breakdown[key] = convert_from_usd(value, currency)
        except (ValueError, KeyError, TypeError):
            converted_breakdown[key] = value

    converted_cost["breakdown"] = converted_breakdown

    return converted_cost


# ============================================================
# ENDPOINT
# GET /api/rates/base/<currency>
# ============================================================

@rates_bp.route("/base/<string:base_currency>", methods=["GET"])
def get_rates(base_currency):

    base = str(base_currency).strip().upper()

    try:
        usd_rates = build_full_usd_map()
    except Exception as error:
        logger.exception("No currency rates available")
        return jsonify({
            "success": False,
            "message": "Currency conversion is temporarily unavailable.",
        }), 503

    base_rate = usd_rates.get(base)

    if base_rate is None:
        return jsonify({
            "success": False,
            "message": "Currency is not supported.",
        }), 400

    # Convert the USD-based table into rates relative to the requested base.
    rates = {
        code: round(rate / base_rate, 6)
        for code, rate in usd_rates.items()
    }

    return jsonify({
        "success": True,
        "base": base,
        "rates": rates,
    }), 200


# ============================================================
# FALLBACK (FILTERED) ENDPOINT
# GET /api/rates/bridge?from=USD&to=EUR
# ============================================================

@rates_bp.route("/bridge", methods=["GET"])
def get_single_rate():

    from_code = str(request.args.get("from", "USD")).strip().upper()
    to_code = str(request.args.get("to", "")).strip().upper()

    if not to_code:
        return jsonify({
            "success": False,
            "message": "A 'to' currency is required.",
        }), 400

    try:
        usd_rates = build_full_usd_map()
    except Exception as error:
        logger.exception("No currency rates available")
        return jsonify({
            "success": False,
            "message": "Currency conversion is temporarily unavailable.",
        }), 503

    from_rate = usd_rates.get(from_code)
    to_rate = usd_rates.get(to_code)

    if from_rate is None or to_rate is None:
        return jsonify({
            "success": False,
            "message": "Currency is not supported.",
        }), 400

    return jsonify({
        "success": True,
        "from": from_code,
        "to": to_code,
        "rate": round(to_rate / from_rate, 6),
    }), 200