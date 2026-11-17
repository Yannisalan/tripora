"""Reusable test configuration for the local Tripora backend security tests.

This module is loaded by pytest as conftest.py. It:

1. Puts the Tripora backend package on sys.path so the app and models
   can be imported from security/tests/.
2. Provides an isolated test database (SQLite in-memory by default).
3. Stubs Groq AI itinerary generation and weather requests so tests
   never make external API calls or incur API costs.
4. Disables all external email providers to prevent real emails from
   being sent during the test suite.

Environment overrides
---------------------
- TRIPORA_TEST_DB_URI:
  Optional SQLAlchemy URI for a dedicated disposable test database.
  The default is SQLite in-memory.  Any non-memory target is rejected
  unless TRIPORA_ALLOW_EXTERNAL_TEST_DB is set to the exact opt-in token
  below *and* the target database name clearly marks it as disposable.

WARNING:
Tests call ``create_all()`` and ``drop_all()``.  Never point
TRIPORA_TEST_DB_URI at a production, staging, or shared database.
"""

import os
import re
import sys
from pathlib import Path
from datetime import date, timedelta

from sqlalchemy.engine import make_url
from sqlalchemy.pool import StaticPool

# ----------------------------------------------------------------------
# 1. Make the backend importable from this directory
# ----------------------------------------------------------------------

BACKEND_DIR = str(Path(__file__).resolve().parents[2] / "backend")

if BACKEND_DIR not in sys.path:
    sys.path.insert(0, BACKEND_DIR)


# ----------------------------------------------------------------------
# 2. Isolated test environment
# ----------------------------------------------------------------------
# These values are deliberately assigned rather than set with setdefault().
# This prevents inherited Windows/CI environment variables from introducing
# production credentials or external service configuration into the tests.

os.environ["TRIPORA_ENV"] = "test"

# Dummy backend configuration.
os.environ["DB_USER"] = "test_user"
os.environ["DB_PASSWORD"] = "test_password"
os.environ["DB_HOST"] = "127.0.0.1"
os.environ["DB_PORT"] = "3306"
os.environ["DB_NAME"] = "tripora_security_test"

os.environ["JWT_SECRET_KEY"] = (
    "tripora-security-test-secret-key-not-for-production"
)

os.environ["GROQ_API_KEY"] = "tripora-test-dummy-groq-key"
os.environ["ADMIN_API_TOKEN"] = "tripora-test-admin-token"
os.environ["ADMIN_LEGACY_TOKEN_ENABLED"] = "true"

# Cloudflare Turnstile: off for the general suite (test_bot_protection.py
# turns it on per test). Explicit, so a developer's .env cannot enable it or
# leak a real secret into the run. Siteverify is additionally blocked below.
os.environ["TURNSTILE_ENABLED"] = "false"
os.environ["TURNSTILE_SECRET_KEY"] = ""
os.environ["TURNSTILE_SITE_KEY"] = ""
os.environ["TURNSTILE_ALLOWED_HOSTNAMES"] = ""

# Fresh random Fernet key per test session for admin TOTP secrets.
from cryptography.fernet import Fernet as _Fernet  # noqa: E402

os.environ["MFA_ENCRYPTION_KEY"] = _Fernet.generate_key().decode("ascii")

# Never let a developer's REDIS_URL leak into the unit suite; Redis tests
# opt in explicitly with TRIPORA_TEST_REDIS_URL.
os.environ["REDIS_URL"] = ""  # set (not popped) so backend/.env cannot fill it

# Disable external email delivery.
# Both SMTP and Resend are explicitly disabled, even if the developer's
# machine or CI environment contains real provider credentials.

for _mail_var in (
    "MAIL_HOST",
    "MAIL_PORT",
    "MAIL_USER",
    "MAIL_PASSWORD",
    "MAIL_FROM",
    "MAIL_FROM_NAME",
    "MAIL_USE_TLS",
    "RESEND_API_KEY",
):
    os.environ[_mail_var] = ""

# Rate limiting is disabled for the general security suite.
# Dedicated rate-limit tests explicitly enable limits when required.

os.environ["RATE_LIMIT_ENABLED"] = "false"

# Request logging is disabled to prevent analytics writes from interfering
# with tests using the shared in-memory SQLite connection.
# Dedicated admin tests exercise analytics endpoints separately.

os.environ["REQUEST_LOGGING_ENABLED"] = "false"


# ----------------------------------------------------------------------
# 3. Test database configuration
# ----------------------------------------------------------------------

DEFAULT_TEST_DATABASE_URI = "sqlite:///:memory:"

# External test databases are opt-in only.  The token is intentionally long
# and explicit so it cannot be set by accident or by a vague "true"/"1" value.
EXTERNAL_TEST_DB_OPT_IN_ENV = "TRIPORA_ALLOW_EXTERNAL_TEST_DB"
EXTERNAL_TEST_DB_OPT_IN_TOKEN = (
    "I_UNDERSTAND_THIS_IS_A_DISPOSABLE_TEST_DATABASE"
)

# A non-memory target must carry one of these markers in its database name.
_DISPOSABLE_DB_NAME_MARKERS = (
    "test",
    "ci",
    "temp",
    "tmp",
    "disposable",
    "scratch",
    "sandbox",
)

# These markers always veto an external target, even when an opt-in is set.
_UNSAFE_DB_NAME_MARKERS = (
    "prod",
    "production",
    "live",
    "stage",
    "staging",
    "shared",
    "primary",
    "master",
)


def _is_in_memory_sqlite(url):
    """Return True for SQLite URLs that do not touch a file on disk."""

    if url.get_backend_name() != "sqlite":
        return False

    return url.database in (None, "", ":memory:")


def _is_disposable_database_name(database_name):
    """Return True when a database name is clearly intended for tests."""

    normalized = re.sub(
        r"[^a-z0-9]+",
        "",
        str(database_name or "").lower(),
    )

    if not normalized:
        return False

    if any(marker in normalized for marker in _UNSAFE_DB_NAME_MARKERS):
        return False

    return any(
        marker in normalized for marker in _DISPOSABLE_DB_NAME_MARKERS
    )


def _test_database_uri():
    """Return the SQLAlchemy URI for the isolated test database.

    The in-memory SQLite default needs no opt-in.  Anything else is treated
    as an external target and fails closed unless both the explicit opt-in
    token and a disposable-looking database name are present.
    """

    override = os.environ.get("TRIPORA_TEST_DB_URI", "").strip()

    if not override:
        return DEFAULT_TEST_DATABASE_URI

    try:
        url = make_url(override)
    except Exception:
        # Never echo the URI: it may contain a username or password.
        raise RuntimeError(
            "TRIPORA_TEST_DB_URI is not a valid SQLAlchemy database URL."
        ) from None

    if _is_in_memory_sqlite(url):
        return override

    opt_in = os.environ.get(EXTERNAL_TEST_DB_OPT_IN_ENV, "").strip()

    if opt_in != EXTERNAL_TEST_DB_OPT_IN_TOKEN:
        raise RuntimeError(
            "Refusing to use an external test database. "
            "TRIPORA_TEST_DB_URI must be an in-memory SQLite URL, or "
            "{} must be set to the exact documented opt-in token."
            .format(EXTERNAL_TEST_DB_OPT_IN_ENV)
        )

    if not _is_disposable_database_name(url.database):
        raise RuntimeError(
            "Refusing to use an external test database whose name is not "
            "clearly disposable. Use a database name containing a marker "
            "such as 'test' and never a production/staging/shared name."
        )

    return override


# ----------------------------------------------------------------------
# 4. Backend imports
# ----------------------------------------------------------------------
# Imports happen only after the test environment has been configured.

import pytest

import routes.trips as trips_module

from app import create_app
from config.database import db as _db
from config.settings import Config
from services.rate_limiter import limiter


# ----------------------------------------------------------------------
# 5. AI itinerary stubs
# ----------------------------------------------------------------------

def _stub_generate_itinerary(
    destination,
    start_date,
    end_date,
    travelers,
    budget,
    travel_style,
    interests,
    language="en",
    weather=(),
    deadline=None,
):
    """Generate a deterministic test itinerary without calling Groq."""

    start = date.fromisoformat(str(start_date)[:10])
    end = date.fromisoformat(str(end_date)[:10])

    days = (end - start).days + 1

    itinerary = []

    for i in range(days):
        day_date = (start + timedelta(days=i)).isoformat()

        itinerary.append(
            {
                "day": i + 1,
                "title": f"Day {i + 1}",
                "date": day_date,
                "activities": [
                    {
                        "time": slot,
                        "title": f"{slot} activity",
                        "description": "Test description",
                        "category": "culture",
                    }
                    for slot in ("Morning", "Afternoon", "Evening")
                ],
            }
        )

    return {"itinerary": itinerary}


def _stub_generate_activity_swap(
    destination,
    day_number,
    day_date,
    time_slot,
    current_activity,
    day_activities,
    existing_titles,
    travelers,
    budget,
    travel_style,
    interests,
    language="en",
    day_weather=(),
    deadline=None,
):
    """Generate a deterministic replacement activity for testing."""

    return {
        "time": time_slot,
        "title": "Fusee Museum Tour",
        "description": "A quirky museum replacement activity.",
        "category": "Sightseeing",
        "location": "Marais District",
    }


# ----------------------------------------------------------------------
# 6. Automatically stub external AI and weather services
# ----------------------------------------------------------------------

@pytest.fixture(autouse=True)
def stub_ai(monkeypatch):
    """Prevent tests from making real Groq or weather API requests."""

    monkeypatch.setattr(
        trips_module,
        "generate_itinerary",
        _stub_generate_itinerary,
    )

    monkeypatch.setattr(
        trips_module,
        "generate_activity_swap",
        _stub_generate_activity_swap,
    )

    monkeypatch.setattr(
        trips_module,
        "get_forecast_for_generation",
        lambda *args, **kwargs: [],
    )


# ----------------------------------------------------------------------
# 7. Rate-limit isolation
# ----------------------------------------------------------------------

# Verification emails sent during a test: {email: [code, ...]} (newest last).
# Stands in for the user's inbox; nothing is delivered.
SENT_VERIFICATION_CODES = {}


@pytest.fixture(autouse=True)
def capture_verification_emails(monkeypatch):
    """Record verification codes instead of emailing them."""
    import routes.auth as auth_routes

    SENT_VERIFICATION_CODES.clear()

    def _capture(to_email, code):
        SENT_VERIFICATION_CODES.setdefault(to_email, []).append(code)
        return True

    monkeypatch.setattr(auth_routes, "send_verification_code", _capture)
    monkeypatch.setattr(
        auth_routes, "send_existing_account_notice", lambda to_email: True,
    )
    yield SENT_VERIFICATION_CODES
    SENT_VERIFICATION_CODES.clear()


@pytest.fixture(autouse=True)
def block_real_turnstile(monkeypatch):
    """No test may reach Cloudflare. Tests that need Siteverify patch
    ``services.turnstile._siteverify_post`` with a mocked response."""
    import services.turnstile as turnstile_service

    attempted = []

    def _no_network(form, timeout):
        # verify() treats any exception as "unavailable", so record the call
        # and fail the test at teardown instead of relying on the raise.
        attempted.append(True)
        raise RuntimeError("Tests must not call Cloudflare Siteverify.")

    monkeypatch.setattr(turnstile_service, "_siteverify_post", _no_network)
    yield
    assert not attempted, "A test tried to call Cloudflare Siteverify."


@pytest.fixture(autouse=True)
def reset_rate_limits():
    """Reset shared rate-limiter state before and after every test."""

    limiter.reset()

    yield

    limiter.reset()


# ----------------------------------------------------------------------
# 8. Flask application fixture
# ----------------------------------------------------------------------

@pytest.fixture
def app():
    """Create an application with an isolated test database."""

    db_uri = _test_database_uri()

    engine_options = {}

    if db_uri.startswith("sqlite:///:memory:"):
        engine_options = {
            "poolclass": StaticPool,
            "connect_args": {
                "check_same_thread": False,
            },
        }

    # Apply the test database configuration before creating the app.
    Config.SQLALCHEMY_DATABASE_URI = db_uri
    Config.SQLALCHEMY_ENGINE_OPTIONS = engine_options

    application = create_app()

    application.config.update(
        TESTING=True,
    )

    with application.app_context():
        _db.create_all()

        yield application

        _db.session.remove()
        _db.drop_all()


# ----------------------------------------------------------------------
# 9. Flask test client fixture
# ----------------------------------------------------------------------

@pytest.fixture
def client(app):
    """Return a Flask test client bound to the isolated application."""

    return app.test_client()


# ----------------------------------------------------------------------
# 10. Security test evidence collection
# ----------------------------------------------------------------------

def pytest_sessionfinish(session, exitstatus):
    """Persist evidence collected by security test modules.

    Modules can define a module-level EVIDENCE list containing dictionaries
    with the following keys:

    category, case, status, body, exception_exposed.
    """

    import json

    evidence = []
    seen = set()

    for item in session.items:
        module = item.module

        if id(module) in seen:
            continue

        seen.add(id(module))

        data = getattr(module, "EVIDENCE", None)

        if isinstance(data, list) and data:
            evidence.extend(data)

    if not evidence:
        return

    output_path = os.path.abspath(
        os.path.join(
            os.path.dirname(__file__),
            "..",
            "reports",
            "_generate_trip_evidence.json",
        )
    )

    os.makedirs(os.path.dirname(output_path), exist_ok=True)

    with open(output_path, "w", encoding="utf-8") as file:
        json.dump(
            evidence,
            file,
            indent=2,
            ensure_ascii=False,
        )
