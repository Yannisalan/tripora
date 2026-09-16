import logging
import time
from datetime import date

import requests
from flask import Blueprint, jsonify
from flask_jwt_extended import (
    get_jwt_identity,
    jwt_required,
)

from config.database import db
from models.trip import Trip

logger = logging.getLogger(__name__)

weather_bp = Blueprint(
    "weather",
    __name__,
    url_prefix="/api",
)

# ============================================================
# OPEN-METEO (no API key required)
# ============================================================

_GEOCODING_URL = "https://geocoding-api.open-meteo.com/v1/search"
_FORECAST_URL = "https://api.open-meteo.com/v1/forecast"

# WMO weather code → human label + icon code
_WMO_CODES = {
    0: ("Clear sky", "clear"),
    1: ("Mainly clear", "mostly_clear"),
    2: ("Partly cloudy", "partly_cloudy"),
    3: ("Overcast", "cloudy"),
    45: ("Fog", "fog"),
    48: ("Rime fog", "fog"),
    51: ("Light drizzle", "drizzle"),
    53: ("Moderate drizzle", "drizzle"),
    55: ("Dense drizzle", "drizzle"),
    56: ("Freezing drizzle", "freezing_rain"),
    57: ("Dense freezing drizzle", "freezing_rain"),
    61: ("Slight rain", "rain"),
    63: ("Moderate rain", "rain"),
    65: ("Heavy rain", "rain"),
    66: ("Freezing rain", "freezing_rain"),
    67: ("Heavy freezing rain", "freezing_rain"),
    71: ("Slight snow", "snow"),
    73: ("Moderate snow", "snow"),
    75: ("Heavy snow", "snow"),
    77: ("Snow grains", "snow"),
    80: ("Slight rain showers", "rain"),
    81: ("Moderate rain showers", "rain"),
    82: ("Violent rain showers", "rain"),
    85: ("Slight snow showers", "snow"),
    86: ("Heavy snow showers", "snow"),
    95: ("Thunderstorm", "thunderstorm"),
    96: ("Thunderstorm with hail", "thunderstorm"),
    99: ("Thunderstorm with heavy hail", "thunderstorm"),
}

# ============================================================
# IN-MEMORY CACHE (trip_id → {data, fetched_at})
# ============================================================

_CACHE_TTL_SECONDS = 30 * 60  # 30 minutes
_cache: dict[int, dict] = {}


# ============================================================
# HELPERS
# ============================================================

def _get_owned_trip(trip_id: int, user_id: int):
    return Trip.query.filter_by(id=trip_id, user_id=user_id).first()


def _geocode_destination(destination: str):
    """Return (name, country, lat, lon) or None."""
    try:
        resp = requests.get(
            _GEOCODING_URL,
            params={"name": destination, "count": 1, "language": "en"},
            timeout=8,
        )
        if resp.status_code != 200:
            return None
        results = resp.json().get("results")
        if not results or not isinstance(results, list) or len(results) == 0:
            return None
        r = results[0]
        return (
            r.get("name", destination),
            r.get("country", ""),
            r.get("latitude"),
            r.get("longitude"),
        )
    except Exception as exc:
        logger.warning("Geocoding failed for %r: %s", destination, exc)
        return None


def _fetch_forecast(lat: float, lon: float, start: date, end: date):
    """Fetch daily forecast from Open-Meteo. Returns a list of day dicts."""
    try:
        resp = requests.get(
            _FORECAST_URL,
            params={
                "latitude": lat,
                "longitude": lon,
                "daily": (
                    "weather_code,"
                    "temperature_2m_max,"
                    "temperature_2m_min,"
                    "precipitation_probability_max,"
                    "wind_speed_10m_max"
                ),
                "timezone": "auto",
                "start_date": start.isoformat(),
                "end_date": end.isoformat(),
            },
            timeout=10,
        )
        if resp.status_code != 200:
            logger.warning("Open-Meteo forecast HTTP %s", resp.status_code)
            return None
        data = resp.json()
        daily = data.get("daily")
        if not daily or not isinstance(daily, dict):
            return None
        dates = daily.get("time", [])
        codes = daily.get("weather_code", [])
        tmax = daily.get("temperature_2m_max", [])
        tmin = daily.get("temperature_2m_min", [])
        precip = daily.get("precipitation_probability_max", [])
        wind = daily.get("wind_speed_10m_max", [])
        forecast = []
        n = len(dates)
        for i in range(n):
            code = codes[i] if i < len(codes) else 0
            label, icon = _WMO_CODES.get(code, ("Unknown", "unknown"))
            forecast.append({
                "date": dates[i] if i < len(dates) else None,
                "weatherCode": code,
                "label": label,
                "icon": icon,
                "tempMax": tmax[i] if i < len(tmax) else None,
                "tempMin": tmin[i] if i < len(tmin) else None,
                "precipitationProbability": (
                    precip[i] if i < len(precip) else None
                ),
                "windSpeedMax": wind[i] if i < len(wind) else None,
            })
        return forecast
    except Exception as exc:
        logger.warning("Open-Meteo forecast failed: %s", exc)
        return None


# ============================================================
# ENDPOINT
# GET /api/trips/<trip_id>/weather
# ============================================================

@weather_bp.route(
    "/trips/<int:trip_id>/weather",
    methods=["GET"],
)
@jwt_required()
def get_trip_weather(trip_id: int):
    user_id = get_jwt_identity()
    try:
        user_id = int(user_id)
    except (TypeError, ValueError):
        return jsonify({
            "success": False,
            "message": "Invalid token.",
        }), 401

    trip = _get_owned_trip(trip_id, user_id)
    if trip is None:
        return jsonify({
            "success": False,
            "message": "Trip not found.",
        }), 404

    destination = (trip.destination or "").strip()
    if not destination:
        return jsonify({
            "success": False,
            "message": "This trip has no destination.",
            "available": False,
            "reason": "no_destination",
        }), 200

    if trip.start_date is None or trip.end_date is None:
        return jsonify({
            "success": True,
            "available": False,
            "reason": "missing_dates",
            "message": "Add travel dates to see the weather forecast.",
            "destination": destination,
        }), 200

    today = date.today()
    if trip.end_date < today:
        return jsonify({
            "success": True,
            "available": False,
            "reason": "trip_ended",
            "message": "This trip has already ended.",
            "destination": destination,
        }), 200

    # Check in-memory cache first
    cached = _cache.get(trip_id)
    if (
        cached is not None
        and (time.time() - cached["fetched_at"]) < _CACHE_TTL_SECONDS
    ):
        return jsonify({
            "success": True,
            "available": True,
            "cached": True,
            **cached["data"],
        }), 200

    # Geocode
    geo = _geocode_destination(destination)
    if geo is None:
        return jsonify({
            "success": True,
            "available": False,
            "reason": "geocoding_failed",
            "message": (
                "Weather data is not available for this destination."
            ),
            "destination": destination,
        }), 200

    geo_name, geo_country, lat, lon = geo

    # Forecast — clamp start to today (Open-Meteo won't return past dates)
    forecast_start = max(trip.start_date, today)
    forecast_end = trip.end_date

    forecast = _fetch_forecast(lat, lon, forecast_start, forecast_end)

    if forecast is None:
        return jsonify({
            "success": True,
            "available": False,
            "reason": "forecast_unavailable",
            "message": (
                "Weather forecast is temporarily unavailable."
            ),
            "destination": destination,
        }), 200

    result = {
        "destination": destination,
        "location": {
            "name": geo_name,
            "country": geo_country,
            "latitude": lat,
            "longitude": lon,
        },
        "dates": {
            "start": trip.start_date.isoformat(),
            "end": trip.end_date.isoformat(),
            "forecastStart": forecast_start.isoformat(),
            "forecastEnd": forecast_end.isoformat(),
        },
        "forecast": forecast,
    }

    _cache[trip_id] = {
        "data": result,
        "fetched_at": time.time(),
    }

    return jsonify({
        "success": True,
        "available": True,
        "cached": False,
        **result,
    }), 200
