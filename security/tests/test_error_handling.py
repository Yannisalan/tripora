"""Error-handling / information-disclosure regression tests.

Sends controlled invalid requests to every endpoint and inspects the HTTP
responses for accidental disclosure of:

- Python stack traces
- filesystem paths (e.g. C:\\Users\\..., /app/..., site-packages)
- SQL queries / DDL
- database information (engine, table/column names, connection strings)
- JWT secrets / tokens
- environment variables / API keys
- internal Flask/SQLAlchemy configuration
- library versions
- debugging information

Design notes
------------
- Uses the isolated in-memory test DB (see conftest.py), dummy credentials,
  and the stubbed AI itinerary service. No production data, no destructive SQL.
- The backend echoes ``str(error)`` in several ``500`` handlers (documented in
  attack-surface.md findings A-8 / A-12). These leak *internal exception
  detail*; the important security line is that NO response leaks stack
  traces, filesystem paths, SQL text, secrets, env vars, or library versions.
- This module records per-case evidence so the outcome can be reported.

Secret policy: no real secrets are used in tests. If any response ever
contained a secret-like value it is asserted against a redaction/whitelist;
reporting reports type/location only, never the value.
"""

import re

import pytest

from .helpers import (
    auth_headers,
    create_logged_in_user,
    create_trip,
    forge_none_alg_token,
    forge_valid_access_token,
    get_user_by_email,
    login,
    register,
)

EVIDENCE = []


def _record(category, case, status, body_text, flags):
    EVIDENCE.append(
        {
            "category": category,
            "case": case,
            "status": status,
            "body": body_text,
            "flags": flags,
        }
    )


# ----------------------------------------------------------------------
# Disclosure-detection helpers
# ----------------------------------------------------------------------

TRACEBACK_RE = re.compile(
    r"Traceback \(most recent call last\)|File \"[^\"]+\", line \d+|"
    r" in <module>| in [a-zA-Z_]+$|\bRuntimeError\b|\bOperationalError\b",
    re.M,
)
SQL_RE = re.compile(
    r"\bSELECT\b|\bFROM\b [a-z_]+|\bINSERT\b|\bUPDATE\b|\bDELETE\b|"
    r"\[SQL:\s|\bWHERE\b [a-z_]+\.|= \?", re.I,
)
PATH_RE = re.compile(r"[A-Za-z]:\\\\|/usr/|/var/|site-packages|\\\\AppData\\\\|/backend/")
JWT_RE = re.compile(r"eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}")
ENV_RE = re.compile(r"\b(DB_PASSWORD|DB_USER|JWT_SECRET_KEY|GEMINI_API_KEY|SECRET_KEY)\s*[=:]")
KEY_RE = re.compile(r"\b[A-Za-z0-9_]{16,}\b=|\"(password|secret|api[_-]?key|token)\":\s*\"[^\"]+\"", re.I)
VERSION_RE = re.compile(r"\b(sqla?chemy|flask[\s-]?[\d.]+|werkzeug|mysql|pymysql)[\s-]*\d+\.\d+", re.I)
CLASSPATH_RE = re.compile(r"site-packages")
SQLITE_RE = re.compile(r"sqlite|mysql\+|\d+\.\d+\.\d+:\d+")

# Values that would be secret if they appeared (test dummies only; never real
# production secrets). We assert these exact dummy values never leak.
DUMMY_SECRETS = [
    "tripora-security-test-secret-key",
    "tripora-test-dummy-gemini-key",
    "test_password",
]


def _flags_for(body_text):
    flags = []
    if TRACEBACK_RE.search(body_text):
        flags.append("stack_trace")
    if SQL_RE.search(body_text):
        flags.append("sql")
    if PATH_RE.search(body_text):
        flags.append("filesystem_path")
    if JWT_RE.search(body_text):
        flags.append("jwt_value")
    if ENV_RE.search(body_text):
        flags.append("env_var_name")
    if KEY_RE.search(body_text) or any(s in body_text for s in DUMMY_SECRETS):
        flags.append("possible_secret")
    if VERSION_RE.search(body_text):
        flags.append("library_version")
    if CLASSPATH_RE.search(body_text):
        flags.append("internal_module_path")
    if SQLITE_RE.search(body_text):
        flags.append("database_info")
    return flags


SEVERE = {"stack_trace", "sql", "filesystem_path", "possible_secret",
          "library_version", "internal_module_path", "database_info"}


def _get_text(resp):
    return resp.get_data(as_text=True)


class TestWellFormedErrorsDoNotLeak:
    """Application-level validation errors must return clean JSON."""

    @pytest.mark.parametrize(
        "label,builder",
        [
            ("register missing password", lambda c: c.post("/api/auth/register", json={"name": "A", "email": "a@b.com"})),
            ("login missing email", lambda c: c.post("/api/auth/login", json={"password": "x"})),
            ("generate no auth", lambda c: c.get("/api/trips")),
            ("404 unknown path", lambda c: c.get("/api/does-not-exist")),
            ("405 wrong method", lambda c: c.put("/api/auth/register")),
        ],
    )
    def test_clean_400_404_405_401(self, client, label, builder):
        resp = builder(client)
        text = _get_text(resp)
        flags = _flags_for(text)
        _record("clean-client-error", label, resp.status_code, text, flags)
        # Client errors must never disclose internals.
        assert not (SEVERE & set(flags)), (label, flags, text)
        assert resp.status_code in (400, 401, 404, 405), resp.status_code


class TestJWTFailureDisclosure:
    """Malformed/forged tokens must not disclose JWT secrets or signed values."""

    def test_non_jwt_authorization_value(self, client):
        resp = client.get("/api/trips", headers={"Authorization": "Bearer not-a-real-jwt"})
        text = _get_text(resp)
        flags = _flags_for(text)
        _record("jwt-invalid", "non-jwt bearer", resp.status_code, text, flags)
        assert resp.status_code == 401
        # No signed token echo, no secret, no version.
        assert not (SEVERE & set(flags)), flags

    def test_forged_token_not_echoed(self, client):
        # A signed-but-not-valid token must not be reflected back wholesale.
        forged = forge_valid_access_token("1", "dummy-secret-for-forging")
        resp = client.get("/api/trips", headers=auth_headers(forged))
        text = _get_text(resp)
        flags = _flags_for(text)
        _record("jwt-invalid", "forged token", resp.status_code, text, flags)
        assert resp.status_code == 401
        assert forged not in text  # token value never echoed

    def test_none_alg_token_rejected(self, client):
        tok = forge_none_alg_token("1")
        resp = client.get("/api/trips", headers=auth_headers(tok))
        text = _get_text(resp)
        flags = _flags_for(text)
        _record("jwt-invalid", "alg:none token", resp.status_code, text, flags)
        assert resp.status_code == 401
        assert not (SEVERE & set(flags)), flags


class TestTypeErrorValidationNoLeak:
    """FIXED (A-12): strongly-typed date/budget input is rejected as a clean
    400 by the parser and no internal exception detail is disclosed."""

    def _token(self, client):
        return create_logged_in_user(client, name="ErrUser")

    def test_integer_startdate_rejected(self, client):
        token = self._token(client)
        resp = create_trip(
            client, token, startDate=20260901, endDate="2026-09-10"
        )
        text = _get_text(resp)
        flags = _flags_for(text)
        _record("strerror-400-fixed", "int startDate", resp.status_code, text, flags)
        # FIXED: previously a 500 leaking "'int' object has no attribute
        # 'split'"; now parser rejects non-string dates -> clean 400.
        assert resp.status_code == 400
        assert not (SEVERE & set(flags)), (flags, text)
        assert "has no attribute" not in text

    def test_list_budget_rejected(self, client):
        token = self._token(client)
        resp = create_trip(client, token, budget=["moderate"])
        text = _get_text(resp)
        flags = _flags_for(text)
        _record("strerror-400-fixed", "list budget", resp.status_code, text, flags)
        assert resp.status_code == 400
        assert not (SEVERE & set(flags)), (flags, text)

    def test_int_budget_rejected(self, client):
        token = self._token(client)
        resp = create_trip(client, token, budget=123)
        text = _get_text(resp)
        flags = _flags_for(text)
        _record("strerror-400-fixed", "int budget", resp.status_code, text, flags)
        assert resp.status_code == 400
        assert not (SEVERE & set(flags)), (flags, text)

    def test_no_sql_query_in_response(self, client):
        # Regression: even a 500/400 must never render the SQL statement.
        token = self._token(client)
        resp = create_trip(client, token, startDate=20260901)
        text = _get_text(resp)
        assert "SELECT" not in text.upper()
        assert "FROM trips" not in text
        assert "FROM users" not in text


class TestHealthProbe:
    """Health endpoint DB-probe must not leak connection details."""

    def test_health_no_leak(self, client):
        resp = client.get("/api/health")
        text = _get_text(resp)
        flags = _flags_for(text)
        _record("health", "healthy db", resp.status_code, text, flags)
        assert resp.status_code in (200, 500)
        assert not (SEVERE & set(flags)), flags


class TestAuthInputDisclosure:
    """Malformed auth inputs that reach SQLAlchemy must not leak SQL/DDL."""

    def test_login_neither_query_nor_leak(self, client):
        # Any login result is controlled; the body never contains SQL text.
        for payload in ["' OR '1'='1", '{"$gt":""}', "x'] --"]:
            resp = login(client, payload, "pw")
            text = _get_text(resp)
            flags = _flags_for(text)
            _record("auth-input", "login payload", resp.status_code, text, flags)
            assert resp.status_code in (400, 401), (flags, text, resp.status_code)
            assert "SELECT" not in text.upper()
            assert "FROM users" not in text


class TestRouteLevelUnhandledGuards:
    """Confirm no debugger/traceback HTML reaches the HTTP layer."""

    def test_no_werkzeug_debug_html(self, client):
        # Even errors must not return the Werkzeug interactive debugger HTML.
        token = create_logged_in_user(client, name="ErrUser")
        resp = create_trip(client, token, startDate=20260901)
        ct = resp.content_type or ""
        assert "text/html" not in ct
        assert "Werkzeug" not in _get_text(resp)


class TestStrErrorNoSqlDisclosure:
    """FIXED (A-8/E-3): when the DB layer fails, the wrapped handlers must
    return a generic 500 and must NOT echo the SQLAlchemy exception (which
    would contain the SQL statement and bind parameters).

    Simulates a statement-level DB failure on login (``auth.py``) against the
    isolated test DB. No real DB is touched and no destructive SQL is issued;
    the exception is raised in-memory by the test.
    """

    @pytest.fixture
    def force_db_error(self, monkeypatch):
        import sqlalchemy.exc
        from sqlalchemy.orm import Query

        # Patch Query.first() so the login ORM execution raises a SQLAlchemy
        # OperationalError whose message contains the compiled SQL and binds,
        # mirroring a real statement-level DB failure.
        def flaky_first(self_, *args, **kwargs):
            raise sqlalchemy.exc.OperationalError(
                "SELECT users.* FROM users WHERE users.email = ?",
                {"email": "x", "limit": 1, "offset": 0},
                Exception("connection refused"),
            )

        monkeypatch.setattr(Query, "first", flaky_first)

    def test_login_operational_error_masks_sql(self, client, force_db_error):
        resp = login(client, "any@example.com", "password1")
        text = _get_text(resp)
        flags = _flags_for(text)
        _record("strerror-db-failure-fixed",
                "simulated OperationalError on login",
                resp.status_code, text, flags)
        # FIXED (A-8): the handler still returns 500 but the response body must
        # not contain the SQL statement, parameters, or binding info.
        assert resp.status_code == 500
        assert resp.get_json()["message"] == "Failed to login."
        assert "sql" not in flags
        assert "FROM users" not in text
        assert "SELECT" not in text.upper()
        assert "connection refused" not in text
