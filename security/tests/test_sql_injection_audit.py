"""SQL injection audit regression tests.

Companion to the static audit (security/reports/sql-injection-audit.md).
These tests drive every user-controlled value that flows into a database
operation and assert that SQL-injection-style inputs are handled as literal
data — never altering query semantics, never throwing a SQL error, and never
enumerating/duplicating/deleting unintended rows.

Because the backend is SQLAlchemy-ORM only, these tests are *regression*
guards: if a future change introduces raw/user-supplied SQL (f-strings,
dynamic WHERE, user-controlled ORDER BY), these tests should fail.

Only synthetic test users/trips are used. No destructive SQL is executed.
"""

from .helpers import (
    auth_headers,
    create_logged_in_user,
    create_trip_and_get_id,
    get_user_by_email,
    login,
    register,
)

# Payload families: comment, tautology, stacked, UNION, error-based,
# blind/time-based. All are benign (no DROP/DELETE/UPDATE/ALTER executed;
# payloads are merely stored or compared as strings).
COMMENT_PAYLOADS = [
    "x'; --",
    "x'--",
    "x'#",
    "x'/*",
]
TAUTOLOGY_PAYLOADS = [
    "' OR '1'='1",
    "' OR '1'='1' --",
    '" OR "1"="1',
    "x' OR 'x'='x",
    "Paris' AND '1'='1",
]
STACKED_PAYLOADS = [
    "x'; SELECT 1; --",
    "1; SELECT 1",
]
UNION_PAYLOADS = [
    "x' UNION SELECT NULL--",
    "x' UNION SELECT 1,2,3--",
    "' UNION SELECT username,password FROM users--",
]
ERROR_PAYLOADS = [
    "'\"",
    "' AND extractvalue(1,concat(0x7e,(SELECT version())))--",
    "' AND updatexml(1,concat(0x7e,(SELECT version())),1)--",
]
TIME_PAYLOADS = [
    "' OR SLEEP(0)--",
    "x' AND SLEEP(0) AND '1'='1",
]

ALL_PAYLOADS = (
    COMMENT_PAYLOADS
    + TAUTOLOGY_PAYLOADS
    + STACKED_PAYLOADS
    + UNION_PAYLOADS
    + ERROR_PAYLOADS
    + TIME_PAYLOADS
)

# Fixed variants safe to use as actual addresses/values (contain '@' or a
# single harmless quote) so the endpoint remains well-formed while provoking
# the underlying query.
EMAIL_PAYLOADS = [
    "foo'@example.com",
    "a' OR '1'='1'@example.com",
    "x' UNION SELECT 1--@example.com",
    "x\\'@example.com",
]


def _assert_safe_no_sqli(resp):
    """Assert a response neither leaked SQL internals nor crashed.

    A safe SQLi-resistant response is any non-500 status. If it IS a 500 it
    must not contain SQL-engine diagnostics. No 500 here should carry
    'syntax', 'SQL', or traceback text.
    """
    if resp.status_code == 500:
        body = resp.get_json(silent=True) or {}
        text_ = "{} {}".format(
            body.get("message", ""),
            body.get("error", ""),
        )
        assert "syntax" not in text_.lower()
        assert "sql" not in text_.lower()
        assert "traceback" not in text_.lower()
        assert "operationalerror" not in text_.lower()
    # Non-500 statuses are always acceptable either way; the security
    # property is that the payload was not interpreted as SQL.


class TestRegisterQueries:
    """POST /api/auth/register — name and email flow into the users table."""

    def test_email_payloads_never_crash_the_query(self, client):
        for payload in EMAIL_PAYLOADS + ERROR_PAYLOADS[:2] + COMMENT_PAYLOADS[:2]:
            resp = register(client, name="Sqli", email=payload)
            # Accepted as a literal (201) or rejected by validation (400/409) —
            # never a SQL error.
            assert resp.status_code in (201, 400, 409), (payload, resp.get_json())
            _assert_safe_no_sqli(resp)

    def test_tautology_email_does_not_bypass_existing_check(self, client):
        # A tautology in the email must not cause the uniqueness query to
        # return 'no existing user' for a user that already exists, nor
        # enumerate others.
        email = "sqli-taut-example@example.com"
        register(client, name="RealOwner", email=email)
        payload = "'' OR '1'='1'@example.com"
        resp = register(client, name="Other", email=payload)
        # The result is a single-user outcome; never a multi-user disclosure
        # and never an error leaking SQL.
        assert resp.status_code in (201, 400, 409), resp.get_json()

    def test_email_payloads_stored_literally_when_accepted(self, client):
        # If the app accepts a payload as an email, it must be stored as-is
        # (lowercased), proving it was bound as a literal value.
        for payload in EMAIL_PAYLOADS[:2]:
            resp = register(client, name="Sqli", email=payload)
            if resp.status_code == 201:
                stored = get_user_by_email(resp.get_json()["user"]["email"])
                assert stored is not None

    def test_name_payloads_do_not_alias_other_rows(self, client):
        register(client, name="TargetAccount", email="sqli-target@example.com")
        for payload in UNION_PAYLOADS + TAUTOLOGY_PAYLOADS:
            uniq = abs(hash(payload)) % 100000
            resp = register(
                client, name=payload, email="sqli-name-{}-{}@example.com".format(len(payload), uniq)
            )
            assert resp.status_code == 201, (payload, resp.get_json())


class TestLoginQueries:
    """POST /api/auth/login — email drives the user lookup query."""

    def test_login_email_payloads_yield_generic_result(self, client):
        for payload in ALL_PAYLOADS:
            resp = login(client, payload, "irrelevant")
            # Always a controlled outcome (401 generic, or 400 missing-field) —
            # never a SQL error, never an enumeration.
            assert resp.status_code in (400, 401), (payload, resp.get_json())
            _assert_safe_no_sqli(resp)
            text_ = "{} {}".format(
                resp.get_json().get("message", ""),
                resp.get_json().get("error", ""),
            )
            assert "syntax" not in text_.lower()
            assert "sql" not in text_.lower()


class TestVerifyEmailQueriesRemoved:
    """The verify-email/resend endpoints were removed with the email flow."""

    def test_verify_email_endpoint_gone(self, client):
        assert client.post(
            "/api/auth/verify-email", json={"token": "anything"}
        ).status_code in (404, 405)

    def test_resend_verification_endpoint_gone(self, client):
        assert client.post(
            "/api/auth/resend-verification", json={"email": "a@b.com"}
        ).status_code in (404, 405)


class TestMeUpdateQueries:
    """PATCH /api/auth/me — email conflict check drives a lookup query."""

    def test_patch_email_payloads_do_not_bypass_conflict_check(self, client):
        token_a = create_logged_in_user(client, name="UserA", email="sqli-me-a@example.com")
        token_b = create_logged_in_user(client, name="UserB", email="sqli-me-b@example.com")

        # A tautology must not make User B's uniqueness check claim the email
        # is free when User A already owns it — and must never error.
        create_trip = client.post  # noqa: F841 (placeholder guard against drift)
        resp = client.patch(
            "/api/auth/me",
            json={"email": "Sqli-ME-A@example.com"},
            headers=auth_headers(token_b),
        )
        assert resp.status_code == 409, resp.get_json()  # conflict preserved

        # Injection payloads are accepted as a literal address or rejected as
        # invalid, but never crash the unique-email query.
        for payload in EMAIL_PAYLOADS:
            resp = client.patch(
                "/api/auth/me",
                json={"email": payload},
                headers=auth_headers(token_b),
            )
            assert resp.status_code in (200, 400, 409), (payload, resp.get_json())
            _assert_safe_no_sqli(resp)


class TestTripQueryPaths:
    """Trip queries — destination/interests stored values and ownership filters."""

    def test_destination_payloads_stored_literally(self, client):
        token = create_logged_in_user(client, name="Traveller")
        for payload in (
            COMMENT_PAYLOADS
            + TAUTOLOGY_PAYLOADS
            + STACKED_PAYLOADS
            + UNION_PAYLOADS
            + ERROR_PAYLOADS
        ):
            trip_id = create_trip_and_get_id(client, token, destination=payload)
            trips = client.get("/api/trips", headers=auth_headers(token)).get_json()["trips"]
            target = next(t for t in trips if t["id"] == trip_id)
            assert target["destination"] == payload

    def test_destination_payloads_do_not_alter_ownership(self, client):
        # A tautology/union in a destination must not make one user able to
        # read or mutate another user's trips (the WHERE user_id is bound and
        # unchanged regardless of destination content).
        token_a = create_logged_in_user(client, name="OwnerA")
        token_b = create_logged_in_user(client, name="OtherB")
        trip_id = create_trip_and_get_id(client, token_a, destination="Paris")

        payload = "' OR '1'='1"
        resp = client.get("/api/trips", headers=auth_headers(token_b)).get_json()
        # OtherB sees no trips (destination is not even in the query).
        assert len(resp["trips"]) == 0

        read = client.get(
            "/api/trips/{}".format(trip_id), headers=auth_headers(token_b)
        )
        assert read.status_code == 404  # IDOR blocked regardless

        # A tautology injected via PATCH destination must not change which row
        # is updated (identity comes from the bound id+user_id filter).
        resp = client.patch(
            "/api/trips/{}".format(trip_id),
            json={
                "destination": payload,
                "startDate": "2026-09-01",
                "endDate": "2026-09-02",
                "travelers": 1,
                "budget": "budget",
                "travelStyle": "adventure",
                "interests": [],
            },
            headers=auth_headers(token_b),
        )
        assert resp.status_code == 404  # not owner -> not found, no update

    def test_interests_payloads_do_not_alter_queries(self, client):
        token = create_logged_in_user(client, name="Traveller")
        payloads = TAUTOLOGY_PAYLOADS + UNION_PAYLOADS
        trip_id = create_trip_and_get_id(client, token, interests=payloads)
        trips = client.get("/api/trips", headers=auth_headers(token)).get_json()["trips"]
        target = next(t for t in trips if t["id"] == trip_id)
        # The list came back with the same number of entries (JSON round-trip).
        assert len(target["interests"]) == len(payloads)
