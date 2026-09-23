"""Tests for the AI generation time-budget / retry policy.

The backend must always answer within a short budget (well under the
client's 60s timeout), retry a transient Gemini failure only a few times,
never retry a permanent error, and never persist a trip after it has
already given up (which would leave an orphan/duplicate).
"""

import json
import time
from datetime import date, timedelta

import pytest

import routes.trips as trips_module
import services.itinerary_service as itinerary_service
from models.trip import Trip

from .helpers import (
    create_logged_in_user,
    create_trip,
    get_user_by_email,
)


# ----------------------------------------------------------------------
# Fakes
# ----------------------------------------------------------------------


class _FakeResponse:
    def __init__(self, text):
        self.text = text


class _FakeModels:
    def __init__(self, handler):
        self._handler = handler
        self.calls = []

    def generate_content(self, model=None, contents=None, config=None):
        self.calls.append((model, config))
        return self._handler(len(self.calls))


class _FakeClient:
    def __init__(self, handler):
        self.models = _FakeModels(handler)


class _ExpiredClock:
    """Clock whose first reading starts the budget and whose next reading
    is already past the deadline."""

    def __init__(self):
        self.calls = 0

    def monotonic(self):
        self.calls += 1
        return 1000.0 if self.calls == 1 else 2000.0


def _raise_transient():
    raise Exception("503 UNAVAILABLE: The model is overloaded.")


def _raise_timeout():
    raise TimeoutError("request timed out")


def _raise_permanent():
    raise Exception("400 INVALID_ARGUMENT: bad request")


def _valid_itinerary_text(days=3):
    """A minimal itinerary that passes ``_validate_itinerary``.

    Covers the ``culture``/``food``/``sightseeing`` categories, uses unique
    titles across the trip, and names a non-empty location per activity.
    """
    start = date(2026, 9, 1)
    categories = ["Culture", "Food", "Sightseeing"]
    itinerary = []
    for i in range(days):
        day_date = start + timedelta(days=i)
        activities = []
        for j, slot in enumerate(["Morning", "Afternoon", "Evening"]):
            activities.append(
                {
                    "time": slot,
                    "title": "Unique {} spot {}-{}".format(slot, i + 1, j + 1),
                    "description": "Test description",
                    "category": categories[j % len(categories)],
                    "location": "District {}-{}".format(i + 1, j + 1),
                }
            )
        itinerary.append(
            {
                "day": i + 1,
                "title": "Day {}".format(i + 1),
                "date": day_date.isoformat(),
                "activities": activities,
            }
        )
    return json.dumps({"itinerary": itinerary})


def _generate(deadline_seconds=50.0):
    return itinerary_service.generate_itinerary(
        destination="Paris",
        start_date="2026-09-01",
        end_date="2026-09-03",
        travelers=2,
        budget="moderate",
        travel_style="balanced",
        interests=["culture", "food", "sightseeing"],
        language="en",
        weather=(),
        deadline=time.monotonic() + deadline_seconds,
    )


# ----------------------------------------------------------------------
# Service-level retry / timeout policy
# ----------------------------------------------------------------------


class TestRetryPolicy:
    def test_all_transient_raises_ai_busy_after_three_attempts(self, monkeypatch):
        fake = _FakeClient(lambda n: _raise_transient())
        monkeypatch.setattr(itinerary_service, "client", fake)
        monkeypatch.setattr(itinerary_service.time, "sleep", lambda *a, **k: None)

        with pytest.raises(itinerary_service.AIBusyError):
            _generate()

        # Capped at three tries, never the old eight.
        assert len(fake.models.calls) == 3

    def test_first_transient_then_success(self, monkeypatch):
        def handler(n):
            if n == 1:
                raise Exception("503 UNAVAILABLE: The model is overloaded.")
            return _FakeResponse(_valid_itinerary_text())

        fake = _FakeClient(handler)
        monkeypatch.setattr(itinerary_service, "client", fake)
        monkeypatch.setattr(itinerary_service.time, "sleep", lambda *a, **k: None)

        result = _generate()

        assert result["itinerary"][0]["day"] == 1
        assert len(fake.models.calls) == 2

    def test_client_timeout_is_transient_and_per_attempt_timeout_is_set(
        self, monkeypatch
    ):
        def handler(n):
            if n == 1:
                raise TimeoutError("request timed out")
            return _FakeResponse(_valid_itinerary_text())

        fake = _FakeClient(handler)
        monkeypatch.setattr(itinerary_service, "client", fake)
        monkeypatch.setattr(itinerary_service.time, "sleep", lambda *a, **k: None)

        result = _generate()

        assert result["itinerary"][0]["day"] == 1
        assert len(fake.models.calls) == 2

        # A per-attempt timeout in milliseconds must reach the SDK config.
        config = fake.models.calls[0][1]
        timeout_ms = config.http_options.timeout
        assert isinstance(timeout_ms, int)
        assert timeout_ms >= itinerary_service.MIN_ATTEMPT_SECONDS * 1000

    def test_permanent_error_is_not_retried(self, monkeypatch):
        fake = _FakeClient(lambda n: _raise_permanent())
        monkeypatch.setattr(itinerary_service, "client", fake)
        monkeypatch.setattr(itinerary_service.time, "sleep", lambda *a, **k: None)

        with pytest.raises(Exception) as excinfo:
            _generate()

        assert not isinstance(excinfo.value, itinerary_service.AIBusyError)
        assert len(fake.models.calls) == 1


# ----------------------------------------------------------------------
# Route-level: AI busy => 503 and nothing saved
# ----------------------------------------------------------------------


class TestGenerateRouteBudget:
    def test_ai_busy_returns_503_and_saves_nothing(self, client, monkeypatch):
        token = create_logged_in_user(
            client, name="BusyUser", email="busy@example.com"
        )

        def boom(*args, **kwargs):
            raise itinerary_service.AIBusyError("AI is busy")

        monkeypatch.setattr(trips_module, "generate_itinerary", boom)

        resp = create_trip(client, token)

        assert resp.status_code == 503, resp.get_json()
        assert resp.get_json()["error"] == "ai_busy"

        user = get_user_by_email("busy@example.com")
        assert Trip.query.filter_by(user_id=user.id).count() == 0

    def test_expired_budget_returns_503_and_saves_nothing(self, client, monkeypatch):
        token = create_logged_in_user(
            client, name="LateUser", email="late@example.com"
        )

        monkeypatch.setattr(trips_module, "time", _ExpiredClock())

        resp = create_trip(client, token)

        assert resp.status_code == 503, resp.get_json()
        assert resp.get_json()["error"] == "ai_busy"

        user = get_user_by_email("late@example.com")
        assert Trip.query.filter_by(user_id=user.id).count() == 0

    def test_successful_generation_saves_exactly_one_trip(self, client, monkeypatch):
        token = create_logged_in_user(
            client, name="OkUser", email="ok@example.com"
        )

        def handler(n):
            if n == 1:
                raise Exception("503 UNAVAILABLE: The model is overloaded.")
            return _FakeResponse(_valid_itinerary_text())

        fake = _FakeClient(handler)
        monkeypatch.setattr(itinerary_service, "client", fake)
        monkeypatch.setattr(itinerary_service.time, "sleep", lambda *a, **k: None)
        monkeypatch.setattr(
            trips_module, "generate_itinerary", itinerary_service.generate_itinerary
        )

        resp = create_trip(
            client,
            token,
            startDate="2026-09-01",
            endDate="2026-09-03",
        )

        assert resp.status_code == 200, resp.get_json()
        assert len(fake.models.calls) == 2

        user = get_user_by_email("ok@example.com")
        assert Trip.query.filter_by(user_id=user.id).count() == 1
