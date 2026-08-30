"""Controlled input-security testing for POST /api/trips/generate.

Covers 20 input categories plus SQL-injection resistance using only harmless,
non-destructive payloads. Every test records the HTTP status code, response
body, and whether a server-side exception leaked into the response.

These tests capture evidence for the report
``security/reports/generate-trip-security.md``. Only synthetic test users are
used; no destructive commands; no DB data is modified or deleted.

Expected behaviour reference (backend/routes/trips.py ``_parse_trip_payload``):
- destination        : required, non-empty after strip
- startDate/endDate  : required, ISO-parseable from first 10 chars
- travelers          : must be ``int`` and > 0
- budget             : no type validation in parser (cost service calls .lower())
- travelStyle        : no validation
- interests          : must be a ``list``
- extra fields       : ignored
"""

import json

import pytest

from .helpers import (
    auth_headers,
    create_logged_in_user,
)

# ----------------------------------------------------------------------
# Evidence capture
# ----------------------------------------------------------------------


# Collected at module teardown for the report.
EVIDENCE = []


def _record(category, case, status, body, exception_exposed):
    """Store a row of evidence for the report."""
    EVIDENCE.append(
        {
            "category": category,
            "case": case,
            "status": status,
            "body": body,
            "exception_exposed": exception_exposed,
        }
    )


def _exception_exposed(status, body):
    """Heuristic: did the response leak a server-side exception / stack text?"""
    if status < 500:
        return "no"
    text = ""
    if isinstance(body, dict):
        # The app returns {"error": str(error)} on some 500s.
        text = body.get("error") or body.get("message") or ""
    elif isinstance(body, str):
        text = body
    lower = text.lower()
    markers = (
        "traceback",
        "exception",
        "attributerror",
        "has no attribute",
        "object has no attribute",
        "valueerror",
        "sqlalchemy",
        "pymysql",
        "operationalerror",
        "file \"",
        "line ",
    )
    return "yes" if any(m in lower for m in markers) else "no"


# ----------------------------------------------------------------------
# Fixtures
# ----------------------------------------------------------------------


@pytest.fixture
def authed(client):
    """An authenticated test user + auth headers."""
    token = create_logged_in_user(client, name="GenTrip", email="gentrip@example.com")
    return token


# ----------------------------------------------------------------------
# Test implementations
# ----------------------------------------------------------------------


BASE = {
    "destination": "Paris",
    "startDate": "2026-09-01",
    "endDate": "2026-09-04",
    "travelers": 2,
    "budget": "moderate",
    "travelStyle": "balanced",
    "interests": ["food", "culture"],
}


def _send(client, token, payload):
    """POST /api/trips/generate and return (response, status, body)."""
    resp = client.post(
        "/api/trips/generate", json=payload, headers=auth_headers(token)
    )
    body = resp.get_json(silent=True)
    if body is None:
        body = resp.get_data(as_text=True)
    return resp, resp.status_code, body


def _run_case(client, token, category, case, payload):
    resp, status, body = _send(client, token, payload)
    _record(category, case, status, body, _exception_exposed(status, body))
    return resp, status, body


class TestDestination:
    def test_missing_destination(self, client, authed):
        payload = dict(BASE)
        del payload["destination"]
        resp, status, body = _run_case(
            client, authed, "Missing destination",
            "destination key absent", payload,
        )
        assert status == 400

    def test_empty_destination(self, client, authed):
        payload = dict(BASE, destination="")
        resp, status, body = _run_case(
            client, authed, "Empty destination", "destination = ''",
            payload,
        )
        assert status == 400

    def test_whitespace_destination(self, client, authed):
        payload = dict(BASE, destination="   ")
        resp, status, body = _run_case(
            client, authed, "Empty destination", "destination = '   '",
            payload,
        )
        assert status == 400

    def test_null_destination(self, client, authed):
        payload = dict(BASE, destination=None)
        resp, status, body = _run_case(
            client, authed, "Null values", "destination = null",
            payload,
        )
        # str(None).strip() == 'None' -> truthy, so it may be accepted.
        assert status in (200, 400)

    def test_extremely_long_destination(self, client, authed):
        long_dest = "A" * 100000
        payload = dict(BASE, destination=long_dest)
        resp, status, body = _run_case(
            client, authed, "Extremely long destination",
            "destination = 100000 chars", payload,
        )
        # No route-level length cap; SQLite does not enforce String(255).
        assert status in (200, 400)
        if status == 200:
            trips = client.get("/api/trips", headers=auth_headers(authed)).get_json()["trips"]
            assert any(t["destination"] == long_dest for t in trips)


class TestDates:
    def test_invalid_start_date(self, client, authed):
        payload = dict(BASE, startDate="not-a-date")
        resp, status, body = _run_case(
            client, authed, "Invalid start date", "startDate = 'not-a-date'",
            payload,
        )
        assert status == 400

    def test_invalid_end_date(self, client, authed):
        payload = dict(BASE, endDate="2026-13-45")
        resp, status, body = _run_case(
            client, authed, "Invalid end date", "endDate = '2026-13-45'",
            payload,
        )
        assert status == 400

    def test_end_before_start(self, client, authed):
        payload = dict(BASE, startDate="2026-09-10", endDate="2026-09-01")
        resp, status, body = _run_case(
            client, authed, "End date before start date",
            "end 09-01 < start 09-10", payload,
        )
        assert status == 400

    def test_dates_as_numbers(self, client, authed):
        payload = dict(BASE, startDate=20260901)
        resp, status, body = _run_case(
            client, authed, "Invalid start date", "startDate = 20260901 (int)",
            payload,
        )
        # FIXED (A-12): non-string dates are rejected up front by the parser,
        # so an integer no longer bypasses the ISO check or crashes the cost
        # service. Returned as a clean 400 with no internal detail exposed.
        assert status == 400
        assert isinstance(body, dict)
        assert _exception_exposed(status, body) == "no"


class TestTravelers:
    def test_invalid_type_string(self, client, authed):
        payload = dict(BASE, travelers="2")
        resp, status, body = _run_case(
            client, authed, "Invalid traveler count", "travelers = '2' (str)",
            payload,
        )
        assert status == 400

    def test_invalid_type_float(self, client, authed):
        payload = dict(BASE, travelers=2.5)
        resp, status, body = _run_case(
            client, authed, "Invalid traveler count", "travelers = 2.5 (float)",
            payload,
        )
        assert status == 400

    def test_negative_count(self, client, authed):
        payload = dict(BASE, travelers=-1)
        resp, status, body = _run_case(
            client, authed, "Negative traveler count", "travelers = -1",
            payload,
        )
        assert status == 400

    def test_zero_count(self, client, authed):
        payload = dict(BASE, travelers=0)
        resp, status, body = _run_case(
            client, authed, "Invalid traveler count", "travelers = 0",
            payload,
        )
        assert status == 400

    def test_extremely_large_count(self, client, authed):
        payload = dict(BASE, travelers=10 ** 9)
        resp, status, body = _run_case(
            client, authed, "Extremely large traveler count",
            "travelers = 1e9", payload,
        )
        # Large but valid int; accepted (cost math only). Not a numeric-bounds
        # overflow because Python ints are unbounded.
        assert status in (200, 400)


class TestBudget:
    def test_negative_budget_string(self, client, authed):
        payload = dict(BASE, budget="-100")
        resp, status, body = _run_case(
            client, authed, "Negative budget", "budget = '-100' (str)",
            payload,
        )
        # budget is not validated; any string passes through to the AI stub
        # and cost service (which falls back to moderate on unknown keys).
        assert status == 200

    def test_negative_budget_number(self, client, authed):
        payload = dict(BASE, budget=-100)
        resp, status, body = _run_case(
            client, authed, "Negative budget", "budget = -100 (int)",
            payload,
        )
        # FIXED (A-12): non-string budget rejected by the parser before the
        # cost service (which called .lower() -> AttributeError).
        assert status == 400

    def test_extremely_large_budget(self, client, authed):
        payload = dict(BASE, budget="9" * 100)
        resp, status, body = _run_case(
            client, authed, "Extremely large budget", "budget = 100-digit str",
            payload,
        )
        assert status in (200, 400)

    def test_invalid_budget_type_int(self, client, authed):
        payload = dict(BASE, budget=123)
        resp, status, body = _run_case(
            client, authed, "Invalid budget type", "budget = 123 (int)",
            payload,
        )
        # FIXED (A-12): int budget rejected with a clean 400.
        assert status == 400

    def test_invalid_budget_type_list(self, client, authed):
        payload = dict(BASE, budget=["moderate"])
        resp, status, body = _run_case(
            client, authed, "Invalid budget type", "budget = ['moderate']",
            payload,
        )
        # FIXED (A-12): list budget rejected with a clean 400.
        assert status == 400


class TestTravelStyle:
    def test_invalid_travel_style(self, client, authed):
        payload = dict(BASE, travelStyle=12345)
        resp, status, body = _run_case(
            client, authed, "Invalid travel style", "travelStyle = 12345 (int)",
            payload,
        )
        # travelStyle is never validated; accepted as-is.
        assert status == 200


class TestInterests:
    def test_interests_string_instead_of_list(self, client, authed):
        payload = dict(BASE, interests="food,culture")
        resp, status, body = _run_case(
            client, authed, "Invalid interests", "interests = str",
            payload,
        )
        assert status == 400

    def test_interests_object_instead_of_list(self, client, authed):
        payload = dict(BASE, interests={"food": True})
        resp, status, body = _run_case(
            client, authed, "Invalid interests", "interests = object",
            payload,
        )
        assert status == 400


class TestUnexpectedAndMalformed:
    def test_unexpected_json_fields(self, client, authed):
        payload = dict(BASE, admin=True, role="root", secret_token="x", user_id=1)
        resp, status, body = _run_case(
            client, authed, "Unexpected JSON fields",
            "extra keys: admin, role, ...", payload,
        )
        # Extra fields are ignored; trip is created normally.
        assert status == 200
        assert "admin" not in (body or {})

    def test_null_mandatory_fields(self, client, authed):
        payload = dict(BASE, startDate=None, endDate=None, travelers=None)
        resp, status, body = _run_case(
            client, authed, "Null values", "null start/end/travelers",
            payload,
        )
        # None for dates -> fromisoformat('None') fails -> 400; travelers None
        # -> not int -> 400.
        assert status == 400

    def test_arrays_where_strings_expected(self, client, authed):
        payload = dict(BASE, destination=["Paris"], budget=["moderate"])
        resp, status, body = _run_case(
            client, authed, "Arrays where strings expected",
            "destination/budget as arrays", payload,
        )
        # FIXED (A-12): destination array is accepted as text, but the list
        # budget is now rejected by the parser -> clean 400.
        assert status == 400

    def test_objects_where_primitives_expected(self, client, authed):
        payload = dict(BASE, destination={"name": "Paris"}, travelers={"n": 2})
        resp, status, body = _run_case(
            client, authed, "Objects where primitives expected",
            "destination/travelers as objects", payload,
        )
        # travelers dict is not int -> 400.
        assert status == 400

    def test_malformed_json(self, client, authed):
        """POST raw malformed JSON (not via json=)."""
        raw = b'{"destination": "Paris", "startDate": "2026-09-01",'
        resp = client.post(
            "/api/trips/generate",
            data=raw,
            content_type="application/json",
            headers=auth_headers(authed),
        )
        body = resp.get_json(silent=True)
        status = resp.status_code
        _record("Malformed JSON", "truncated JSON body", status, body,
                _exception_exposed(status, body))
        # get_json(silent=True) returns None -> treated as missing data -> 400.
        assert status == 400

    def test_missing_auth(self, client):
        resp = client.post("/api/trips/generate", json=BASE)
        body = resp.get_json(silent=True)
        _record("Missing authentication", "no Authorization header",
                resp.status_code, body, "no")
        assert resp.status_code == 401


class TestSQLInjectionResistance:
    """Harmless SQLi-resistance probes (no destructive statements)."""

    # Note: '--', ';' and quotes are harmless meta-checks; we never attempt
    # DROP/UPDATE/DELETE etc.
    PROBES = [
        "' OR '1'='1",
        "' OR 1=1 --",
        "x' UNION SELECT NULL--",
        "'; --",
        "'\"",
        "1; SELECT 1",
        "Paris' AND '1'='1",
    ]

    @pytest.mark.parametrize("probe", PROBES)
    def test_destination_injection_probe(self, client, authed, probe):
        payload = dict(BASE, destination=probe)
        resp, status, body = _run_case(
            client, authed, "SQL injection (destination)",
            "payload={!r}".format(probe), payload,
        )
        # ORM parameterizes the query: probe stored as literal data, never
        # altering query semantics or changing row counts. Status 200 (stored)
        # or 400 (validation) is fine; never a 500 SQL error.
        assert status in (200, 400), (probe, resp.get_json())
        if status == 200:
            trips = client.get("/api/trips", headers=auth_headers(authed)).get_json()["trips"]
            assert any(t["destination"] == probe for t in trips)

    @pytest.mark.parametrize("probe", PROBES)
    def test_interests_injection_probe(self, client, authed, probe):
        payload = dict(BASE, interests=[probe])
        resp, status, body = _run_case(
            client, authed, "SQL injection (interests)",
            "payload={!r}".format(probe), payload,
        )
        assert status in (200, 400), (probe, resp.get_json())


# ----------------------------------------------------------------------
# NOTE: Evidence persistence (writing the JSON) is handled by the
# pytest_sessionfinish hook in conftest.py, which dumps this module's
# EVIDENCE list to security/reports/_generate_trip_evidence.json.
# ----------------------------------------------------------------------
