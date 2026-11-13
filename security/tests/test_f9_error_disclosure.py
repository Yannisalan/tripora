"""F9 - Exception text must never reach API clients.

Audit result (see SECURITY_HARDENING_REPORT.md, P11): route handlers used to
return ``str(error)`` for any ``ValueError`` / provider exception. Most of
those messages were hand-written, but the same handlers also caught
standard-library parser errors (echoing raw input) and provider errors that
named the vendor and its credential state. The fix:

- ``services.client_errors.ClientValidationError`` marks messages written for
  the client; ``client_message()`` returns any other exception as a fixed
  fallback.
- Session-identity failures return the fixed ``INVALID_SESSION_MESSAGE``.
- Travel provider failures return a fixed 502 message (code unchanged).
- App-level JSON handlers cover unhandled exceptions and HTTP errors.
- SQLAlchemy ``hide_parameters`` keeps bind values out of logged DB errors.

Only synthetic users/data and in-memory test databases are used.
"""

import logging
import sys

import pytest
import sqlalchemy.exc
from flask import abort
from sqlalchemy import text

import routes.auth as auth_mod
import routes.travel as travel_mod
import routes.trips as trips_mod
from config.database import db
from services.client_errors import (
    GENERIC_INVALID_REQUEST_MESSAGE,
    INVALID_SESSION_MESSAGE,
    UNEXPECTED_ERROR_MESSAGE,
    ClientValidationError,
    client_message,
)
from services.travelpayouts_service import (
    TravelpayoutsError,
    TravelpayoutsLookupError,
)

from .helpers import auth_headers, create_logged_in_user, create_trip


# Strings that must never appear in a client response. Each is planted in an
# exception message by a test below.
SECRET_DETAIL = "postgresql://tripora_owner:hunter2-secret@db.internal:5432/tripora"
SQL_DETAIL = "SELECT users.password_hash FROM users WHERE users.email = %(email)s"


def _text(resp):
    return resp.get_data(as_text=True)


def _assert_no_detail(resp, *needles):
    body = _text(resp)
    for needle in (SECRET_DETAIL, SQL_DETAIL, "hunter2", "Traceback",
                   "password_hash") + needles:
        assert needle not in body, (needle, body)
    assert resp.is_json, body


# ----------------------------------------------------------------------
# 1. The helper itself
# ----------------------------------------------------------------------

class TestClientMessageHelper:

    def test_client_validation_message_passes_through(self):
        assert client_message(ClientValidationError("Travelers cannot exceed 50.")) \
            == "Travelers cannot exceed 50."

    @pytest.mark.parametrize("error", [
        ValueError("Invalid isoformat string: '2026-09-01xyz'"),
        ValueError(SECRET_DETAIL),
        RuntimeError(SQL_DETAIL),
        KeyError("password"),
        TravelpayoutsError("Travelpayouts rejected the API credentials."),
    ])
    def test_other_exceptions_use_fallback(self, error):
        assert client_message(error) == GENERIC_INVALID_REQUEST_MESSAGE
        assert client_message(error, "Custom.") == "Custom."

    def test_empty_client_message_uses_fallback(self):
        assert client_message(ClientValidationError("  "), "Fallback.") == "Fallback."

    def test_client_validation_error_is_still_a_value_error(self):
        # Existing ``except ValueError`` handlers must keep catching it.
        assert issubclass(ClientValidationError, ValueError)


# ----------------------------------------------------------------------
# 2. Trips: validation messages kept, parser/internal text hidden
# ----------------------------------------------------------------------

class TestTripsErrorDisclosure:

    def _token(self, client):
        return create_logged_in_user(client, name="F9Trips")

    def test_stdlib_date_error_is_not_echoed_on_generate(self, client):
        # The payload parser accepts "2026-09-01xyz" (it reads [:10]) but the
        # cost service parses the full string. That used to return
        # "Invalid isoformat string: '2026-09-01xyz'".
        token = self._token(client)
        resp = create_trip(client, token, startDate="2026-09-01xyz")
        assert resp.status_code == 400
        assert resp.get_json()["message"] == trips_mod.INVALID_TRIP_DETAILS_MESSAGE
        _assert_no_detail(resp, "isoformat", "xyz")

    def test_stdlib_date_error_is_not_echoed_on_update(self, client):
        token = self._token(client)
        resp = client.patch(
            "/api/trips/1",
            json={
                "destination": "Paris",
                "startDate": "2026-09-01",
                "endDate": "2026-09-04<script>",
                "travelers": 2,
            },
            headers=auth_headers(token),
        )
        assert resp.status_code == 400
        assert resp.get_json()["message"] == trips_mod.INVALID_TRIP_DETAILS_MESSAGE
        _assert_no_detail(resp, "isoformat", "<script>")

    def test_cost_service_validation_message_is_preserved(self, client):
        # Same-day trip: cost_service raises its own client-facing message.
        token = self._token(client)
        resp = create_trip(client, token, startDate="2026-09-01",
                           endDate="2026-09-01")
        assert resp.status_code == 400
        assert resp.get_json()["message"] == "End date must be after start date."

    @pytest.mark.parametrize("overrides,message", [
        ({"destination": ""}, "Destination is required."),
        ({"travelers": 51}, "Travelers cannot exceed 50."),
        ({"interests": "food"}, "Interests must be a list."),
        ({"startDate": "not-a-date"}, "Invalid date format."),
        ({"endDate": "2026-08-01"}, "End date cannot be before start date."),
        ({"budgetAmount": -5}, "Budget amount must be a positive number."),
    ])
    def test_payload_validation_messages_are_preserved(self, client,
                                                       overrides, message):
        token = self._token(client)
        resp = create_trip(client, token, **overrides)
        assert resp.status_code == 400
        assert resp.get_json() == {"success": False, "message": message}

    def test_unexpected_value_error_in_cost_is_generic(self, client, monkeypatch):
        token = self._token(client)

        def boom(*args, **kwargs):
            raise ValueError(SECRET_DETAIL)

        monkeypatch.setattr(trips_mod, "calculate_trip_cost", boom)
        resp = create_trip(client, token)
        assert resp.status_code == 400
        assert resp.get_json()["message"] == trips_mod.INVALID_TRIP_DETAILS_MESSAGE
        _assert_no_detail(resp)

    def test_unexpected_exception_in_cost_is_generic_500(self, client, monkeypatch):
        token = self._token(client)

        def boom(*args, **kwargs):
            raise RuntimeError(SECRET_DETAIL)

        monkeypatch.setattr(trips_mod, "calculate_trip_cost", boom)
        resp = create_trip(client, token)
        assert resp.status_code == 500
        assert resp.get_json()["error"] == "Internal server error."
        _assert_no_detail(resp)

    def test_session_identity_error_text_is_fixed(self, client, monkeypatch):
        token = self._token(client)

        def bad_identity():
            raise ValueError(SECRET_DETAIL)

        monkeypatch.setattr(trips_mod, "_get_authenticated_user_id", bad_identity)
        for method, path in (("get", "/api/trips"), ("get", "/api/trips/1"),
                             ("delete", "/api/trips/1")):
            resp = getattr(client, method)(path, headers=auth_headers(token))
            assert resp.status_code == 401, path
            assert resp.get_json() == {
                "success": False, "message": INVALID_SESSION_MESSAGE,
            }
            _assert_no_detail(resp)

    def test_database_error_on_list_masks_sql(self, client, monkeypatch):
        token = self._token(client)
        from sqlalchemy.orm import Query

        def flaky_all(self_, *args, **kwargs):
            raise sqlalchemy.exc.OperationalError(
                SQL_DETAIL, {"email": "victim@example.com"},
                Exception(SECRET_DETAIL),
            )

        monkeypatch.setattr(Query, "all", flaky_all)
        resp = client.get("/api/trips", headers=auth_headers(token))
        assert resp.status_code == 500
        assert resp.get_json()["message"] == "Failed to retrieve trips."
        _assert_no_detail(resp, "victim@example.com")


# ----------------------------------------------------------------------
# 3. Expenses and auth: session-identity text is fixed
# ----------------------------------------------------------------------

class TestIdentityErrorsAreFixed:

    def test_expenses_identity_error(self, client, monkeypatch):
        import routes.expenses as expenses_mod

        token = create_logged_in_user(client, name="F9Exp")

        def bad_identity():
            raise ValueError(SECRET_DETAIL)

        monkeypatch.setattr(expenses_mod, "_get_authenticated_user_id",
                            bad_identity)
        resp = client.get("/api/trips/1/expenses", headers=auth_headers(token))
        assert resp.status_code == 401
        assert resp.get_json()["message"] == INVALID_SESSION_MESSAGE
        _assert_no_detail(resp)

    @pytest.mark.parametrize("method,path", [
        ("get", "/api/auth/me"),
        ("post", "/api/auth/verify-email"),
        ("post", "/api/auth/verify-email/resend"),
    ])
    def test_auth_identity_error(self, client, monkeypatch, method, path):
        token = create_logged_in_user(client, name="F9Auth")

        def bad_identity():
            raise auth_mod.InvalidIdentityError(SECRET_DETAIL)

        monkeypatch.setattr(auth_mod, "_current_user_id", bad_identity)
        resp = getattr(client, method)(path, json={},
                                       headers=auth_headers(token))
        assert resp.status_code == 401
        assert resp.get_json()["message"] == INVALID_SESSION_MESSAGE
        _assert_no_detail(resp)

    def test_social_verification_detail_hidden(self, client, monkeypatch):
        from services.social_auth_service import SocialAuthError

        def fail(provider, id_token_value, nonce=None):
            raise SocialAuthError("Invalid Apple identity token. " + SECRET_DETAIL)

        monkeypatch.setattr(auth_mod, "verify_identity_token", fail)
        resp = client.post("/api/auth/social", json={"provider": "apple",
                                                     "idToken": "x"})
        assert resp.status_code == 401
        assert resp.get_json()["message"].startswith("Could not verify")
        _assert_no_detail(resp)


# ----------------------------------------------------------------------
# 4. Travel provider errors
# ----------------------------------------------------------------------

@pytest.fixture
def no_provider_credentials(monkeypatch):
    for name in ("DUFFEL_API_TOKEN", "TRAVELPAYOUTS_API_KEY",
                 "TRAVELPAYOUTS_API_TOKEN", "TRAVELPAYOUTS_TOKEN",
                 "TRAVELPAYOUTS_KEY"):
        monkeypatch.delenv(name, raising=False)


class TestTravelProviderErrors:

    def _token(self, client):
        return create_logged_in_user(client, name="F9Travel")

    def _assert_provider_502(self, resp):
        assert resp.status_code == 502
        body = resp.get_json()
        assert body["message"] == travel_mod.TRAVEL_PROVIDER_UNAVAILABLE_MESSAGE
        assert body["code"] == "PROVIDER_ERROR"
        assert body["error"] == "travel_provider_error"
        _assert_no_detail(resp, "Duffel", "Travelpayouts", "credentials",
                          "not configured")

    def test_unconfigured_duffel_stays(self, client, no_provider_credentials):
        resp = client.post("/api/travel/stays/search", json={
            "location": "Paris", "checkIn": "2026-10-01",
            "checkOut": "2026-10-05",
        }, headers=auth_headers(self._token(client)))
        self._assert_provider_502(resp)

    def test_unconfigured_duffel_cars(self, client, no_provider_credentials):
        resp = client.post("/api/travel/cars/search", json={
            "pickup": "CDG", "dropoff": "CDG",
            "pickupDateTime": "2026-10-01T10:00:00",
            "dropoffDateTime": "2026-10-05T10:00:00",
        }, headers=auth_headers(self._token(client)))
        self._assert_provider_502(resp)

    def test_unconfigured_travelpayouts_prices(self, client,
                                               no_provider_credentials):
        resp = client.post("/api/travel/flights/prices", json={
            "origin": "JFK", "destination": "LHR", "departDate": "2026-10-01",
        }, headers=auth_headers(self._token(client)))
        self._assert_provider_502(resp)

    def test_rejected_credentials_hidden(self, client, monkeypatch):
        def rejected(**kwargs):
            raise TravelpayoutsError("Travelpayouts rejected the API credentials.")

        monkeypatch.setattr(travel_mod, "search_flight_prices", rejected)
        resp = client.post("/api/travel/flights/search", json={
            "origin": "JFK", "destination": "LHR", "departDate": "2026-10-01",
        }, headers=auth_headers(self._token(client)))
        self._assert_provider_502(resp)

    def test_location_lookup_message_is_preserved(self, client, monkeypatch):
        def not_found(value):
            raise TravelpayoutsLookupError(
                "Could not find that location. Check the spelling or enter "
                "its airport code."
            )

        monkeypatch.setattr(travel_mod, "resolve_city_to_iata", not_found)
        resp = client.post("/api/travel/flights/search", json={
            "origin": "Atlantis", "destination": "LHR",
            "departDate": "2026-10-01",
        }, headers=auth_headers(self._token(client)))
        assert resp.status_code == 400
        assert resp.get_json()["message"].startswith(
            "Could not find that location.")

    def test_non_lookup_error_during_resolve_is_hidden(self, client, monkeypatch):
        def down(value):
            raise TravelpayoutsError(SECRET_DETAIL)

        monkeypatch.setattr(travel_mod, "resolve_city_to_iata", down)
        resp = client.post("/api/travel/flights/search", json={
            "origin": "Paris", "destination": "LHR",
            "departDate": "2026-10-01",
        }, headers=auth_headers(self._token(client)))
        self._assert_provider_502(resp)


# ----------------------------------------------------------------------
# 5. App-level handlers (unhandled exceptions and HTTP errors)
# ----------------------------------------------------------------------

@pytest.fixture
def probe_app(app):
    """Add throwaway routes that fail in controlled ways."""

    @app.route("/api/_f9/boom", methods=["POST"])
    def _f9_boom():
        raise RuntimeError(SECRET_DETAIL)

    @app.route("/api/_f9/db", methods=["GET"])
    def _f9_db():
        raise sqlalchemy.exc.OperationalError(
            SQL_DETAIL, {"email": "victim@example.com"}, Exception("refused"))

    @app.route("/api/_f9/abort", methods=["GET"])
    def _f9_abort():
        abort(400, description=SQL_DETAIL)

    @app.route("/api/_f9/abort500", methods=["GET"])
    def _f9_abort500():
        abort(503, description=SECRET_DETAIL)

    return app


class TestGlobalErrorHandlers:

    def test_unhandled_exception_is_generic_json_500(self, probe_app, caplog):
        client = probe_app.test_client()
        with caplog.at_level(logging.ERROR):
            resp = client.post(
                "/api/_f9/boom",
                json={"password": "body-password-value"},
                headers={"Authorization": "Bearer header-token-value"},
            )
        assert resp.status_code == 500
        assert resp.get_json() == {
            "success": False,
            "message": UNEXPECTED_ERROR_MESSAGE,
            "error": "Internal server error.",
        }
        _assert_no_detail(resp, "RuntimeError")
        # Diagnostics stay server-side ...
        assert "Unhandled RuntimeError on POST /api/_f9/boom" in caplog.text
        # ... but the handler never logs the request body or headers.
        assert "body-password-value" not in caplog.text
        assert "header-token-value" not in caplog.text

    def test_unhandled_database_error_masks_sql(self, probe_app):
        resp = probe_app.test_client().get("/api/_f9/db")
        assert resp.status_code == 500
        _assert_no_detail(resp, "victim@example.com", "refused",
                          "OperationalError")

    def test_abort_description_is_not_returned(self, probe_app):
        resp = probe_app.test_client().get("/api/_f9/abort")
        assert resp.status_code == 400
        assert resp.get_json()["message"] == "Bad request."
        _assert_no_detail(resp)

    def test_abort_5xx_description_is_not_returned(self, probe_app):
        resp = probe_app.test_client().get("/api/_f9/abort500")
        assert resp.status_code == 503
        assert resp.get_json()["message"] == UNEXPECTED_ERROR_MESSAGE
        _assert_no_detail(resp)

    def test_404_is_json(self, client):
        resp = client.get("/api/does-not-exist")
        assert resp.status_code == 404
        assert resp.get_json()["success"] is False
        assert "text/html" not in resp.content_type

    def test_405_is_json_and_keeps_allow_header(self, client):
        resp = client.put("/api/auth/register")
        assert resp.status_code == 405
        assert resp.is_json
        assert "POST" in resp.headers.get("Allow", "")

    def test_413_is_json(self, client):
        resp = client.post("/api/auth/login", data=b"x" * (1024 * 1024 + 10),
                           content_type="application/json")
        assert resp.status_code == 413
        assert resp.get_json()["message"] == "The request is too large."

    def test_unguarded_route_db_failure_is_generic(self, client, monkeypatch):
        # verify-email/resend has no local try/except around its DB read, so
        # a DB failure there is handled by the app-level handler.
        token = create_logged_in_user(client, name="F9Resend")
        real_get = db.session.get

        def flaky_get(*args, **kwargs):
            if sys._getframe(1).f_code.co_name == "resend_verification_email":
                raise sqlalchemy.exc.OperationalError(
                    SQL_DETAIL, {"id": 1}, Exception(SECRET_DETAIL))
            return real_get(*args, **kwargs)

        monkeypatch.setattr(db.session, "get", flaky_get)
        resp = client.post("/api/auth/verify-email/resend",
                           headers=auth_headers(token))
        assert resp.status_code == 500
        assert resp.get_json()["message"] == UNEXPECTED_ERROR_MESSAGE
        _assert_no_detail(resp)

    def test_jwt_errors_keep_their_own_handlers(self, client):
        # The generic Exception handler must not swallow JWT 401s.
        resp = client.get("/api/trips")
        assert resp.status_code == 401
        assert resp.get_json()["message"] == "Authentication is required."


# ----------------------------------------------------------------------
# 6. Server logs: SQL bind parameters are hidden
# ----------------------------------------------------------------------

class TestSqlParametersHiddenInLogs:

    def test_engine_hides_parameters(self, app):
        assert db.engine.hide_parameters is True

    def test_db_error_text_has_no_bind_values(self, app):
        with pytest.raises(sqlalchemy.exc.DBAPIError) as info:
            db.session.execute(
                text("SELECT * FROM f9_no_such_table WHERE secret = :value"),
                {"value": "bind-secret-value"},
            )
        db.session.rollback()
        assert "bind-secret-value" not in str(info.value)
        assert "hidden" in str(info.value).lower()
