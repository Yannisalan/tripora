# Tripora Backend — Error-Handling / Information-Disclosure Report

**Scope:** Local Tripora backend (authorized for testing). Controlled invalid requests were sent to every endpoint and the HTTP responses were inspected for disclosure of stack traces, filesystem paths, SQL queries, database information, JWT secrets, environment variables, API keys, internal Flask configuration, library versions, and debugging information.
**Method:** Black-box requests via the Flask test client against the isolated in-memory test DB (dummy credentials, stubbed AI service). 19 automated regression tests in `security/tests/test_error_handling.py`; full suite **155 tests passed**.
**Secret policy:** No real secrets are used in tests. Any secret-like value is redacted in this report; only the *type* and *location* are disclosed.

---

## 1. Summary

| Information class | Disclosed via HTTP? | Severity / source |
|-------------------|---------------------|-------------------|
| Python stack traces | No (clean JSON in normal operation) | — |
| Filesystem paths | No | — |
| SQL queries / DDL | **Conditionally yes** | `"error": str(error)` on DB-failure paths |
| Database information | **Conditionally yes** | same `str(error)` paths |
| JWT secrets / signed token values | No (not echoed) | — |
| Environment variables / API keys | No | — |
| Internal Flask/SQLAlchemy config | No | — |
| Library versions | No | — |
| Debugging information (Werkzeug HTML) | No in tests | Only if `debug=True` reaches the network (development config) |

---

## 2. What Was Sent and What Came Back

### 2.1 Client/validation errors — clean (no disclosure)
Malformed/missing input across all endpoints returned well-formed `{"success":…,"message":…}` `400/401/404/405` bodies. Examples probed: missing password, missing login email, empty verification token, unknown path (`404`), wrong method (`405`), unauthenticated trip access (`401`). None leaked any internal detail.

### 2.2 JWT failure handlers — minor library-internal detail (finding E-1)
The JWT error loaders (`app.py:66-71`) return the raw exception as the `error` field:

```json
400 / 401 response "error" values observed:
- "Not enough segments"
- "Invalid header padding"
- "Invalid header string: 'utf-8' codec can't decode byte 0x81 in position 0: invalid start byte"
```

These reveal PyJWT internals (message text) but **not** the token value, secret, or any signed payload. Low severity. Forged/`alg:none` tokens are rejected with `401` and their value is never echoed.

### 2.3 Type-based `str(error)` 500s — internal code detail (finding E-2)
Sending strongly-typed values that pass `_parse_trip_payload` but crash downstream (confirmed earlier as A-12) yields `500` whose `"error"` is the internal exception message:

| Request | Status | Disclosed `error` string |
|---------|--------|--------------------------|
| `startDate = 20260901` (int) | 500 | `'int' object has no attribute 'split'` (cost_service.py:50) |
| `budget = ["moderate"]` (list) | 500 | `'list' object has no attribute 'lower'` |
| `budget = 123` (int) | 500 | `'int' object has no attribute 'lower'` |

These leak the internal code structure (attribute names, call sites) but **not** stack traces, paths, SQL, or secrets. Medium (info leak; also a crash/handling defect).

### 2.4 Database-failure `str(error)` — SQL & DB-information disclosure (finding E-3, the substantive one)
Every wrapped handler ends with `except Exception as error: return jsonify({..., "error": str(error)})`. If the database layer raises (connectivity loss, constraint/operational error), SQLAlchemy formats `OperationalError` to include the **SQL statement, table/column names, and bound parameters**. `str(error)` returns all of that to the client verbatim.

Demonstrated by simulating a statement-level DB failure on `POST /api/auth/login` (against the isolated test DB; no real DB touched, no destructive SQL):

```json
500 {"error": "… SELECT users.* FROM users WHERE users.email = ? …",
     "message": "Failed to login.", "success": false}
```

The same pattern exists on the following `str(error)` handlers (all wrapped in `except Exception`):
- `auth.py:208` (register), `:424` (login), `:489` (me GET), `:623` (me PATCH)
- `trips.py:216,236,284` (generate cost / itinerary / save), `:341` (list), `:388` (get one), `:452` (delete), `:482` (update cost), `:528` (update), `:581` (regenerate)
- `app.py:135` (health)

Severity: **Medium–High** — leaks SQL, schema, and bind parameters during any unhandled DB error. This is the concrete, reachable SQL/database-information disclosure route.

### 2.5 Unwrapped DB commit paths + development debugger (finding E-4)
`POST /api/auth/verify-email` (`auth.py:238`) and `POST /api/auth/resend-verification` (`auth.py:285`) wrap their `db.session.commit()` in **no** try/except. On a DB failure the exception propagates to Flask's default handler:
- With `debug=False` (production): Flask returns a generic `500` — **no disclosure**.
- With `debug=True` (development config, `app.py:157`) exposed on the network (`host="0.0.0.0"`): Flask renders the **interactive Werkzeug debugger**, which discloses the full **stack trace, source lines, and all local variables** — potentially including secrets held in scope. This is only an exposure if debug is left on outside localhost. Severity: High in that (non-production) configuration.

### 2.6 Startup log disclosure (not HTTP — noted for completeness)
`config/settings.py:22-27` prints `DB_USER`, `DB_HOST`, `DB_PORT`, `DB_NAME` to server **stdout at startup** (the DB password is **not** printed). This is a log-side artifact; it is not returned to HTTP clients. Real values were not read for this test (only dummy test env values were used).

---

## 3. Findings Table

| ID | Class | Source | Severity | Disclosed |
|----|-------|--------|----------|-----------|
| E-1 | JWT error loader echoes library exception text | `app.py:66-71` | Low | Internal PyJWT message strings; no secret/token |
| E-2 | `str(error)` with internal exception detail | cost service via `trips.py:216` (and update path) | Med | Attribute/code internals (A-12) |
| E-3 | `str(error)` on DB failure leaks SQL + bind params + schema | all wrapped handlers (see §2.4) | **Med–High** | SQL, schema, DB info |
| E-4 | Unwrapped commits + `debug=True` on `0.0.0.0` | `auth.py:238,285`; `app.py:154-157` | High (dev only) | Stack trace + locals via Werkzeug debugger |
| E-5 | Startup stdout prints DB identifiers | `settings.py:22-27` | Low (log-side) | DB user/host/port/name (no password) |

**Not found as disclosed via HTTP:** Python stack traces (normal op), filesystem paths, JWT secrets/values, environment variables, API keys, Flask/config internals, library versions, or debugger HTML — in properly initialized-DB, non-debug operation.

---

## 4. No Secrets in This Report (redaction note)
No real production secrets were read or exposed. The test environment uses only placeholder values which are redacted here. Per instructions: if any secret is ever returned by these endpoint paths (e.g., via the E-4 debugger locals or an E-3 DB error including credentials in a connection string), it would be of type DB-credential / API-key / JWT-secret and located in `backend/.env` via the relevant handler — but none were encountered during this test run and none are printed here.

---

## 5. Recommendation (not applied — no application code modified)
- **Stop echoing `str(error)`**: return a generic `{"message": "Internal server error."}` and log the real exception server-side (resolves E-1, E-2, E-3). This is the single highest-value fix and also closes A-8/A-12.
- **Wrap the unwrapped commits** (`verify-email`, `resend-verification`) in try/except with the same generic-error + server-log pattern (E-4).
- **Keep `debug=False` and bind `127.0.0.1`** outside local development (E-4 secondary).
- **Remove the startup `print()` of DB identifiers** or demote to `logger.debug` (E-5).
- **JWT loaders** (`app.py`): return only generic messages, drop the raw `error` field (E-1).

---

## 6. Regression Tests
`security/tests/test_error_handling.py` (19 tests) asserts:
- Clean `400/401/404/405` bodies never leak traces, SQL, paths, secrets, versions, or debugger HTML.
- Forged/malformed tokens are rejected without echoing the token.
- Type-based `500`s expose no stack/SQL/path/secret (E-2 bounded).
- A simulated DB failure on a wrapped handler returns `500` with `str(error)` (documents E-3 current behaviour; will surface once fixed).
- No Werkzeug debugger HTML is served.

Run: `pytest -q security/tests/test_error_handling.py`
