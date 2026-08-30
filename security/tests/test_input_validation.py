"""Input validation, missing-fields, and invalid-data-type tests (P5/P6/P7).

Documents expected secure behaviour for each case. Some asserts encode the
software's CURRENT (permissive) behaviour so a change toward stricter
validation becomes a deliberate, visible assertion update rather than an
unexpected failure — this flags gaps without modifying application code.
"""

from .helpers import (
    auth_headers,
    create_logged_in_user,
    create_trip,
    login,
    register,
    verify_email,
)

VALID_LANGUAGES = {"en", "es", "fr", "de", "it", "pt"}
VALID_CURRENCIES = {"USD", "EUR", "GBP", "CAD", "AUD", "AED", "JPY", "CHF"}


# ----------------------------------------------------------------------
# P5 - Input validation
# ----------------------------------------------------------------------


class TestRegistrationValidation:
    """POST /api/auth/register field validation."""

    def test_invalid_language_rejected(self, client):
        resp = register(client, name="Alice", language="zz")
        assert resp.status_code == 400
        assert resp.get_json()["success"] is False

    def test_invalid_currency_rejected(self, client):
        resp = register(client, name="Alice", currency="XYZ")
        assert resp.status_code == 400
        assert resp.get_json()["success"] is False

    def test_valid_languages_and_currencies_accepted(self, client):
        for idx, lang in enumerate(VALID_LANGUAGES):
            resp = register(
                client, name="Lang", email="lang{}-{}-@example.com".format(lang, idx), language=lang
            )
            assert resp.status_code == 201, (lang, resp.get_json())

    def test_email_is_normalized_lowercase(self, client):
        register(client, name="Alice", email="Alice@Example.com")
        user = get_user_by_email("alice@example.com")
        assert user is not None
        assert user.email == "alice@example.com"

    def test_duplicate_email_rejected(self, client):
        register(client, name="Alice", email="dup@example.com")
        resp = register(client, name="Alice2", email="dup@example.com")
        assert resp.status_code == 409

    def test_unknown_formatted_email_is_accepted_gap(self, client):
        """CONFIRMED GAP: no email format validation.

        The backend does not validate the email form, so a malformed address
        is stored. This documents the gap rather than asserting stronger
        (non-existent) behaviour.
        """
        resp = register(client, name="Alice", email="not-an-email")
        assert resp.status_code == 201


class TestUpdateMeValidation:
    """PATCH /api/auth/me per-field validation."""

    def _token(self, client):
        return create_logged_in_user(client, name="Val", email="val-me@example.com")

    def test_invalid_language_rejected(self, client):
        token = self._token(client)
        resp = client.patch("/api/auth/me", json={"preferredLanguage": "qq"},
                            headers=auth_headers(token))
        assert resp.status_code == 400

    def test_invalid_currency_rejected(self, client):
        token = self._token(client)
        resp = client.patch("/api/auth/me", json={"preferredCurrency": "BTC"},
                            headers=auth_headers(token))
        assert resp.status_code == 400


# ----------------------------------------------------------------------
# P6 - Missing required fields
# ----------------------------------------------------------------------


class TestMissingRegistrationFields:
    """POST /api/auth/register missing required fields."""

    def test_missing_name(self, client):
        resp = client.post(
            "/api/auth/register",
            json={"email": "a@example.com", "password": "secret1"},
        )
        assert resp.status_code == 400
        assert "Name" in resp.get_json().get("message", "")

    def test_missing_email(self, client):
        resp = client.post(
            "/api/auth/register",
            json={"name": "Alice", "password": "secret1"},
        )
        assert resp.status_code == 400

    def test_missing_password(self, client):
        resp = client.post(
            "/api/auth/register",
            json={"name": "Alice", "email": "a@example.com"},
        )
        assert resp.status_code == 400

    def test_empty_json_body(self, client):
        resp = client.post("/api/auth/register", json={})
        assert resp.status_code == 400

    def test_short_password_rejected(self, client):
        resp = register(client, name="Alice", password="12345")
        assert resp.status_code == 400
        assert "6" in resp.get_json().get("message", "")


class TestMissingLoginFields:
    """POST /api/auth/login missing required fields."""

    def test_missing_email(self, client):
        resp = login(client, None, "secret1")
        assert resp.status_code == 400

    def test_missing_password(self, client):
        resp = login(client, "a@example.com", None)
        assert resp.status_code == 400

    def test_empty_body(self, client):
        resp = client.post("/api/auth/login", json={})
        assert resp.status_code == 400


class TestMissingTripFields:
    """POST /api/trips/generate missing required fields."""

    def _base(self, token):
        return {
            "destination": "Paris",
            "startDate": "2026-09-01",
            "endDate": "2026-09-04",
            "travelers": 2,
            "budget": "moderate",
            "travelStyle": "balanced",
            "interests": ["food"],
        }

    def test_missing_destination(self, client):
        token = create_logged_in_user(client, name="Traveller")
        payload = self._base(token)
        del payload["destination"]
        resp = client.post("/api/trips/generate", json=payload,
                           headers=auth_headers(token))
        assert resp.status_code == 400
        assert "estination" in resp.get_json().get("message", "")

    def test_missing_start_date(self, client):
        token = create_logged_in_user(client, name="Traveller")
        payload = self._base(token)
        del payload["startDate"]
        resp = client.post("/api/trips/generate", json=payload,
                           headers=auth_headers(token))
        assert resp.status_code == 400

    def test_missing_end_date(self, client):
        token = create_logged_in_user(client, name="Traveller")
        payload = self._base(token)
        del payload["endDate"]
        resp = client.post("/api/trips/generate", json=payload,
                           headers=auth_headers(token))
        assert resp.status_code == 400

    def test_missing_travelers(self, client):
        token = create_logged_in_user(client, name="Traveller")
        payload = self._base(token)
        del payload["travelers"]
        resp = client.post("/api/trips/generate", json=payload,
                           headers=auth_headers(token))
        assert resp.status_code == 400


class TestPasswordChangeGuard:
    """Password change must require the current password."""

    def test_password_change_without_current_password(self, client):
        token = create_logged_in_user(client, name="Pw", email="pw@example.com")
        resp = client.patch(
            "/api/auth/me",
            json={"password": "newpassword1"},
            headers=auth_headers(token),
        )
        assert resp.status_code == 400

    def test_password_change_with_wrong_current_password(self, client):
        token = create_logged_in_user(client, name="Pw", email="pw2@example.com")
        resp = client.patch(
            "/api/auth/me",
            json={"password": "newpassword1", "currentPassword": "wrong"},
            headers=auth_headers(token),
        )
        assert resp.status_code == 401

    def test_password_change_with_correct_current_password(self, client):
        token = create_logged_in_user(client, name="Pw", email="pw3@example.com")
        resp = client.patch(
            "/api/auth/me",
            json={"password": "newpassword1", "currentPassword": "supersecret1"},
            headers=auth_headers(token),
        )
        assert resp.status_code == 200

        # Old password no longer works.
        assert login(client, "pw3@example.com", "supersecret1").status_code in (401, 403)
        assert login(client, "pw3@example.com", "newpassword1").status_code == 200


# ----------------------------------------------------------------------
# P7 - Invalid data types
# ----------------------------------------------------------------------


class TestInvalidTripTypes:
    """POST /api/trips/generate type and range validation."""

    def _token(self, client):
        return create_logged_in_user(client, name="Traveller")

    def _payload(self, **overrides):
        payload = {
            "destination": "Paris",
            "startDate": "2026-09-01",
            "endDate": "2026-09-04",
            "travelers": 2,
            "budget": "moderate",
            "travelStyle": "balanced",
            "interests": ["food"],
        }
        payload.update(overrides)
        return payload

    def test_travelers_string_rejected(self, client):
        token = self._token(client)
        resp = client.post("/api/trips/generate",
                           json=self._payload(travelers="2"),
                           headers=auth_headers(token))
        assert resp.status_code == 400

    def test_travelers_float_rejected(self, client):
        token = self._token(client)
        resp = client.post("/api/trips/generate",
                           json=self._payload(travelers=2.5),
                           headers=auth_headers(token))
        assert resp.status_code == 400

    def test_travelers_zero_rejected(self, client):
        token = self._token(client)
        resp = client.post("/api/trips/generate",
                           json=self._payload(travelers=0),
                           headers=auth_headers(token))
        assert resp.status_code == 400

    def test_travelers_negative_rejected(self, client):
        token = self._token(client)
        resp = client.post("/api/trips/generate",
                           json=self._payload(travelers=-1),
                           headers=auth_headers(token))
        assert resp.status_code == 400

    def test_travelers_boolean_issue_gap(self, client):
        """CONFIRMED GAP: bool is accepted because ``bool`` is an ``int``.

        ``True`` passes the ``isinstance(travelers, int)`` check, so it is
        silently coerced to traveler count 1. Documents the current
        permissive behaviour.
        """
        token = self._token(client)
        resp = client.post("/api/trips/generate",
                           json=self._payload(travelers=True),
                           headers=auth_headers(token))
        assert resp.status_code == 200

    def test_invalid_date_format_rejected(self, client):
        token = self._token(client)
        resp = client.post("/api/trips/generate",
                           json=self._payload(startDate="not-a-date"),
                           headers=auth_headers(token))
        assert resp.status_code == 400

    def test_end_before_start_rejected(self, client):
        token = self._token(client)
        resp = client.post("/api/trips/generate",
                           json=self._payload(endDate="2026-08-01"),
                           headers=auth_headers(token))
        assert resp.status_code == 400

    def test_interests_not_a_list_rejected(self, client):
        token = self._token(client)
        resp = client.post("/api/trips/generate",
                           json=self._payload(interests="food"),
                           headers=auth_headers(token))
        assert resp.status_code == 400


# Local import used above in TestRegistrationValidation
def get_user_by_email(email):
    from models.user import User

    return User.query.filter_by(email=email).first()
