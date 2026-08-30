# Tripora Security Tests

Automated pytest suite that exercises the local Tripora backend's security
controls via Flask's **test client** (no uncontrolled network traffic). It
uses only synthetic test users and test data.

## Quick start

Run from the repository root:

```powershell
# Windows (uses the backend virtualenv which already has pytest)
& .\backend\venv\Scripts\python.exe -m pytest security/tests -v
```

Or, if `pytest` is on your `PATH`:

```powershell
pytest security/tests -v
```

A `pytest.ini` at the repo root sets `testpaths = security/tests`.

## What's covered

| Module | Category |
|--------|----------|
| `test_jwt_authentication.py` | P1 authentication bypass / P3 JWT security (no/empty/malformed/expired tokens, invalid signature, tampered payload, cross-user token, unauthenticated access) |
| `test_authorization_idor.py` | P2 broken authorization / IDOR (cross-user read/update/delete/regenerate, list scoping, account scoping) |
| `test_sql_injection.py` | P4 SQL injection resistance (register/login/trip fields) |
| `test_input_validation.py` | P5 input validation / P6 missing fields / P7 invalid data types |

## Test isolation (reusable config)

`conftest.py` provides the app + client and guarantees isolation:

- **No production MySQL records are touched.** By default the suite overrides
  the SQLAlchemy URI to an **in-memory SQLite** database that is created
  empty per test and dropped afterwards.
- **No real credentials are read or required.** Dummy env values
  (`DB_*`, `JWT_SECRET_KEY`, `GEMINI_API_KEY`) are set for test construction.
  The real `backend/.env` is never read.
- **No external network calls.** The Gemini AI itinerary call is stubbed with
  a deterministic fixture, so tests never reach a third-party API and incur
  no cost.

### Pointing at a real MySQL *test* database (optional)

If you want to exercise MySQL itself (still on a dedicated, throwaway test
database — never the production DB), set `TRIPORA_TEST_DB_URI` before running:

```powershell
$env:TRIPORA_TEST_DB_URI = "mysql+pymysql://<test_user>:<test_pass>@127.0.0.1:3306/tripora_security_test"
& .\backend\venv\Scripts\python.exe -m pytest security/tests -v
```

> The database referenced by `TRIPORA_TEST_DB_URI` is treated as disposable:
> tests run `create_all()` and `drop_all()` against it.

## Notes / conventions

- Tests assert the **current** backend behaviour for a few documented gaps
  (e.g. no email-format validation, `bool` accepted as `travelers`). These are
  marked `CONFIRMED GAP` in docstrings and will fail loudly if the app is ever
  hardened — that is intentional, so a fix becomes a visible assertion update.
- No application code in `backend/` is modified by this suite.
