# Tripora Backend — Security Test Plan

**Scope:** Local Tripora backend (`http://127.0.0.1:5000`), Flask test-client / pytest style.
**Auth:** Tests run against a **separate test database with dummy credentials** — never against real data, and never reading `.env` values.
**Rule:** No destructive actions. Use only synthetically created test users/trips.

This plan maps each test to the attack surface identified in [`attack-surface.md`](attack-surface.md). Each test specifies the endpoint, method, preconditions, input, expected secure behavior, and the condition that would constitute a vulnerability.

> Test-client notes: use Flask's `app.test_client()` (or `pytest` fixtures) so no real network/DB side effects are needed. For rate-limit tests, either observe logical absence of throttling or, where a shared in-memory app is used, send N rapid requests and check that responses are not throttled.

---

## P1 — Authentication Bypass

### T-1.1 Unauthenticated access to protected endpoints
- **Endpoint:** all JWT-protected routes (`/api/auth/me`, `/api/trips`, `/api/trips/<id>`, `/api/trips/generate`, `/api/trips/<id>/regenerate`, and `DELETE/PATCH /api/trips/<id>`)
- **Method:** GET / POST / PATCH / DELETE
- **Preconditions:** Test app with DB initialized; no token supplied.
- **Input:** Requests with no `Authorization` header.
- **Expected secure behavior:** Each returns `401` with `{"success": false}` and no resource data.
- **Vulnerability if:** Any protected route returns `200`/`2xx` with data, or executes a mutation, without a valid token.

### T-1.2 Invalid / malformed token
- **Endpoint:** `/api/trips/generate` (representative)
- **Method:** POST
- **Preconditions:** No valid session.
- **Input:** `Authorization: Bearer garbage`, `Bearer <valid-MAC-but-wrong-signature>`, `Bearer not-a-jwt`, empty `Bearer `.
- **Expected secure behavior:** `401` with invalid-session message; no DB writes.
- **Vulnerability if:** Any malformed/forged token is accepted.

### T-1.3 Expired token rejected
- **Endpoint:** `/api/trips`
- **Method:** GET
- **Preconditions:** Create a token with `exp` in the past (JWT config `JWT_ACCESS_TOKEN_EXPIRES` default 15 min; inject an already-expired token via test config).
- **Input:** Authorization header with expired token.
- **Expected secure behavior:** `401` expired-session message.
- **Vulnerability if:** Expired token grants access.

### T-1.4 Token signature algorithm confusion
- **Endpoint:** `/api/trips`
- **Method:** GET
- **Preconditions:** Server uses HS256 (`JWT_ALGORITHM` unset).
- **Input:** A forged token signed with asymmetric algorithm choice (e.g., `alg: none`, or RS256 using the public key as HMAC secret) — the standard "algorithm confusion" checks.
- **Expected secure behavior:** Invalid-signature rejection (`401`).
- **Vulnerability if:** `alg:none` or algorithm-confusion tricks verify successfully.

### T-1.5 Verify-email before account exists / token oracle
- **Endpoint:** `/api/auth/verify-email`
- **Method:** POST
- **Preconditions:** Test DB; an unverified user exists; attacker does not know the token.
- **Input:** Random/absent `token` values.
- **Expected secure behavior:** `400`/`404` with generic invalid-token message; no status flipping.
- **Vulnerability if:** Any token guess can set `email_verified = True`, or the endpoint permits verifying an account whose verification token matches — indicating insufficient token entropy or exposure (see logging finding A-2).

---

## P2 — Broken Authorization / IDOR

### T-2.1 Cross-user trip access (GET)
- **Endpoint:** `GET /api/trips/<trip_id>`
- **Method:** GET
- **Preconditions:** Two test users A and B; user A owns trip X.
- **Input:** User B requests trip X's id.
- **Expected secure behavior:** `404` (trip is filtered by `user_id`).
- **Vulnerability if:** User B receives user A's trip data (`200`).

### T-2.2 Cross-user trip modification (PATCH)
- **Endpoint:** `PATCH /api/trips/<trip_id>`
- **Method:** PATCH
- **Preconditions:** Two test users; user A owns trip X.
- **Input:** User B issues a valid trip payload for trip X (changes destination).
- **Expected secure behavior:** `404`; user A's trip unchanged.
- **Vulnerability if:** `200` and user A's trip is modified.

### T-2.3 Cross-user trip deletion (DELETE)
- **Endpoint:** `DELETE /api/trips/<trip_id>`
- **Method:** DELETE
- **Preconditions:** Two test users; user A owns trip X.
- **Input:** User B deletes trip X.
- **Expected secure behavior:** `404`; trip X still present for user A.
- **Vulnerability if:** `200` and trip X is deleted (verify via user A GET).

### T-2.4 Cross-user trip regeneration
- **Endpoint:** `POST /api/trips/<trip_id>/regenerate`
- **Method:** POST
- **Preconditions:** Two test users; user A owns trip X.
- **Input:** User B regenerates trip X.
- **Expected secure behavior:** `404`; no change to X.
- **Vulnerability if:** `200` and trip X's itinerary is regenerated for user B.

### T-2.5 IDOR via numeric ID sweeps / invalid ids
- **Endpoint:** `GET /api/trips/<trip_id>`, `DELETE ...`
- **Method:** GET / DELETE
- **Preconditions:** Test DB with several trips across users.
- **Input:** Enumerate trip ids `0`, `1`, `999999`, negative `-1`; ensure each returns `404` for non-owned resources, regardless of id validity.
- **Expected secure behavior:** `404` for anything not owned by the authenticated user (even valid-format ids).
- **Vulnerability if:** Any non-owned id yields data or mutation.

### T-2.6 Account update stays scoped to self
- **Endpoint:** `PATCH /api/auth/me`
- **Method:** PATCH
- **Preconditions:** Two test users.
- **Input:** Nothing permits choosing a target user id (identity comes only from JWT). Send PATCH with no `id` field.
- **Expected secure behavior:** Update applies to the token's own user only.
- **Vulnerability if:** A user can modify another user's account (e.g., via injected `id`/`user_id` fields).

---

## P3 — JWT Security

### T-3.1 Default expiry honored
- **Endpoint:** `/api/trips`
- **Method:** GET
- **Preconditions:** App default config (15-min access token).
- **Input:** Token valid at issuance; advance simulated time beyond `exp`.
- **Expected secure behavior:** Expired token → `401`.
- **Vulnerability if:** Token remains accepted after expiry.

### T-3.2 No refresh-token / session-revocation bypass
- **Endpoint:** (conceptual, all protected routes)
- **Method:** GET
- **Preconditions:** A valid token was issued and then "logged out" (no logout endpoint exists).
- **Input:** Reuse the pre-logout token.
- **Expected secure behavior:** Since no logout/revocation is implemented, note this as a documented gap, not a pass/fail test. Attempt to confirm there is **no refresh endpoint** that extends a compromised session beyond the 15-min window.
- **Vulnerability if:** A `refresh` capability exists unguarded that grants long-lived access, or a revoked token never expires.

### T-3.3 Weak-secret acceptance check (non-destructive)
- **Endpoint:** `/api/trips`
- **Method:** GET
- **Preconditions:** In an **isolated test app** with a deliberately weak `JWT_SECRET_KEY` (dummy only; do NOT modify production config).
- **Input:** Forge a token signed with a short/guessable key.
- **Expected secure behavior:** (Not a runtime test — analysis) Flag if the deployment uses a weak/default secret.
- **Vulnerability if:** The real secret is weak or hard-coded. (Static check only; do not attempt to brute-force a live secret.)

### T-3.4 Token identity type integrity
- **Endpoint:** `/api/auth/me`
- **Method:** GET
- **Preconditions:** Valid token whose `sub`/identity is non-numeric or malformed.
- **Input:** Token with `sub` not castable to int (e.g., `"abc"`) — simulate by signing a crafted payload in test app.
- **Expected secure behavior:** Route handles gracefully (`401`/`404`), no crash leaking stack.
- **Vulnerability if:** Non-numeric identity causes unhandled `ValueError` → `500` with `str(error)` disclosure (`auth.py:449`).

---

## P4 — SQL Injection Resistance

### T-4.1 Injection in string fields (register)
- **Endpoint:** `POST /api/auth/register`
- **Method:** POST
- **Preconditions:** Test DB.
- **Input:** `name`/`email` fields containing classic payloads: `' OR '1'='1`, `'; DROP TABLE users; --`, `" OR ""="`, `1 UNION SELECT ...`. Use fully self-contained payloads that would break query structure if interpolation occurred.
- **Expected secure behavior:** Treated as literal data (ORM parameterized); no error, user/stored data remains intact; `'` characters stored literally or rejected by validation.
- **Vulnerability if:** Any payload changes query semantics, returns extra rows, alters response status/content, or causes a SQL error in the response.

### T-4.2 Injection via login email
- **Endpoint:** `POST /api/auth/login`
- **Method:** POST
- **Preconditions:** Test DB.
- **Input:** `email` with injection payloads; observe behavior and response timing/content.
- **Expected secure behavior:** No change in query behavior; `401` generic "Invalid email or password".
- **Vulnerability if:** Injection alters the user lookup, or error text exposes raw SQL.

### T-4.3 Injection via trip destination / interests (generate)
- **Endpoint:** `POST /api/trips/generate`
- **Method:** POST
- **Preconditions:** Test user with valid JWT.
- **Input:** `destination` and `interests[]` with SQL injection payloads.
- **Expected secure behavior:** Stored literally; cost computation treats them as strings; no DB error.
- **Vulnerability if:** Query errors surface or injection payloads executed.

---

## P5 — Input Validation

### T-5.1 Invalid language / currency rejected
- **Endpoint:** `POST /api/auth/register`, `PATCH /api/auth/me`
- **Method:** POST / PATCH
- **Preconditions:** Valid signed-in status for PATCH.
- **Input:** `preferredLanguage: "zz"`, `preferredCurrency: "XYZ"` (outside whitelists).
- **Expected secure behavior:** `400` invalid-language / invalid-currency.
- **Vulnerability if:** Non-whitelisted values are accepted and stored.

### T-5.2 Invalid email format accepted (documented gap)
- **Endpoint:** `POST /api/auth/register`, `PATCH /api/auth/me`
- **Method:** POST / PATCH
- **Preconditions:** Test DB.
- **Input:** `email: "not-an-email"`, `email: "a@b"`, `email: "user@example"`, leading/trailing spaces.
- **Expected secure behavior:** Ideally `400` for a malformed email. (Note: current code has **no email-format validation** — treat this as a confirmed gap, document, do not treat as a pass.)
- **Vulnerability if:** Malformed emails are stored and create phishing/harvesting concern; enumeration via `409`/`404` differences.

### T-5.3 Email normalization / case-insensitive uniqueness
- **Endpoint:** `POST /api/auth/register`
- **Method:** POST
- **Preconditions:** Existing user `Test@Example.com`.
- **Input:** Register same address lowercase `test@example.com`.
- **Expected secure behavior:** `409` duplicate (email is lowercased before lookup).
- **Vulnerability if:** Duplicate accounts are created with case-differing or whitespace-differing emails.

### T-5.4 Interests type enforcement (generate)
- **Endpoint:** `POST /api/trips/generate`
- **Method:** POST
- **Preconditions:** Valid JWT.
- **Input:** `interests: "food"` (string not list) and `interests: [123, null, {"x":1}]` (non-string elements).
- **Expected secure behavior:** Rejects `interests` not being a list (`400`); non-string elements either rejected or safely coerced without breaking the AI/cost path.
- **Vulnerability if:** Non-list passes validation, or malformed interests cause `500`/crash or unsafe prompt content.

### T-5.5 Destination / dates basic validation
- **Endpoint:** `POST /api/trips/generate`
- **Method:** POST
- **Preconditions:** Valid JWT.
- **Input:** Missing `destination`; `startDate: "not-a-date"`; `endDate` before `startDate`.
- **Expected secure behavior:** `400` with corresponding message; no DB write.
- **Vulnerability if:** Invalid dates/destination are accepted and saved.

---

## P6 — Missing Required Fields

### T-6.1 Register missing fields
- **Endpoint:** `POST /api/auth/register`
- **Method:** POST
- **Preconditions:** Test DB.
- **Input:** Omit each of `name`, `email`, `password` (one at a time); also send empty JSON `{}` and empty/whitespace `name`.
- **Expected secure behavior:** `400` with a specific required-field message for each case.
- **Vulnerability if:** Missing fields are accepted (creates partial user) or return `500`.

### T-6.2 Login missing fields
- **Endpoint:** `POST /api/auth/login`
- **Method:** POST
- **Preconditions:** Test DB.
- **Input:** Omit `email`, omit `password`, empty `{}`.
- **Expected secure behavior:** `400`.
- **Vulnerability if:** Accepted without creds.

### T-6.3 Trip generate missing fields
- **Endpoint:** `POST /api/trips/generate`
- **Method:** POST
- **Preconditions:** Valid JWT.
- **Input:** Omit `destination` / `startDate` / `endDate` / `travelers`; empty `{}`; `travelers` missing or zero.
- **Expected secure behavior:** `400` with message; no AI call / DB write.
- **Vulnerability if:** Missing/invalid fields trigger external Gemini calls or partial trip rows.

### T-6.4 PATCH /me missing update + required current password
- **Endpoint:** `PATCH /api/auth/me`
- **Method:** PATCH
- **Preconditions:** Valid JWT; existing user with password.
- **Input:** (a) empty `{}` → expect `400`; (b) `{"password": "newpass"}` without `currentPassword` → expect `400`; (c) `{"password": "newpass", "currentPassword": "wrong"}` → expect `401`.
- **Expected secure behavior:** `400`/`401` respectively; password unchanged.
- **Vulnerability if:** Password can be changed without verifying the current password.

---

## P7 — Invalid Data Types

### T-7.1 travelers as wrong types
- **Endpoint:** `POST /api/trips/generate`
- **Method:** POST
- **Preconditions:** Valid JWT.
- **Input:** `travelers: "2"` (string), `travelers: 2.5` (float), `travelers: [2]`, `travelers: null`, `travelers: 0`, `travelers: -1`, `travelers: true`.
- **Expected secure behavior:** `400` "Travelers must be a positive number" (only proper positive `int` accepted).
- **Vulnerability if:** Non-int accepted and stored, or integer/boolean coercion bypasses the check (e.g., `true` → 1) leading to unexpected cost math.

### T-7.2 dates as wrong types
- **Endpoint:** `POST /api/trips/generate`
- **Method:** POST
- **Preconditions:** Valid JWT.
- **Input:** `startDate: 12345`, `startDate: {"x":1}`, `startDate: null`, `startDate: "2026-1-1"`.
- **Expected secure behavior:** `400` "Invalid date format"; no crash.
- **Vulnerability if:** ValueError escapes to a `500` with `str(error)` disclosure.

### T-7.3 JSON body vs non-JSON
- **Endpoint:** `POST /api/auth/login`, `/api/trips/generate`
- **Method:** POST
- **Preconditions:** — 
- **Input:** `Content-Type: text/plain` body, or malformed JSON.
- **Expected secure behavior:** `get_json(silent=True)` returns `None`/`{}` → handled as missing-data `400`.
- **Vulnerability if:** Malformed body causes unhandled exception or crash.

---

## P8 — Excessively Large Inputs

### T-8.1 Oversized strings
- **Endpoint:** `POST /api/auth/register`, `PATCH /api/auth/me`
- **Method:** POST / PATCH
- **Preconditions:** Test DB.
- **Input:** `name`/`email` of 10k–100k+ characters; `name: "A" * 100000`.
- **Expected secure behavior:** Rejected (`400`/`413`) or safely stored up to model limits (`String(100)`, `String(255)`); no memory/DB exhaustion, no `500` stack leak.
- **Vulnerability if:** Oversized inputs bloat DB (no length cap in route), cause errors, or bypass DB column limits with silent truncation.

### T-8.2 Very large interests list / long itinerary span
- **Endpoint:** `POST /api/trips/generate`
- **Method:** POST
- **Preconditions:** Valid JWT.
- **Input:** `interests: [<thousands of elements>]`; trip spanning months/years (`startDate` to `endDate` far apart — e.g., 2 years).
- **Expected secure behavior:** Inputs bounded/validated; the AI call and storage scale responsibly or are rejected.
- **Vulnerability if:** Unbounded trip length → huge Gemini payloads / many retries (cost/latency DoS per A-11) or large stored JSON.

### T-8.3 Large request body (default limits)
- **Endpoint:** `POST /api/anything` (representative: `/api/trips/generate`)
- **Method:** POST
- **Preconditions:** —
- **Input:** Multi-MB request body.
- **Expected secure behavior:** Flask/Werkzeug default body-size handling; no uncontrolled memory usage (note: no `MAX_CONTENT_LENGTH` is set in config — documented gap).
- **Vulnerability if:** Unbounded body causes DoS.

---

## P9 — Error Information Disclosure

### T-9.1 Error message leaks internals on 5xx
- **Endpoint:** `/api/trips/generate`, `/api/auth/me`, `/api/health`, `/api/trips`
- **Method:** POST / GET
- **Preconditions:** Ability to trigger a server error (e.g., provide a data shape that throws) in a test app.
- **Input:** Crafted inputs that raise exceptions in each handled block.
- **Expected secure behavior:** Response body contains **no** exception text, SQL, file paths, or host details — only a generic message and `success:false`.
- **Vulnerability if:** `"error": str(error)` contains internal details (confirmed leak pattern in many handlers — see A-8).

### T-9.2 Debug stack traces disabled
- **Endpoint:** any request when the app errors
- **Method:** —
- **Preconditions:** Dev server.
- **Input:** A request that raises an unhandled exception.
- **Expected secure behavior:** Generic `500`, no debugger/Werkzeug interactive traceback. Note: `app.py:154-157` runs `debug=True` on `0.0.0.0` — this enables interactive debugger RCE if reachable.
- **Vulnerability if:** Werkzeug debugger / stack trace is exposed to clients during a test.

---

## P10 — Rate Limiting

### T-10.1 Login brute-force not throttled
- **Endpoint:** `POST /api/auth/login`
- **Method:** POST
- **Preconditions:** Test user with known bad password.
- **Input:** Send N rapid attempts (e.g., 50–100) with wrong password.
- **Expected secure behavior:** Ideally throttled/locked after a threshold.
- **Vulnerability if:** Every attempt is processed and returns `401` with no throttling — brute-force is feasible. (Current code has **no rate limiting** — confirmed gap, A-5. Do not exceed a reasonable local volume; testing is read-only enumeration, not credential-stuffing against real users.)

### T-10.2 Register spam not throttled
- **Endpoint:** `POST /api/auth/register`
- **Method:** POST
- **Preconditions:** Test DB.
- **Input:** Many rapid unique registrations.
- **Expected secure behavior:** Account-creation spam limited.
- **Vulnerability if:** Unlimited signups (resource + enumeration DoS).

### T-10.3 Gemini endpoint abuse (cost DoS)
- **Endpoint:** `POST /api/trips/generate`, `POST /api/trips/<id>/regenerate`
- **Method:** POST
- **Preconditions:** Valid test user; Gemini configured with a dummy key in test env (or stubbed).
- **Input:** Repeated generate/regenerate calls.
- **Expected secure behavior:** Some per-user throttling / API-quota guard.
- **Vulnerability if:** No throttling — each call triggers 1–3 Gemini requests (cost/latency amplification, A-11). **Use a stub/mock for the Gemini client in tests** to avoid real external cost.

---

## P11 — File Upload Security

### T-11.1 Confirm no upload surface
- **Endpoint:** all routes
- **Method:** GET / POST / PATCH
- **Preconditions:** —
- **Input:** Attempt multipart `enctype` uploads (`request.files`) with files (e.g., `POST /api/trips/generate` with a `.php`/`.py` attachment).
- **Expected secure behavior:** No file handling exists → `400`/ignored; no file written to disk anywhere.
- **Vulnerability if:** Any endpoint accepts/stores an uploaded file, writes to a web-accessible path, or processes content. (Static review found **no file-upload surface** — low priority.)

---

## P12 — Sensitive Information Exposure

### T-12.1 No secrets in responses
- **Endpoint:** `/api/auth/login`, `/api/auth/me`, `/api/trips/*`
- **Method:** GET / POST
- **Preconditions:** Test user.
- **Input:** Legitimate authenticated requests that return user/trip objects.
- **Expected secure behavior:** `password_hash`, `verification_token`, and any internal fields are **absent** from all JSON responses.
- **Vulnerability if:** `password_hash`, `verification_token`, or DB connection details appear in any response.

### T-12.2 User enumeration via distinct responses
- **Endpoint:** `POST /api/auth/resend-verification` (primary), `POST /api/auth/register`, `PATCH /api/auth/me`
- **Method:** POST / PATCH
- **Preconditions:** One known existing email, one non-existent email.
- **Input:** Submit both to each endpoint.
- **Expected secure behavior:** Responses should be indistinguishable for existing vs non-existing (same status + generic message).
- **Vulnerability if:** `resend-verification` returns `404` "No account was found" vs `200` (confirmed oracle, A-3), or `register` returns `409` vs `201`, or `me` PATCH returns `409` on taken email — enabling account enumeration.

### T-12.3 Passwords / tokens not logged in plaintext
- **Endpoint:** `POST /api/auth/register`, `POST /api/auth/login`
- **Method:** POST
- **Preconditions:** Test app with DEBUG logging enabled.
- **Input:** Register + login with a test password; capture log output.
- **Expected secure behavior:** No password (or verification token) appears in logs.
- **Vulnerability if:** `logger.debug("REGISTER REQUEST: %s", data)` / `logger.debug("LOGIN REQUEST: %s", data)` writes plaintext passwords, or email verification token is logged by the placeholder service (confirmed — A-1, A-2).

### T-12.4 Config print not exposing secrets
- **Endpoint:** startup only
- **Method:** —
- **Preconditions:** Instantiate the test app.
- **Input:** Observe process stdout at import.
- **Expected secure behavior:** DB password never printed.
- **Vulnerability if:** `config/settings.py:22-27` prints `DB_PASSWORD` or other secrets. (It prints user/host/port/name only — password not printed, but host/user info is exposed; document as low.)

### T-12.5 `.env` / secrets not served
- **Endpoint:** `/` , `/api/health`, and any static path
- **Method:** GET
- **Preconditions:** —
- **Input:** Request `/`, `.env`, `/../.env`, `/app.py`, `/config/settings.py`.
- **Expected secure behavior:** No source or config files are served; static file serving not enabled.
- **Vulnerability if:** The app serves `.env`, source, or config (paths/passwords exposed).

---

## Execution & Reporting Notes

- **Order:** Run P1–P4 (auth/authorization/JWT/SQLi — highest impact) first, then P5–P9, then P10–P12.
- **Isolation:** Prefer Flask test-client with an **in-memory or throwaway MySQL test database** and **dummy** DB/JWT/Gemini credentials. Never run against production data or the real `.env`.
- **Non-destructive:** Every test creates only discardable test rows; DELETE tests only delete test-owned trips. Always clean up test users/trips after a run.
- **Gemini:** Stub/mock `itinerary_service` in rate/input tests to avoid external calls and cost.
- **Result capture:** For each test record: PASS / FAIL / CONFIRMED-GAP / N/A, evidence, and mapping back to `attack-surface.md` finding IDs (A-1 … A-11). Log results in `security/reports/test-results.md` when executed.
