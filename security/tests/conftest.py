"""Reusable test configuration for the local Tripora backend security tests.

This module is loaded by pytest as `conftest.py`. It:

1. Puts the Tripora backend package on ``sys.path`` so the app and models
   can be imported from ``security/tests/``.
2. Provides a hermetic, isolated test database (SQLite in-memory by default)
   so NO production MySQL records are ever touched and no real credentials
   are required.
3. Stubs the Gemini AI itinerary call so tests never make external network
   requests and never incur API cost.

Environment overrides
---------------------
- ``TRIPORA_TEST_DB_URI``: If set, use this SQLAlchemy URI instead of the
  default in-memory SQLite. This lets maintainers point the suite at a
  dedicated MySQL *test* database (e.g.
  ``mysql+pymysql://user:pass@127.0.0.1:3306/tripora_security_test``).
  Any database referenced here is assumed to be a throwaway test DB.

All dummy env values below are set BEFORE the backend is imported so the
app constructs successfully without reading the real ``backend/.env``.
"""

import os
import sys
from pathlib import Path

from sqlalchemy.pool import StaticPool

# ----------------------------------------------------------------------
# 1. Make the backend importable from this directory
# ----------------------------------------------------------------------

BACKEND_DIR = str(Path(__file__).resolve().parents[2] / "backend")
if BACKEND_DIR not in sys.path:
    sys.path.insert(0, BACKEND_DIR)

# ----------------------------------------------------------------------
# 2. Dummy environment values (never read from backend/.env)
# ----------------------------------------------------------------------
# These satisfy the Config class validation (which raises if DB_* /
# JWT_SECRET_KEY are missing) and let services/imports complete. They are
# dummy values for test construction only; the DB URI is overridden below.
os.environ.setdefault("DB_USER", "test_user")
os.environ.setdefault("DB_PASSWORD", "test_password")
os.environ.setdefault("DB_HOST", "127.0.0.1")
os.environ.setdefault("DB_PORT", "3306")
os.environ.setdefault("DB_NAME", "tripora_security_test")
os.environ.setdefault("JWT_SECRET_KEY", "tripora-security-test-secret-key-not-for-production")
os.environ.setdefault("GEMINI_API_KEY", "tripora-test-dummy-gemini-key")
os.environ.setdefault("ADMIN_API_TOKEN", "tripora-test-admin-token")
# Rate limiting is OFF for the pre-existing security suite so those tests
# behave exactly as they did before the feature was added (several issue many
# generate/write requests in a single test). The dedicated module
# test_rate_limiting.py explicitly enables tight limits and asserts the 429
# behaviour; Config still reads its limit/window defaults from the (unset)
# environment for the assertion tests.
os.environ.setdefault("RATE_LIMIT_ENABLED", "false")

# Request-logging (the analytics after_request hook) writes a row per request,
# which serializes badly on the suite's single shared in-memory SQLite
# connection and slows/hangs many-request tests. The dedicated admin tests
# exercise the analytics endpoints directly, so keep it OFF here for speed and
# isolation -- exactly like RATE_LIMIT_ENABLED above.
os.environ.setdefault("REQUEST_LOGGING_ENABLED", "false")

# Force log-only (placeholder) email delivery instead of a real SMTP send.
# Without these, ``load_dotenv()`` in ``config/settings.py`` can pull real
# Gmail credentials out of ``backend/.env`` and every test that registers a
# user would attempt a real (and rate-limited / slow) SMTP delivery. python-
# dotenv does not override env vars that already exist, so assigning empty
# values here keeps ``_email_configured()`` False and the suite hermetic.
for _mail_var in ("MAIL_HOST", "MAIL_PORT", "MAIL_USER", "MAIL_PASSWORD",
                  "MAIL_FROM", "MAIL_FROM_NAME", "MAIL_USE_TLS"):
    os.environ.setdefault(_mail_var, "")


def _test_database_uri():
    """Return the SQLAlchemy URI for the isolated test database."""
    override = os.environ.get("TRIPORA_TEST_DB_URI")
    if override:
        return override
    return "sqlite:///:memory:"


# ----------------------------------------------------------------------
# Imports must happen AFTER the dummy env values are set above.
# ----------------------------------------------------------------------
import pytest
from datetime import date, timedelta

import routes.trips as trips_module
from app import create_app
from config.database import db as _db
from config.settings import Config
from services.rate_limiter import limiter

# ----------------------------------------------------------------------
# AI itinerary stub
# ----------------------------------------------------------------------


def _stub_generate_itinerary(
    destination,
    start_date,
    end_date,
    travelers,
    budget,
    travel_style,
    interests,
):
    """Deterministic itinerary stand-in for the Gemini service.

    Produces one day per calendar day with Morning/Afternoon/Evening
    activities, matching the schema the backend expects, so the trip
    generation flow works without any external API call.
    """
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
                    for slot in ["Morning", "Afternoon", "Evening"]
                ],
            }
        )
    return {"itinerary": itinerary}


@pytest.fixture(autouse=True)
def stub_ai(monkeypatch):
    """Ensure every test uses the deterministic itinerary stub.

    Route handlers reference ``generate_itinerary`` by the name imported
    into the ``routes.trips`` module namespace, so we patch that symbol.
    This guarantees no real Gemini network calls and no API cost.
    """
    monkeypatch.setattr(trips_module, "generate_itinerary", _stub_generate_itinerary)


@pytest.fixture(autouse=True)
def reset_rate_limits():
    """Clear the shared rate-limiter state before every test.

    The limiter is a process-wide singleton (in-memory backend). Clearing it
    per test gives each test an isolated budget so the app's rate limits do
    not spill across tests and break existing behavior. Rate-limit tests craft
    their own bursts within a single test to trip a limit deliberately.
    """
    limiter.reset()
    yield
    limiter.reset()


@pytest.fixture
def app():
    """Function-scoped app with an isolated, freshly created database.

    The test URI is applied to the ``Config`` class BEFORE ``create_app()``
    so ``app.config.from_object(Config)`` picks up the isolated database
    (rather than the MySQL URI computed at Config import time). This avoids
    any engine being bound to the production MySQL database.
    """
    db_uri = _test_database_uri()
    engine_options = {}
    if db_uri.startswith("sqlite:///:memory:"):
        # A single shared in-memory connection is required so tables created
        # in the app context are visible to request-scoped sessions.
        engine_options = {
            "poolclass": StaticPool,
            "connect_args": {"check_same_thread": False},
        }

    Config.SQLALCHEMY_DATABASE_URI = db_uri
    Config.SQLALCHEMY_ENGINE_OPTIONS = engine_options

    application = create_app()
    application.config.update(TESTING=True)

    with application.app_context():
        _db.create_all()
        yield application
        _db.session.remove()
        _db.drop_all()


@pytest.fixture
def client(app):
    """Flask test client bound to the isolated app."""
    return app.test_client()


def pytest_sessionfinish(session, exitstatus):
    """Persist per-case evidence gathered by security test modules.

    Any module defining a module-level ``EVIDENCE`` list of dicts (with keys
    category/case/status/body/exception_exposed) is dumped to
    ``security/reports/_generate_trip_evidence.json`` for report generation.
    """
    import importlib
    import json as _json
    import os

    evidence = []
    # Scan all collected test items for their module-level EVIDENCE list.
    seen = set()
    for item in session.items:
        mod = item.module
        if id(mod) in seen:
            continue
        seen.add(id(mod))
        data = getattr(mod, "EVIDENCE", None)
        if isinstance(data, list) and data:
            evidence.extend(data)

    if not evidence:
        return

    out = os.path.abspath(
        os.path.join(os.path.dirname(__file__), "..", "reports", "_generate_trip_evidence.json")
    )
    with open(out, "w", encoding="utf-8") as fh:
        _json.dump(evidence, fh, indent=2, ensure_ascii=False)
