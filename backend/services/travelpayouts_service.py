"""Live flight-price lookups for a generated trip via Travelpayouts (Aviasales).

This service hits the Travelpayouts "Data Access API" (``/v2/prices/latest``)
which returns real, cached airline prices for a route/date pair. It is open to
any logged-in user -- there is no premium gate on this endpoint. The API token
is read from ``TRAVELPAYOUTS_API_KEY`` at request time (never from the client).

Like the Duffel/IAP services, this module FAILS CLOSED: if the token is not
configured, every lookup raises ``TravelpayoutsError`` and no data is returned.
Response mapping is deliberately defensive so a slightly different payload
degrades to an error rather than crashing the process.
"""

import logging
import os

import requests

logger = logging.getLogger(__name__)

# Travelpayouts Data Access API base URL.
TRAVELPAYOUTS_API_URL = "https://api.travelpayouts.com"

# Short timeout so a slow third-party provider never blocks a request thread
# indefinitely. The route layer catches TravelpayoutsError and maps it to a
# clean 4xx/5xx response.
TRAVELPAYOUTS_TIMEOUT = 20

NOT_CONFIGURED_MESSAGE = (
    "Live flight prices are not configured. Travelpayouts credentials are missing."
)


class TravelpayoutsError(Exception):
    """Raised when a Travelpayouts lookup cannot be completed (fail closed)."""


def _api_token():
    # Trust the canonical name, but also tolerate a trailing newline/space
    # from a copy-paste and a couple of common alternate spellings so a small
    # "not configured" paste doesn't silently disable the feature.
    for name in (
        "TRAVELPAYOUTS_API_KEY",
        "TRAVELPAYOUTS_API_TOKEN",
        "TRAVELPAYOUTS_TOKEN",
        "TRAVELPAYOUTS_KEY",
    ):
        value = (os.getenv(name, "") or "").strip()
        if value:
            return value
    return None


def search_flight_prices(*, origin, destination, depart_date, currency="USD"):
    """Look up real flight prices for a route/date via the prices/latest API.

    ``origin``/``destination`` are IATA *city* codes (3 letters). Returns a
    Tripora-shaped dict with a ``results`` list of normalized prices.
    """
    token = _api_token()
    if not token:
        raise TravelpayoutsError(NOT_CONFIGURED_MESSAGE)

    params = {
        "origin": origin,
        "destination": destination,
        "departure_at": depart_date,
        "currency": currency.lower(),
        "one_way": "true",
        "sorting": "price",
        "limit": 15,
        "page": 1,
    }
    url = TRAVELPAYOUTS_API_URL.rstrip("/") + "/v2/prices/latest"
    try:
        response = requests.get(
            url,
            params=params,
            headers={"X-Access-Token": token, "Accept": "application/json"},
            timeout=TRAVELPAYOUTS_TIMEOUT,
        )
        if response.status_code == 401 or response.status_code == 403:
            raise TravelpayoutsError(
                "Travelpayouts rejected the API credentials."
            )
        response.raise_for_status()
        body = response.json()
    except TravelpayoutsError:
        raise
    except requests.RequestException as error:
        logger.warning("Travelpayouts request failed: %s", error)
        raise TravelpayoutsError("Could not contact the flight price provider.")
    except ValueError:
        raise TravelpayoutsError(
            "The flight price provider returned an invalid response."
        )

    data = body.get("data") if isinstance(body, dict) else None
    if data is None and isinstance(body, dict):
        data = body.get("prices")

    results = []
    for item in _as_list(data):
        if not isinstance(item, dict):
            continue
        parsed = _parse(result := _as_dict(item))
        if parsed is not None:
            results.append(parsed)

    results.sort(
        key=lambda r: (r["price"].get("amount") or 0.0) if isinstance(r["price"], dict) else 0.0
    )

    return {
        "results": results,
        "count": len(results),
        "provider": "travelpayouts",
        "currency": currency,
        "estimated": False,
        "disclaimer": (
            "Prices are live search results for display purposes only. "
            "Tripora does not book or reserve flights."
        ),
    }


def _as_dict(value):
    return value if isinstance(value, dict) else {}


def _as_list(value):
    return value if isinstance(value, list) else []


def _parse(item):
    item = _as_dict(item)
    amount_text = item.get("value") or item.get("price")
    try:
        amount = float(amount_text or 0)
    except (TypeError, ValueError):
        return None

    currency = str(item.get("currency") or "USD")
    try:
        depart = str(item.get("depart_date") or item.get("departure_at") or "")
        depart_iso = (depart or "")[:19]
    except (TypeError, ValueError):
        depart_iso = ""

    return {
        "flightNumber": str(item.get("flight_number") or ""),
        "airline": str(item.get("airline") or ""),
        "departureTime": depart_iso,
        "origin": str(item.get("origin") or ""),
        "destination": str(item.get("destination") or ""),
        "stops": _to_int(item.get("number_of_changes")),
        "price": {"amount": round(amount, 2), "currency": currency},
    }


def _to_int(value):
    try:
        return int(value)
    except (TypeError, ValueError):
        return 0
