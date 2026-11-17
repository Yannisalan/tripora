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

CI runs the security suite from the repository root with:

```bash
python -m pytest security/tests -q -m "not integration"
```

The `not integration` marker filter keeps tests that need live credentials or
external services out of CI; the security suite itself uses stubs and
in-memory databases.

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
  (`DB_*`, `JWT_SECRET_KEY`, `GROQ_API_KEY`) are set for test construction.
  The real `backend/.env` is never read.
- **No external network calls.** The Groq AI itinerary call is stubbed with
  a deterministic fixture, so tests never reach a third-party API and incur
  no cost.

## Test database configuration

### Default: in-memory SQLite

Every test uses a fresh **in-memory SQLite** database (`sqlite:///:memory:`)
by default. It is created empty per test and dropped afterwards, so no
database credentials, external database, or network connection are required.

### External test database (opt-in only)

`conftest.py` fails closed for any non-memory database. It refuses to run
unless **all** of the following are true:

1. `TRIPORA_TEST_DB_URI` contains a valid SQLAlchemy URL.
2. `TRIPORA_ALLOW_EXTERNAL_TEST_DB` is set to exactly
   `I_UNDERSTAND_THIS_IS_A_DISPOSABLE_TEST_DATABASE`
   (vague values such as `true` or `1` are rejected).
3. The database name contains a disposable marker: `test`, `ci`, `temp`,
   `tmp`, `disposable`, `scratch`, or `sandbox`.

The database name must also **not** contain any unsafe marker: `prod`,
`production`, `live`, `stage`, `staging`, `shared`, `primary`, or `master`.
Any unsafe marker vetoes the target even when the opt-in is present.

Example (PowerShell), using a dedicated throwaway database on a local host:

```powershell
$env:TRIPORA_ALLOW_EXTERNAL_TEST_DB = "I_UNDERSTAND_THIS_IS_A_DISPOSABLE_TEST_DATABASE"
$env:TRIPORA_TEST_DB_URI = "mysql+pymysql://<test_user>:<test_pass>@127.0.0.1:3306/tripora_security_test"
& .\backend\venv\Scripts\python.exe -m pytest security/tests -v
```

> **Warning:** the opt-in only confirms that you intentionally enabled an
> external target. It does **not** independently establish that the remote
> database is disposable. Verify the host and database ownership yourself.
> The suite runs `create_all()` and `drop_all()`, so never point it at
> production, staging, shared, or otherwise important data. Use only a
> dedicated, throwaway database that you own.

Invalid URLs and rejected targets raise an error that names the policy
without echoing the URI or credentials.

## Notes / conventions

- Tests assert the **current** backend behaviour for a few documented gaps
  (e.g. no email-format validation, `bool` accepted as `travelers`). These are
  marked `CONFIRMED GAP` in docstrings and will fail loudly if the app is ever
  hardened — that is intentional, so a fix becomes a visible assertion update.
- No application code in `backend/` is modified by this suite.
