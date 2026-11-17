"""Mocked tests for the Groq AI integration (no network).

Covers the provider layer of ``services.itinerary_service``: request shape
(strict JSON schema, per-attempt timeout, model order), response parsing,
retry / fallback policy for Groq SDK errors, log safety, and the route
contract when the real generation code runs against a fake Groq client.
"""

import json
import logging
import time
from datetime import date, timedelta

import httpx
import groq
import pytest

import routes.trips as trips_module
import services.itinerary_service as itinerary_service
from models.trip import Trip

from .helpers import (
    auth_headers,
    create_logged_in_user,
    create_trip,
    create_trip_and_get_id,
    get_user_by_email,
)


_URL = "https://api.groq.com/openai/v1/chat/completions"


# ----------------------------------------------------------------------
# Fake Groq client (shape of groq.Groq().chat.completions.create)
# ----------------------------------------------------------------------


class _Message:
    def __init__(self, content):
        self.content = content


class _Choice:
    def __init__(self, content):
        self.message = _Message(content)


class _Completion:
    def __init__(self, content, no_choices=False):
        self.choices = [] if no_choices else [_Choice(content)]


class _Completions:
    def __init__(self, handler):
        self._handler = handler
        self.calls = []

    def create(self, **kwargs):
        self.calls.append(kwargs)
        return self._handler(len(self.calls), kwargs)


class _Chat:
    def __init__(self, handler):
        self.completions = _Completions(handler)


class _FakeGroq:
    def __init__(self, handler):
        self.chat = _Chat(handler)

    @property
    def calls(self):
        return self.chat.completions.calls


def _status_error(cls, status, code=None, extra=None):
    request = httpx.Request("POST", _URL)
    response = httpx.Response(status, request=request)
    body = {"message": "provider error", "type": "error"}
    if code:
        body["code"] = code
    if extra:
        body.update(extra)
    return cls("Error code: {} - {}".format(status, body), response=response, body=body)


def _rate_limit():
    return _status_error(groq.RateLimitError, 429, "rate_limit_exceeded")


def _auth_error():
    return _status_error(groq.AuthenticationError, 401, "invalid_api_key")


def _not_found():
    return _status_error(groq.NotFoundError, 404, "model_not_found")


def _server_error():
    return _status_error(groq.InternalServerError, 503, "service_unavailable")


def _timeout():
    return groq.APITimeoutError(request=httpx.Request("POST", _URL))


def _connection_error():
    return groq.APIConnectionError(request=httpx.Request("POST", _URL))


def _schema_rejected():
    return _status_error(
        groq.BadRequestError,
        400,
        "json_validate_failed",
        extra={"failed_generation": "SECRET-TRIP-DETAILS-IN-FAILED-OUTPUT"},
    )


def _valid_itinerary(days=3, start=date(2026, 9, 1)):
    categories = ["Culture", "Food", "Sightseeing"]
    itinerary = []
    for i in range(days):
        activities = []
        for j, slot in enumerate(["Morning", "Afternoon", "Evening"]):
            activities.append({
                "time": slot,
                "title": "Unique {} spot {}-{}".format(slot, i + 1, j + 1),
                "description": "Test description",
                "category": categories[j],
                "location": "District {}-{}".format(i + 1, j + 1),
            })
        itinerary.append({
            "day": i + 1,
            "title": "Day {}".format(i + 1),
            "date": (start + timedelta(days=i)).isoformat(),
            "activities": activities,
        })
    return json.dumps({"itinerary": itinerary})


def _generate(language="en"):
    return itinerary_service.generate_itinerary(
        destination="Paris",
        start_date="2026-09-01",
        end_date="2026-09-03",
        travelers=2,
        budget="moderate",
        travel_style="balanced",
        interests=["culture", "food", "sightseeing"],
        language=language,
        weather=(),
        deadline=time.monotonic() + 50.0,
    )


def _swap():
    return itinerary_service.generate_activity_swap(
        destination="Paris",
        day_number=1,
        day_date="2026-09-01",
        time_slot="Morning",
        current_activity={
            "time": "Morning",
            "title": "Louvre Visit",
            "description": "Museum",
            "category": "Culture",
            "location": "1st Arrondissement",
        },
        day_activities=[],
        existing_titles=["Louvre Visit"],
        travelers=2,
        budget="moderate",
        travel_style="balanced",
        interests=["culture"],
        language="en",
        day_weather=(),
        deadline=time.monotonic() + 25.0,
    )


_VALID_SWAP = json.dumps({
    "time": "Morning",
    "title": "Musee d'Orsay Visit",
    "description": "Impressionist masterpieces in a former railway station.",
    "category": "Culture",
    "location": "7th Arrondissement",
})


@pytest.fixture
def fake_groq(monkeypatch):
    """Install a fake Groq client; returns a setter for the handler."""

    monkeypatch.setattr(itinerary_service.time, "sleep", lambda *a, **k: None)
    holder = {}

    def install(handler):
        fake = _FakeGroq(handler)
        monkeypatch.setattr(itinerary_service, "client", fake)
        holder["fake"] = fake
        return fake

    return install


# ----------------------------------------------------------------------
# Client configuration and request shape
# ----------------------------------------------------------------------


class TestClientConfiguration:
    def test_real_client_is_groq_with_sdk_retries_disabled(self):
        # The module-level client must be the Groq SDK (not Gemini), and
        # SDK retries must be off so the loop owns the time budget.
        assert isinstance(itinerary_service.client, groq.Groq)
        assert itinerary_service.client.max_retries == 0

    def test_model_order(self):
        assert itinerary_service.GROQ_MODELS == [
            "openai/gpt-oss-120b",
            "openai/gpt-oss-20b",
        ]

    def test_request_uses_strict_json_schema_and_timeout(self, fake_groq):
        fake = fake_groq(lambda n, kw: _Completion(_valid_itinerary()))

        _generate()

        call = fake.calls[0]
        assert call["model"] == "openai/gpt-oss-120b"
        assert call["messages"][0]["role"] == "user"
        assert "TRIP DETAILS" in call["messages"][0]["content"]
        assert call["reasoning_effort"] == "low"
        assert isinstance(call["timeout"], float)
        assert call["timeout"] >= itinerary_service.MIN_ATTEMPT_SECONDS

        fmt = call["response_format"]
        assert fmt["type"] == "json_schema"
        assert fmt["json_schema"]["strict"] is True
        schema = fmt["json_schema"]["schema"]
        # Strict mode: every object closed, every property required.
        day = schema["properties"]["itinerary"]["items"]
        activity = day["properties"]["activities"]["items"]
        for obj in (schema, day, activity):
            assert obj["additionalProperties"] is False
            assert set(obj["required"]) == set(obj["properties"])
        assert activity["properties"]["category"]["enum"] == (
            itinerary_service.ACTIVITY_CATEGORIES
        )
        assert day["properties"]["activities"]["minItems"] == 3
        assert day["properties"]["activities"]["maxItems"] == 3

    def test_swap_request_uses_strict_activity_schema(self, fake_groq):
        fake = fake_groq(lambda n, kw: _Completion(_VALID_SWAP))

        _swap()

        call = fake.calls[0]
        schema = call["response_format"]["json_schema"]["schema"]
        assert schema["additionalProperties"] is False
        assert set(schema["required"]) == {
            "time", "title", "description", "category", "location",
        }
        assert call["timeout"] >= itinerary_service.MIN_ATTEMPT_SECONDS

    def test_french_prompt_carries_language_requirement(self, fake_groq):
        fake = fake_groq(lambda n, kw: _Completion(_valid_itinerary()))

        _generate(language="fr")

        prompt = fake.calls[0]["messages"][0]["content"]
        assert "LANGUAGE REQUIREMENT" in prompt
        assert "French" in prompt


# ----------------------------------------------------------------------
# Response parsing and validation
# ----------------------------------------------------------------------


class TestResponseHandling:
    def test_successful_generation(self, fake_groq):
        fake = fake_groq(lambda n, kw: _Completion(_valid_itinerary()))

        result = _generate()

        assert [d["day"] for d in result["itinerary"]] == [1, 2, 3]
        assert len(fake.calls) == 1

    def test_invalid_json_is_retried_with_correction(self, fake_groq):
        def handler(n, kw):
            return _Completion("{not json" if n == 1 else _valid_itinerary())

        fake = fake_groq(handler)

        result = _generate()

        assert result["itinerary"]
        assert len(fake.calls) == 2
        second_prompt = fake.calls[1]["messages"][0]["content"]
        assert "IMPORTANT CORRECTION FROM PREVIOUS ATTEMPT" in second_prompt
        assert "invalid JSON" in second_prompt

    @pytest.mark.parametrize(
        "empty",
        [
            _Completion(None),
            _Completion(""),
            _Completion("x", no_choices=True),
        ],
        ids=["none-content", "empty-string", "no-choices"],
    )
    def test_empty_responses_exhaust_attempts_as_ai_busy(self, fake_groq, empty):
        fake = fake_groq(lambda n, kw: empty)

        with pytest.raises(itinerary_service.AIBusyError):
            _generate()

        assert len(fake.calls) == 3

    def test_schema_validation_failure_is_retried(self, fake_groq):
        # Parses as JSON but fails _validate_itinerary (2 days for 3).
        def handler(n, kw):
            if n == 1:
                return _Completion(_valid_itinerary(days=2))
            return _Completion(_valid_itinerary())

        fake = fake_groq(handler)

        result = _generate()

        assert len(result["itinerary"]) == 3
        assert len(fake.calls) == 2
        assert "Expected exactly 3 itinerary days" in (
            fake.calls[1]["messages"][0]["content"]
        )

    def test_groq_schema_rejection_is_retried(self, fake_groq):
        def handler(n, kw):
            if n == 1:
                raise _schema_rejected()
            return _Completion(_valid_itinerary())

        fake = fake_groq(handler)

        result = _generate()

        assert result["itinerary"]
        assert len(fake.calls) == 2
        # Same model: a bad generation is not a model failure.
        assert fake.calls[1]["model"] == "openai/gpt-oss-120b"
        assert "did not match the required JSON schema" in (
            fake.calls[1]["messages"][0]["content"]
        )

    def test_swap_success_and_invalid_slot_retry(self, fake_groq):
        wrong_slot = json.dumps({**json.loads(_VALID_SWAP), "time": "Evening"})

        def handler(n, kw):
            return _Completion(wrong_slot if n == 1 else _VALID_SWAP)

        fake = fake_groq(handler)

        activity = _swap()

        assert activity["time"] == "Morning"
        assert activity["title"] == "Musee d'Orsay Visit"
        assert len(fake.calls) == 2


# ----------------------------------------------------------------------
# Provider errors: retry, fallback, permanent failures
# ----------------------------------------------------------------------


class TestProviderErrors:
    def test_rate_limit_is_retried(self, fake_groq):
        def handler(n, kw):
            if n == 1:
                raise _rate_limit()
            return _Completion(_valid_itinerary())

        fake = fake_groq(handler)

        assert _generate()["itinerary"]
        assert len(fake.calls) == 2

    def test_persistent_rate_limit_falls_back_then_ai_busy(self, fake_groq):
        def handler(n, kw):
            raise _rate_limit()

        fake = fake_groq(handler)

        with pytest.raises(itinerary_service.AIBusyError):
            _generate()

        # Limits are per model: the first 429 moves straight to the
        # fallback model; the attempt cap (3) is unchanged.
        models = [c["model"] for c in fake.calls]
        assert models == [
            "openai/gpt-oss-120b",
            "openai/gpt-oss-20b",
            "openai/gpt-oss-20b",
        ]

    def test_invalid_model_falls_back_immediately(self, fake_groq):
        def handler(n, kw):
            if kw["model"] == "openai/gpt-oss-120b":
                raise _not_found()
            return _Completion(_valid_itinerary())

        fake = fake_groq(handler)

        assert _generate()["itinerary"]
        assert [c["model"] for c in fake.calls] == [
            "openai/gpt-oss-120b",
            "openai/gpt-oss-20b",
        ]

    def test_decommissioned_model_code_falls_back(self, fake_groq):
        def handler(n, kw):
            if n == 1:
                raise _status_error(
                    groq.BadRequestError, 400, "model_decommissioned"
                )
            return _Completion(_valid_itinerary())

        fake = fake_groq(handler)

        assert _generate()["itinerary"]
        assert fake.calls[1]["model"] == "openai/gpt-oss-20b"

    @pytest.mark.parametrize(
        "make_error",
        [_timeout, _connection_error, _server_error],
        ids=["timeout", "connection", "server-5xx"],
    )
    def test_transient_errors_are_retried(self, fake_groq, make_error):
        def handler(n, kw):
            if n == 1:
                raise make_error()
            return _Completion(_valid_itinerary())

        fake = fake_groq(handler)

        assert _generate()["itinerary"]
        assert len(fake.calls) == 2

    def test_authentication_error_is_not_retried(self, fake_groq):
        fake = fake_groq(lambda n, kw: (_ for _ in ()).throw(_auth_error()))

        with pytest.raises(groq.AuthenticationError):
            _generate()

        assert len(fake.calls) == 1

    def test_swap_authentication_error_is_not_retried(self, fake_groq):
        fake = fake_groq(lambda n, kw: (_ for _ in ()).throw(_auth_error()))

        with pytest.raises(groq.AuthenticationError):
            _swap()

        assert len(fake.calls) == 1

    def test_rate_limit_then_success_uses_fallback_model(self, fake_groq):
        def handler(n, kw):
            if n == 1:
                raise _rate_limit()
            return _Completion(_valid_itinerary())

        fake = fake_groq(handler)

        assert _generate()["itinerary"]
        assert fake.calls[1]["model"] == "openai/gpt-oss-20b"

    def test_swap_rate_limit_then_success(self, fake_groq):
        def handler(n, kw):
            if n == 1:
                raise _rate_limit()
            return _Completion(_VALID_SWAP)

        fake = fake_groq(handler)

        assert _swap()["title"] == "Musee d'Orsay Visit"
        assert len(fake.calls) == 2

    def test_classifiers(self):
        assert itinerary_service._is_transient_error(_rate_limit())
        assert itinerary_service._is_transient_error(_server_error())
        assert itinerary_service._is_transient_error(_timeout())
        assert itinerary_service._is_transient_error(_connection_error())
        assert not itinerary_service._is_transient_error(_auth_error())
        assert not itinerary_service._is_transient_error(
            _status_error(groq.PermissionDeniedError, 403, "forbidden")
        )
        assert itinerary_service._is_permanent_model_error(_not_found())
        assert not itinerary_service._is_permanent_model_error(_rate_limit())
        assert itinerary_service._is_output_validation_error(_schema_rejected())
        assert not itinerary_service._is_output_validation_error(_auth_error())


# ----------------------------------------------------------------------
# Log safety
# ----------------------------------------------------------------------


class TestLogSafety:
    def test_rejected_generation_is_never_logged(self, fake_groq, caplog):
        def handler(n, kw):
            if n == 1:
                raise _schema_rejected()
            return _Completion(_valid_itinerary())

        fake_groq(handler)

        with caplog.at_level(logging.DEBUG, logger=itinerary_service.__name__):
            _generate()

        assert "SECRET-TRIP-DETAILS-IN-FAILED-OUTPUT" not in caplog.text
        assert "BadRequestError (HTTP 400, json_validate_failed)" in caplog.text

    def test_error_description_has_no_body(self):
        text = itinerary_service._describe_error(_schema_rejected())
        assert "SECRET" not in text
        assert itinerary_service._describe_error(_auth_error()) == (
            "AuthenticationError (HTTP 401, invalid_api_key)"
        )


# ----------------------------------------------------------------------
# Routes running the real generation code against the fake client
# ----------------------------------------------------------------------


@pytest.fixture
def real_ai(monkeypatch):
    """Undo the conftest stubs so routes call the real service functions."""

    monkeypatch.setattr(
        trips_module, "generate_itinerary", itinerary_service.generate_itinerary
    )
    monkeypatch.setattr(
        trips_module,
        "generate_activity_swap",
        itinerary_service.generate_activity_swap,
    )


class TestRoutesWithFakeGroq:
    def test_generate_saves_trip_with_unchanged_contract(
        self, client, fake_groq, real_ai
    ):
        token = create_logged_in_user(
            client, name="GroqUser", email="groq@example.com"
        )
        fake_groq(lambda n, kw: _Completion(_valid_itinerary()))

        resp = create_trip(
            client, token, startDate="2026-09-01", endDate="2026-09-03"
        )

        assert resp.status_code == 200, resp.get_json()
        trip = resp.get_json()["trip"]
        itinerary = trip["itinerary"]
        assert [d["day"] for d in itinerary] == [1, 2, 3]
        for day in itinerary:
            assert set(day) >= {"day", "date", "title", "activities"}
            for activity in day["activities"]:
                assert set(activity) >= {
                    "time", "title", "description", "category", "location",
                }

    def test_auth_failure_returns_generic_500_and_saves_nothing(
        self, client, fake_groq, real_ai
    ):
        token = create_logged_in_user(
            client, name="GroqAuth", email="groqauth@example.com"
        )
        fake_groq(lambda n, kw: (_ for _ in ()).throw(_auth_error()))

        resp = create_trip(
            client, token, startDate="2026-09-01", endDate="2026-09-03"
        )

        assert resp.status_code == 500
        body = resp.get_data(as_text=True)
        for leak in ("invalid_api_key", "401", "Groq", "groq", "GROQ_API_KEY"):
            assert leak not in body
        user = get_user_by_email("groqauth@example.com")
        assert Trip.query.filter_by(user_id=user.id).count() == 0

    def test_rate_limited_until_busy_returns_503(
        self, client, fake_groq, real_ai
    ):
        token = create_logged_in_user(
            client, name="GroqBusy", email="groqbusy@example.com"
        )
        fake_groq(lambda n, kw: (_ for _ in ()).throw(_rate_limit()))

        resp = create_trip(
            client, token, startDate="2026-09-01", endDate="2026-09-03"
        )

        assert resp.status_code == 503
        assert resp.get_json()["error"] == "ai_busy"

    def test_regenerate_and_swap_through_groq(
        self, client, fake_groq, real_ai
    ):
        token = create_logged_in_user(
            client, name="GroqRegen", email="groqregen@example.com"
        )
        fake_groq(lambda n, kw: _Completion(_valid_itinerary()))
        trip_id = create_trip_and_get_id(
            client, token, startDate="2026-09-01", endDate="2026-09-03"
        )

        resp = client.post(
            "/api/trips/{}/regenerate".format(trip_id),
            headers=auth_headers(token),
        )
        assert resp.status_code == 200, resp.get_json()

        fake = fake_groq(lambda n, kw: _Completion(_VALID_SWAP))
        resp = client.post(
            "/api/trips/{}/swap-activity".format(trip_id),
            json={"day": 1, "time": "Morning"},
            headers=auth_headers(token),
        )
        assert resp.status_code == 200, resp.get_json()
        day1 = resp.get_json()["trip"]["itinerary"][0]
        morning = [a for a in day1["activities"] if a["time"] == "Morning"][0]
        assert morning["title"] == "Musee d'Orsay Visit"
        assert len(fake.calls) == 1

    def test_edit_with_new_dates_rebuilds_through_groq(
        self, client, fake_groq, real_ai
    ):
        token = create_logged_in_user(
            client, name="GroqEdit", email="groqedit@example.com"
        )
        fake_groq(lambda n, kw: _Completion(_valid_itinerary()))
        trip_id = create_trip_and_get_id(
            client, token, startDate="2026-09-01", endDate="2026-09-03"
        )

        fake = fake_groq(lambda n, kw: _Completion(_valid_itinerary(days=2)))
        resp = client.patch(
            "/api/trips/{}".format(trip_id),
            json={
                "destination": "Paris",
                "startDate": "2026-09-01",
                "endDate": "2026-09-02",
                "travelers": 2,
                "budget": "moderate",
                "travelStyle": "balanced",
                "interests": ["food", "culture"],
            },
            headers=auth_headers(token),
        )

        assert resp.status_code == 200, resp.get_json()
        assert len(resp.get_json()["trip"]["itinerary"]) == 2
        assert len(fake.calls) == 1


# ----------------------------------------------------------------------
# All six supported languages reach the prompt
# ----------------------------------------------------------------------


@pytest.mark.parametrize(
    "code,name",
    [
        ("en", None),
        ("es", "Spanish"),
        ("fr", "French"),
        ("de", "German"),
        ("it", "Italian"),
        ("pt", "Portuguese"),
    ],
)
def test_language_requirement_for_every_supported_language(
    fake_groq, code, name
):
    fake = fake_groq(lambda n, kw: _Completion(_valid_itinerary()))

    _generate(language=code)

    prompt = fake.calls[0]["messages"][0]["content"]
    if name is None:
        assert "LANGUAGE REQUIREMENT" not in prompt
    else:
        assert "LANGUAGE REQUIREMENT" in prompt
        assert "in {}.".format(name) in prompt


@pytest.mark.parametrize("code", ["es", "fr", "de", "it", "pt"])
def test_swap_language_requirement(fake_groq, code):
    fake = fake_groq(lambda n, kw: _Completion(_VALID_SWAP))
    names = {"es": "Spanish", "fr": "French", "de": "German",
             "it": "Italian", "pt": "Portuguese"}

    itinerary_service.generate_activity_swap(
        destination="Paris", day_number=1, day_date="2026-09-01",
        time_slot="Morning",
        current_activity={"time": "Morning", "title": "Louvre Visit",
                          "description": "Museum", "category": "Culture",
                          "location": "1st Arrondissement"},
        day_activities=[], existing_titles=["Louvre Visit"], travelers=2,
        budget="moderate", travel_style="balanced", interests=["culture"],
        language=code, day_weather=(),
        deadline=time.monotonic() + 25.0,
    )

    assert names[code] in fake.calls[0]["messages"][0]["content"]


# ----------------------------------------------------------------------
# Free-tier resilience: bounded retries, no corruption, safe errors
# ----------------------------------------------------------------------


class TestFreeTierResilience:
    @pytest.mark.parametrize(
        "make_error",
        [_rate_limit, _server_error, _timeout, _connection_error,
         _schema_rejected],
        ids=["429", "503", "timeout", "connection", "schema-rejected"],
    )
    def test_retries_are_capped_at_three(self, fake_groq, make_error):
        fake = fake_groq(lambda n, kw: (_ for _ in ()).throw(make_error()))

        with pytest.raises(itinerary_service.AIBusyError):
            _generate()

        assert len(fake.calls) == 3

    @pytest.mark.parametrize(
        "make_error", [_rate_limit, _server_error, _schema_rejected],
        ids=["429", "503", "schema-rejected"],
    )
    def test_swap_retries_are_capped_at_three(self, fake_groq, make_error):
        fake = fake_groq(lambda n, kw: (_ for _ in ()).throw(make_error()))

        with pytest.raises(itinerary_service.AIBusyError):
            _swap()

        assert len(fake.calls) == 3

    def test_both_models_used_before_giving_up(self, fake_groq):
        fake = fake_groq(lambda n, kw: (_ for _ in ()).throw(_rate_limit()))

        with pytest.raises(itinerary_service.AIBusyError):
            _generate()

        assert {c["model"] for c in fake.calls} == set(
            itinerary_service.GROQ_MODELS
        )

    def test_concurrent_requests_fail_or_succeed_cleanly(self, fake_groq):
        import threading

        lock = threading.Lock()
        counter = {"n": 0}

        def handler(n, kw):
            with lock:
                counter["n"] += 1
                k = counter["n"]
            if k % 3 == 0:
                raise _rate_limit()
            if k % 5 == 0:
                raise _server_error()
            return _Completion(_valid_itinerary())

        fake = fake_groq(handler)
        outcomes = []
        unexpected = []

        def worker():
            try:
                _generate()
                outcome = "ok"
            except itinerary_service.AIBusyError:
                outcome = "busy"
            except Exception as error:  # pragma: no cover - reported below
                unexpected.append(repr(error))
                return
            with lock:
                outcomes.append(outcome)

        threads = [threading.Thread(target=worker) for _ in range(12)]
        for t in threads:
            t.start()
        for t in threads:
            t.join(timeout=30)

        assert not unexpected, unexpected
        assert len(outcomes) == 12
        assert outcomes.count("ok") >= 1
        # Bounded: never more than 3 provider calls per request.
        assert len(fake.calls) <= 12 * 3


class TestFailuresDoNotCorruptTrips:
    def _trip(self, client, token):
        resp = client.get(
            "/api/trips", headers=auth_headers(token)
        )
        assert resp.status_code == 200
        return resp.get_json()["trips"][0]

    def test_failed_regenerate_keeps_itinerary(
        self, client, fake_groq, real_ai
    ):
        token = create_logged_in_user(
            client, name="KeepRegen", email="keepregen@example.com"
        )
        fake_groq(lambda n, kw: _Completion(_valid_itinerary()))
        trip_id = create_trip_and_get_id(
            client, token, startDate="2026-09-01", endDate="2026-09-03"
        )
        before = self._trip(client, token)

        fake_groq(lambda n, kw: (_ for _ in ()).throw(_rate_limit()))
        resp = client.post(
            "/api/trips/{}/regenerate".format(trip_id),
            headers=auth_headers(token),
        )

        assert resp.status_code == 503
        assert resp.get_json() == {
            "error": "ai_busy",
            "message": "The AI is busy right now, please try again in a minute.",
        }
        assert self._trip(client, token)["itinerary"] == before["itinerary"]

    def test_failed_swap_keeps_itinerary(self, client, fake_groq, real_ai):
        token = create_logged_in_user(
            client, name="KeepSwap", email="keepswap@example.com"
        )
        fake_groq(lambda n, kw: _Completion(_valid_itinerary()))
        trip_id = create_trip_and_get_id(
            client, token, startDate="2026-09-01", endDate="2026-09-03"
        )
        before = self._trip(client, token)

        fake_groq(lambda n, kw: (_ for _ in ()).throw(_server_error()))
        resp = client.post(
            "/api/trips/{}/swap-activity".format(trip_id),
            json={"day": 1, "time": "Morning"},
            headers=auth_headers(token),
        )

        assert resp.status_code == 503
        assert resp.get_json()["error"] == "ai_busy"
        assert self._trip(client, token)["itinerary"] == before["itinerary"]

    def test_failed_edit_keeps_dates_and_itinerary(
        self, client, fake_groq, real_ai
    ):
        token = create_logged_in_user(
            client, name="KeepEdit", email="keepedit@example.com"
        )
        fake_groq(lambda n, kw: _Completion(_valid_itinerary()))
        trip_id = create_trip_and_get_id(
            client, token, startDate="2026-09-01", endDate="2026-09-03"
        )
        before = self._trip(client, token)

        fake_groq(lambda n, kw: (_ for _ in ()).throw(_auth_error()))
        resp = client.patch(
            "/api/trips/{}".format(trip_id),
            json={
                "destination": "Paris",
                "startDate": "2026-09-01",
                "endDate": "2026-09-02",
                "travelers": 2,
                "budget": "moderate",
                "travelStyle": "balanced",
                "interests": ["food", "culture"],
            },
            headers=auth_headers(token),
        )

        assert resp.status_code == 500
        body = resp.get_data(as_text=True)
        assert "invalid_api_key" not in body and "groq" not in body.lower()
        after = self._trip(client, token)
        assert after["itinerary"] == before["itinerary"]
        assert after["endDate"] == before["endDate"]
