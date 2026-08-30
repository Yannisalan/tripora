"""Live travel-search integration with the Duffel API (flights, stays, cars).

Premium-only travel search is proxied through Duffel so Tripora never stores
third-party data and never exposes credentials to the client. The token is
read from ``DUFFEL_API_TOKEN`` at request time (never from the client).

Like the IAP service, this module FAILS CLOSED: if ``DUFFEL_API_TOKEN`` is not
configured, every search raises ``DuffelError`` and no data is returned. This
keeps the backend safe/inert by default until the provider credentials are
wired in at deploy time.

Each ``search_*`` function returns a clean, Tripora-shaped payload (airports,
dates, passenger counts, prices, etc.) that is safe to hand to the Flutter
client. Response mapping is deliberately defensive so a slightly different
Duffel payload degrades to an error rather than crashing the process.
"""

import logging
import os

import requests

logger = logging.getLogger(__name__)

# Duffel REST API base URL.
DUFFEL_API_URL = "https://api.duffel.com"

# A short timeout so a slow third-party provider never blocks a request thread
# indefinitely. The user-facing route layer catches DuffelError and maps it to
# a clean 4xx/5xx response.
DUFFEL_TIMEOUT = 20

DUFFEL_NOT_CONFIGURED_MESSAGE = (
    "Live travel search is not configured. Duffel credentials are missing."
)


class DuffelError(Exception):
    """Raised when a Duffel search cannot be completed (fail closed)."""


def _api_token():
    return os.getenv("DUFFEL_API_TOKEN", "") or None


def _headers():
    token = _api_token()
    if not token:
        raise DuffelError(DUFFEL_NOT_CONFIGURED_MESSAGE)
    return {
        "Authorization": "Bearer " + token,
        "Accept": "application/json",
        "Content-Type": "application/json",
        "Duffel-Version": "v1",
    }


def _post(path, payload):
    """POST JSON to Duffel and return the decoded body (fail closed)."""
    headers = _headers()
    url = DUFFEL_API_URL.rstrip("/") + path
    try:
        response = requests.post(url, json=payload, headers=headers, timeout=DUFFEL_TIMEOUT)
        if response.status_code == 401 or response.status_code == 403:
            raise DuffelError("Duffel rejected the API credentials.")
        response.raise_for_status()
        body = response.json()
    except DuffelError:
        raise
    except requests.RequestException as error:
        logger.warning("Duffel request failed: %s", error)
        raise DuffelError("Could not contact the travel search provider.")
    except ValueError:
        raise DuffelError("The travel search provider returned an invalid response.")
    return body


def _as_dict(value):
    return value if isinstance(value, dict) else {}


def _as_list(value):
    return value if isinstance(value, list) else []


def _get(body, *keys, default=None):
    """Defensively walk a dict/list path returning ``default`` on any miss."""
    current = body
    for key in keys:
        if isinstance(current, dict) and key in current:
            current = current[key]
        else:
            return default
    return current


def _money(obj):
    """Normalize a Duffel money object to {amount (float), currency}."""
    obj = _as_dict(obj)
    try:
        amount = float(obj.get("amount", 0))
    except (TypeError, ValueError):
        amount = 0.0
    return {
        "amount": round(amount, 2),
        "currency": str(obj.get("currency") or "USD"),
    }


def _datetime_iso(value):
    if not value:
        return None
    text = str(value)
    return text[:19]  # drop timezone/RFC3339 offset for a clean ISO stamp


# ============================================================
# FLIGHTS
# ============================================================

def search_flights(*, origin, destination, depart_date, return_date=None,
                   passengers=1, cabin_class=None):
    """Search flights via the Duffel offers API.

    Returns a Tripora-shaped dict with a ``offers`` list of normalized results.
    """
    slices = [{
        "origin": origin,
        "destination": destination,
        "departure_date": depart_date,
    }]
    if return_date:
        slices.append({
            "origin": destination,
            "destination": origin,
            "departure_date": return_date,
        })

    body = _post("/air/offer_requests", {
        "data": {
            "slices": slices,
            "passengers": [
                {"type": "adult"} for _ in range(max(1, passengers))
            ],
            "cabin_class": cabin_class or "economy",
        },
    })
    # Root API resource lives under body["data"]; offers live under
    # data["offers"]. Fall back gracefully if the shape is unexpected.
    data = _get(body, "data", "offers", default=[])
    if not data and isinstance(body, dict) and "offers" in body:
        data = body["offers"]

    offers = []
    for offer in _as_list(data):
        parsed = _parse_flight_offer(offer)
        if parsed is None:
            continue
        offers.append(parsed)

    return {
        "flights": offers,
        "count": len(offers),
        "estimated": False,
        "provider": "duffel",
        "disclaimer": (
            "Fares are live search results for display purposes. "
            "Tripora does not book or reserve travel."
        ),
    }


def _parse_flight_offer(offer):
    offer = _as_dict(offer)
    try:
        price = _money(offer.get("total_amount"))
    except Exception:
        return None

    slices_data = _get(offer, "slices", default=[])
    segments = []
    legs = []
    for idx, sl in enumerate(_as_list(slices_data)):
        sl = _as_dict(sl)
        seg_list = _as_list(_get(sl, "segments", default=[]))
        if not seg_list:
            continue
        first = _as_dict(seg_list[0])
        last = _as_dict(seg_list[-1])
        segments.append({
            "index": idx,
            "stops": max(0, len(seg_list) - 1),
            "departureAirport": _airport(first.get("origin")),
            "departureTime": _datetime_iso(first.get("departing_at")),
            "arrivalAirport": _airport(last.get("destination")),
            "arrivalTime": _datetime_iso(last.get("arriving_at")),
            "durationMinutes": _duration_minutes(sl.get("duration")),
        })
        for seg in seg_list:
            seg = _as_dict(seg)
            carrier = _get(seg, "operating_carrier", default={})
            legs.append({
                "airline": str(_get(carrier, "name", default="")) or str(_get(carrier, "iata_code", default="")),
                "flightNumber": str(seg.get("flight_number") or ""),
                "originAirport": _airport(seg.get("origin")),
                "destinationAirport": _airport(seg.get("destination")),
            })

    # Best-effort airline label from the first leg.
    airline = legs[0]["airline"] if legs else ""

    return {
        "id": str(offer.get("id") or ""),
        "airline": airline,
        "price": price,
        "segments": segments,
        "legs": legs,
    }


def _airport(part):
    part = _as_dict(part)
    return {
        "code": str(part.get("iata_code") or part.get("id") or ""),
        "city": str(part.get("city") or ""),
        "name": str(part.get("name") or ""),
    }


def _duration_minutes(duration):
    """Convert an ISO-8601 duration (e.g. 'PT10H30M') to a minutes int."""
    text = str(duration or "")
    hours = minutes = 0
    digits = ""
    for ch in text:
        if ch.isdigit():
            digits += ch
        else:
            if digits:
                if ch == "H":
                    hours = int(digits)
                elif ch == "M":
                    minutes = int(digits)
                digits = ""
    return hours * 60 + minutes


# ============================================================
# STAYS
# ============================================================

def search_stays(*, location, check_in, check_out, guests=2, rooms=1):
    """Search stays via the Duffel stays API.

    ``location`` accepts a city name; the request is normalized by Duffel.
    Returns a clean list of stay offers.
    """
    payload = {
        "data": {
            "location": {"type": "city", "id": location},
            "check_in_date": check_in,
            "check_out_date": check_out,
            "rooms": max(1, int(rooms)),
            "guests": [{"type": "adult"} for _ in range(max(1, int(guests)))],
        },
    }
    body = _post("/stays/quote_requests", payload)
    data = _get(body, "data", "quotes", default=[])
    if not data and isinstance(body, dict) and "quotes" in body:
        data = body["quotes"]

    stays = []
    for quote in _as_list(data):
        parsed = _parse_stay(quote)
        if parsed is None:
            continue
        stays.append(parsed)

    return {
        "stays": stays,
        "count": len(stays),
        "estimated": False,
        "provider": "duffel",
        "disclaimer": (
            "Stays are live search results for display purposes. "
            "Tripora does not book or reserve accommodation."
        ),
    }


def _parse_stay(quote):
    quote = _as_dict(quote)
    total = _money(quote.get("total_currency_amount"))
    property_ = _get(quote, "property", default={})
    property_ = _as_dict(property_)
    location = _as_dict(property_.get("location") or {})
    coordinates = _as_dict(location.get("coordinates") or {})
    image = _get(quote, "property", "images", default=[]) or []
    return {
        "id": str(quote.get("id") or ""),
        "name": str(property_.get("name") or ""),
        "propertyId": str(property_.get("property_id") or property_.get("id") or ""),
        "city": str(location.get("city") or ""),
        "country": str(location.get("country") or ""),
        "latitude": coordinates.get("latitude"),
        "longitude": coordinates.get("longitude"),
        "price": total,
        "imageUrl": str(image[0].get("url") or "") if image else "",
        "reference": str(quote.get("reference") or ""),
    }


# ============================================================
# CARS
# ============================================================

def search_cars(*, pickup, dropoff, pickup_datetime, dropoff_datetime,
                driver_age=30):
    """Search rental cars via the Duffel cars API.

    ``pickup``/``dropoff`` accept IATA airport codes or city names.
    Returns a clean list of car offers.
    """
    payload = {
        "data": {
            "pickup_datetime": pickup_datetime,
            "dropoff_datetime": dropoff_datetime,
            "pickup_location": {"type": "airport", "id": pickup},
            "dropoff_location": {"type": "airport", "id": dropoff},
            "driver_age": max(18, int(driver_age)),
        },
    }
    body = _post("/cars/quote_requests", payload)
    data = _get(body, "data", "quotes", default=[])
    if not data and isinstance(body, dict) and "quotes" in body:
        data = body["quotes"]

    cars = []
    for quote in _as_list(data):
        parsed = _parse_car(quote)
        if parsed is None:
            continue
        cars.append(parsed)

    return {
        "cars": cars,
        "count": len(cars),
        "estimated": False,
        "provider": "duffel",
        "disclaimer": (
            "Cars are live search results for display purposes. "
            "Tripora does not book or reserve vehicles."
        ),
    }


def _parse_car(quote):
    quote = _as_dict(quote)
    total = _money(quote.get("total_currency_amount"))
    car = _get(quote, "car", default={})
    car = _as_dict(car)
    return {
        "id": str(quote.get("id") or ""),
        "reference": str(quote.get("reference") or ""),
        "name": str(car.get("name") or ""),
        "make": str(car.get("make") or ""),
        "model": str(car.get("model") or ""),
        "carType": str(car.get("car_type") or ""),
        "transmission": str(car.get("transmission") or ""),
        "fuelType": str(car.get("fuel_policy") or ""),
        "imageUrl": str(_get(quote, "car", "image_url", default="") or ""),
        "price": total,
    }
