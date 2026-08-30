"""Deterministic estimators for premium flight-price and weather features.

These are placeholder implementations so the premium endpoints are fully
functional and testable before paid third-party providers are wired in. Each
function returns realistic, self-consistent data derived from simple
heuristics. Replace the bodies with real provider calls (and keep returning
the same shape) when you configure those APIs.

Marks:
  * ``estimate_flight_price`` -> per-passenger fare estimate with basic
    route-distance and seasonality adjustments.
  * ``estimate_weather_forecast`` -> a per-day summary driven by a stable
    pseudo-random seed derived from the destination + date.
"""

import hashlib
from datetime import timedelta

# Rough great-circle distance (km) for a small set of known routes; falls
# back to a hashed pseudo-distance for unknown IATA pairs.
_KNOWN_ROUTES = {
    ("JFK", "LHR"): 5540, ("LHR", "JFK"): 5540,
    ("JFK", "CDG"): 5840, ("CDG", "JFK"): 5840,
    ("LAX", "NRT"): 8770, ("NRT", "LAX"): 8770,
    ("SFO", "SYD"): 11970, ("SYD", "SFO"): 11970,
    ("DXB", "LHR"): 5500, ("LHR", "DXB"): 5500,
    ("SIN", "LHR"): 10890, ("LHR", "SIN"): 10890,
    ("CDG", "FCO"): 1100, ("FCO", "CDG"): 1100,
    ("LHR", "CDG"): 340, ("CDG", "LHR"): 340,
    ("GRU", "MIA"): 6520, ("MIA", "GRU"): 6520,
}

_BASE_FARE_PER_KM = 0.0012

_SEASON_FACTORS = {
    1: 1.15, 2: 1.10, 3: 1.05, 4: 1.05, 5: 1.10, 6: 1.30,
    7: 1.40, 8: 1.35, 9: 1.05, 10: 1.10, 11: 1.05, 12: 1.30,
}

_WEATHER_POOL = [
    {"condition": "Sunny", "icon": "sunny", "temperature": 24, "humidity": 40},
    {"condition": "Partly cloudy", "icon": "partly_cloudy", "temperature": 21, "humidity": 48},
    {"condition": "Cloudy", "icon": "cloudy", "temperature": 17, "humidity": 60},
    {"condition": "Rain", "icon": "rain", "temperature": 14, "humidity": 80},
    {"condition": "Thunderstorm", "icon": "storm", "temperature": 16, "humidity": 85},
    {"condition": "Clear", "icon": "clear", "temperature": 26, "humidity": 35},
]


def _route_distance(origin, destination):
    return _KNOWN_ROUTES.get(
        (origin, destination),
        900 + (int(hashlib.md5(f"{origin}{destination}".encode()).hexdigest(), 16) % 9000),
    )


def estimate_flight_price(origin, destination, travel_date, passengers=1):
    """Return a per-passenger fare estimate and a total.

    Deterministic for a given (route, date, passengers) tuple.
    """
    distance = _route_distance(origin, destination)
    month = travel_date.month

    base = _BASE_FARE_PER_KM * distance
    seasonal = base * _SEASON_FACTORS[month]

    # Booking variability: purely cosmetic, stable per request.
    jitter = 1.0 + ((int(hashlib.md5(
        f"{origin}{destination}{travel_date}".encode()
    ).hexdigest(), 16) % 100) - 50) / 500.0

    per_passenger = round(max(40.0, seasonal * jitter), 2)
    total = round(per_passenger * passengers, 2)

    return {
        "origin": origin,
        "destination": destination,
        "date": travel_date.isoformat(),
        "passengers": passengers,
        "distanceKm": distance,
        "perPassenger": per_passenger,
        "total": total,
        "currency": "USD",
        "estimated": True,
        "disclaimer": (
            "Flight price is an estimate for preview purposes and may not "
            "reflect live fares."
        ),
    }


def estimate_weather_forecast(destination, start_date, end_date):
    """Return a per-day weather summary derived from a stable seed.

    The forecast is deterministic for a given (destination, date) so repeated
    calls return the same data.
    """
    days = []
    current = start_date
    while current <= end_date:
        seed = int(hashlib.md5(
            f"{destination.lower()}{current.isoformat()}".encode()
        ).hexdigest(), 16)
        entry = _WEATHER_POOL[seed % len(_WEATHER_POOL)]
        # Shift temperature slightly by a per-day offset for variety.
        temp_offset = (seed // 7) % 7 - 3
        days.append({
            "date": current.isoformat(),
            "day": current.strftime("%A"),
            "condition": entry["condition"],
            "icon": entry["icon"],
            "temperatureHigh": entry["temperature"] + 2 + temp_offset,
            "temperatureLow": entry["temperature"] - 6 + temp_offset,
            "humidity": max(20, min(100, entry["humidity"] + temp_offset)),
            "precipitationChance": (
                max(0, 20 + (seed % 40)) if entry["condition"] in (
                    "Rain", "Thunderstorm", "Cloudy"
                ) else max(0, (seed % 20))
            ),
        })
        current += timedelta(days=1)

    return {
        "destination": destination,
        "startDate": start_date.isoformat(),
        "endDate": end_date.isoformat(),
        "days": days,
        "estimated": True,
        "disclaimer": (
            "Forecast is an estimate for preview purposes and may not "
            "reflect live conditions."
        ),
    }
