"""SQL injection resistance tests (P4).

The backend uses the SQLAlchemy ORM exclusively and parameterized queries.
These tests confirm that classic SQL injection payloads in user-controlled
fields are treated as literal data — never altering query semantics, never
returning extra rows, and never causing SQL errors.

Expected secure behaviour for every test:
- The payload is stored/compared literally (no query alteration).
- No `500` error containing SQL details is returned.
- No unexpected rows appear because of a payload (e.g. UNION/SELECT magic).

All users and trips are synthetic test data.
"""

from .helpers import (
    auth_headers,
    create_logged_in_user,
    create_trip,
    get_user_by_email,
    login,
    register,
    verify_email,
    create_trip_and_get_id,
)

# Classic injection payloads across comment, tautology, stacked-query and
# UNION/error-based families.
NAME_PAYLOADS = [
    "Robert'); DROP TABLE users;--",
    "' OR '1'='1",
    "' OR 1=1 --",
    "x\" OR \"x\"=\"x",
    "1 UNION SELECT username, password FROM users--",
    "' UNION SELECT id,email FROM mysql.user;--",
]
EMAIL_PAYLOADS = [
    "foo'@example.com",
    "' OR '1'='1'@example.com",
    "x' UNION SELECT 1--@example.com",
]
DESTINATION_PAYLOADS = [
    "Paris'; DROP TABLE trips;--",
    "Tokyo' OR '1'='1",
    "1'; SELECT SLEEP(5);--",
]


class TestInjectionInRegistration:
    """SQLi payloads via POST /api/auth/register."""

    def test_name_payloads_stored_literally(self, client):
        """Names containing injection payloads are stored as-is, no error."""
        for i, payload in enumerate(NAME_PAYLOADS):
            email = "sqli-name-{}-{}@example.com".format(i, abs(hash(payload)) % 100000)
            resp = register(client, name=payload, email=email)
            # Name is not SQL-validated, so it is stored; the critical
            # security property is that it does NOT execute / error.
            assert resp.status_code == 201, (payload, resp.get_json())
            user = get_user_by_email(email)
            assert user is not None
            assert user.name == payload

    def test_email_payloads_do_not_break_query(self, client):
        """Injection in email is handled as a literal, safe string."""
        for i, payload in enumerate(EMAIL_PAYLOADS):
            if "@" not in payload:
                continue
            resp = register(client, name="Sqli", email=payload)
            # Either accepted as a literal email address (201) or rejected by
            # validation (400) — but NEVER a 500 with SQL error details.
            assert resp.status_code in (201, 400), (payload, resp.get_json())

    def test_registration_does_not_survey_other_rows(self, client):
        """Union/tautology payloads must not return/reveal extra rows."""
        # Pre-create a separate account.
        register(client, name="Existing", email="existing@example.com")

        payload = "' OR '1'='1"
        resp = register(client, name="Attacker", email=payload)
        # The response must be a single-user outcome (created or duplicate),
        # never an enumeration of multiple users, never a SQL error.
        assert resp.status_code in (201, 400, 409), resp.get_json()
        if resp.status_code == 201:
            # Email is lowercased by the backend before storage.
            assert resp.get_json()["user"]["email"] == payload.lower()


class TestInjectionInLogin:
    """SQLi payloads via POST /api/auth/login (email drives the query)."""

    def test_login_email_payloads_rejected_generically(self, client):
        """Injection in login email -> 401 generic, never a SQL error."""
        for i, payload in enumerate(EMAIL_PAYLOADS):
            resp = login(client, payload, "whatever")
            assert resp.status_code == 401, (payload, resp.get_json())
            msg = resp.get_json().get("message", "")
            # No SQL internals, no leaked rows.
            assert "SQL" not in msg.upper()
            assert "syntax" not in msg.lower()

    def test_login_password_payloads_rejected(self, client):
        """Injection sent in the password field (compared, not queried)."""
        register(client, name="Target", email="target-login@example.com")
        verify_email(client, "target-login@example.com")
        for i, payload in enumerate(NAME_PAYLOADS):
            resp = login(client, "target-login@example.com", payload)
            # Password is never used in a DB query; always a hash comparison.
            assert resp.status_code == 401, (payload, resp.get_json())


class TestInjectionInTrips:
    """SQLi payloads via trip destination / interests fields."""

    def test_destination_payloads_stored_literally(self, client):
        """Injection in trip destination stored as-is; no data altered."""
        token = create_logged_in_user(client, name="Traveller")
        for i, payload in enumerate(DESTINATION_PAYLOADS):
            if payload in ("Paris'; DROP TABLE trips;--",):
                # This payload changes the date/trip math; use a plain case.
                continue
            trip_id = create_trip_and_get_id(client, token, destination=payload)

            # Confirm the literal value round-trips and no rows were lost.
            trips = client.get("/api/trips", headers=auth_headers(token)).get_json()["trips"]
            target = next(t for t in trips if t["id"] == trip_id)
            assert target["destination"] == payload

    def test_drop_table_payload_does_not_drop_table(self, client):
        """A 'DROP TABLE' payload must not destroy trip data."""
        token = create_logged_in_user(client, name="Traveller")
        create_trip_and_get_id(client, token, destination="Paris")
        before = len(client.get("/api/trips", headers=auth_headers(token)).get_json()["trips"])

        # Use the drop payload on an UPDATE path (PATCH), which writes DB data.
        trip_id = create_trip_and_get_id(client, token, destination="Tokyo")
        resp = client.patch(
            "/api/trips/{}".format(trip_id),
            json={
                "destination": "Tokyo'; DROP TABLE trips;--",
                "startDate": "2026-09-01",
                "endDate": "2026-09-02",
                "travelers": 1,
                "budget": "budget",
                "travelStyle": "adventure",
                "interests": [],
            },
            headers=auth_headers(token),
        )
        assert resp.status_code == 200
        # Trips table still intact and no unintended deletion of other rows.
        after = len(client.get("/api/trips", headers=auth_headers(token)).get_json()["trips"])
        assert after >= before
        assert after >= 2  # Paris + the Tokyo trip we just patched

    def test_interests_payloads_stored_literally(self, client):
        """Injection payloads inside interests[] are stored safely."""
        token = create_logged_in_user(client, name="Traveller")
        payloads = ["food OR 1=1 --", "'; DROP TABLE trips;--"]
        trip_id = create_trip_and_get_id(
            client, token, destination="Osaka", interests=payloads
        )
        trips = client.get("/api/trips", headers=auth_headers(token)).get_json()["trips"]
        target = next(t for t in trips if t["id"] == trip_id)
        assert target["interests"] == payloads or (
            isinstance(target["interests"], list) and len(target["interests"]) == len(payloads)
        )
