# Tripora Backend — Security Attack-Surface Report

**Scope:** Local Tripora application (authorized for testing).
**Target:** Python Flask backend, development server `http://127.0.0.1:5000`, MySQL database, JWT authentication.
**Method:** Static source review of the backend (`backend/`).
**Status:** Analysis only — no application code was modified and no live requests were made.

> Note: Values referenced as `os.getenv(...)` (DB credentials, `JWT_SECRET_KEY`, `GEMINI_API_KEY`) come from `backend/.env`. The contents of `.env` were **not** read and are out of scope; only the expected variable names are documented.

---

## 1. Endpoint Inventory

All routes are registered in `backend/app.py:90-91`. Blueprints:
- `auth_bp` — `backend/routes/auth.py` (prefix `/api/auth`)
- `trips_bp` — `backend/routes/trips.py` (prefix `/api/trips`)
- Plus two inline routes in `app.py`.

| Method | Path | Handler | Auth | File:Line |
|--------|------|---------|------|-----------|
| GET | `/` | `home` | none | app.py:98 |
| GET | `/api/health` | `health` | none | app.py:112 |
| POST | `/api/auth/register` | `register` | none | routes/auth.py:39 |
| POST | `/api/auth/verify-email` | `verify_email` | none | routes/auth.py:217 |
| POST | `/api/auth/resend-verification` | `resend_verification` | none | routes/auth.py:254 |
| POST | `/api/auth/login` | `login` | none | routes/auth.py:304 |
| GET | `/api/auth/me` | `get_current_user` | JWT | routes/auth.py:433 |
| PATCH | `/api/auth/me` | `update_current_user` | JWT | routes/auth.py:498 |
| POST | `/api/trips/generate` | `generate_trip` | JWT | routes/trips.py:159 |
| GET | `/api/trips` | `get_trips` | JWT | routes/trips.py:303 |
| GET | `/api/trips/<int:trip_id>` | `get_trip` | JWT | routes/trips.py:350 |
| DELETE | `/api/trips/<int:trip_id>` | `delete_trip` | JWT | routes/trips.py:397 |
| PATCH | `/api/trips/<int:trip_id>` | `update_trip` | JWT | routes/trips.py:456 |
| POST | `/api/trips/<int:trip_id>/regenerate` | `regenerate_trip_itinerary` | JWT | routes/trips.py:532 |

**Count:** 15 endpoints; 5 unauthenticated, 10 require a JWT.

---

## 2. Authentication Mechanisms

- **Password hashing:** `werkzeug.security.generate_password_hash` / `check_password_hash` (`routes/auth.py:149`, `:364`, `:589`, `:595`). Defaults to scrypt-based hashing via Werkzeug. Good — no plaintext storage.
- **Email verification gating:** login is blocked (`403`) until `user.email_verified` is true (`routes/auth.py:374-378`).
- **No session cookies; bearer tokens only.** `JWT_TOKEN_LOCATION` is unset → defaults to JSON body / header on Flask-JWT-Extended. The app only ever sends the token in the Authorization header from the client.
- **No password reset** endpoint exists.
- **No account lockout / throttling on login** (see Rate Limiting).
- **Placeholder email service:** `services/email_service.py` only logs the verification token to application logs (`[EMAIL-PLACEHOLDER] ... : <token>`). No real email is sent yet.

---

## 3. JWT Implementation

Configured in `backend/config/settings.py` and initialized in `backend/app.py`.
- `JWT_SECRET_KEY` read from env (`settings.py:82`), required at startup. If weak, tokens are forgeable.
- **No `JWT_ALGORITHM` override** → defaults to `HS256` (symmetric, secret-based). Acceptable, but depends on secret strength.
- **No `JWT_ACCESS_TOKEN_EXPIRES` override** → default **15 minutes** access-token lifetime.
- **No refresh tokens** used (`create_access_token` only, `auth.py:384`; no `refresh=True` routes).
- Custom error loaders: `unauthorized`, `invalid`, and `expired` handlers (`app.py:57-78`) return clean JSON rather than stack traces.
- **No token revocation / logout / blacklist.** A stolen token is valid until it naturally expires (15 min).
- **Identity:** `get_jwt_identity()` returns the user id as a string; routes cast with `int(...)` in `_get_authenticated_user_id` (`trips.py:25-31`) and inline in `auth.py:449, 504`.

---

## 4. Authorization / Ownership Checks

- **Trips:** every trip query filters by both `id` **and** `user_id` of the authenticated user:
  - `GET /api/trips` → `filter_by(user_id=...)` (`trips.py:317`)
  - `GET /api/trips/<id>` → `filter_by(id=..., user_id=...)` (`trips.py:364`)
  - `DELETE /api/trips/<id>` → `filter_by(id=..., user_id=...)` (`trips.py:411`)
  - `PATCH /api/trips/<id>` → `filter_by(id=..., user_id=...)` (`trips.py:486`)
  - `POST /api/trips/<id>/regenerate` → `filter_by(id=..., user_id=...)` (`trips.py:544`)
  
  **Verdict:** Ownership is correctly enforced on trip resources. No IDOR found on trip endpoints.

- **User account:** `GET/PATCH /api/auth/me` operate only on the identity from the JWT — no client-supplied user id is accepted. Ownership is implicit via the token.

- **Notable issue:** `trips.user_id` is `nullable=True` (`models/trip.py:22-26`) and the DB FK is nullable. If any code path could create a trip without `user_id`, it would become orphaned/unowned. Currently `generate_trip` always sets `user_id` (`trips.py:248`), so no live bug, but the nullable column is a risk surface worth noting.

---

## 5. Database Queries

- **ORM via SQLAlchemy** throughout (`User.query`, `Trip.query`, `db.session.get`, `db.session.execute(text("SELECT 1"))`).
- **No raw SQL with user input** except `health` (`app.py:117`) which uses a constant `SELECT 1` — safe.
- **SQL injection risk:** LOW. All user inputs flow through the ORM query-builder / parameterized methods. `_parse_trip_payload` validates types.
- **Schema SQLAlchemy layer:** `backend/models/user.py`, `backend/models/trip.py`; migrations in `backend/migrations/`.

---

## 6. User-Controlled Inputs

| Endpoint | Input | Validation | Notes |
|----------|-------|------------|-------|
| `register` | `name`, `email`, `password`, `preferredLanguage`, `preferredCurrency` | name/email/password presence + min len; language/currency whitelisted (`auth.py:113-126`) | No email format check (regex); no strong password policy (min 6 chars only) |
| `login` | `email`, `password` | presence only | no rate limiting |
| `verify-email` | `token` | presence only; looked up directly | `User.query.filter_by(verification_token=token)` — constant-time not required but token is 32-byte urlsafe |
| `resend-verification` | `email` | presence, lowered | user enumeration via distinct response messages (see §11) |
| `me` PATCH | `name`, `email`, `password`, `currentPassword`, `preferredLanguage`, `preferredCurrency` | present + len checks; lang/currency whitelists; current password required to change password (`auth.py:575-595`) | no email-format validation |
| `trips/generate` | `destination`, `startDate`, `endDate`, `travelers`, `budget`, `travelStyle`, `interests` | `_parse_trip_payload` (`trips.py:34-77`): destination present; dates ISO-parsed; travelers positive int; interests must be list | `budget`/`travelStyle` freely passed to AI and cost service |
| `trips/<id>` PATCH | same as generate | same via `_parse_trip_payload` | full replace semantics |
| `trips/<id>/regenerate` | — (uses stored trip) | — | no new user input |

**Notes / gaps:**
- **No email format validation** (e.g., no `email` regex) anywhere — registering with malformed or attacker-controlled addresses is possible.
- **`interests` list elements are not type-checked** beyond being a list; contents flow into AI prompt and stored JSON.
- **Dates** — `date.fromisoformat(str(start_date)[:10])` truncates to 10 chars; validates parseability but no upper bound on trip length (a multi-year trip creates a huge AI/DB workload — see DoS notes).
- `travel_style`/`budget` are unvalidated strings passed directly into the AI prompt.

---

## 7. File Uploads

- **None found.** No `request.files`, no `UPLOAD_FOLDER`, no `MAX_CONTENT_LENGTH`-related file handling. Not an attack surface in the backend.

---

## 8. External API Calls

- **Google Gemini** (`services/itinerary_service.py`):
  - `GEMINI_API_KEY` loaded from env at import time (`itinerary_service.py:12`); module raises `ValueError` if absent.
  - `client.models.generate_content(...)` for itinerary generation (model `gemini-3.6-flash`), with JSON schema enforcement and response validation `_validate_itinerary`.
  - **LLM prompt injection risk:** user-controlled fields (`destination`, `travel_style`, `interests`, budget) are interpolated directly into the prompt (`itinerary_service.py:303-394`). A crafted `interests`/`destination` value could attempt prompt injection. Output is schema-validated and not executed as code, so impact is limited, but content may be manipulated.
  - **Resource-exhaustion:** each generate attempts up to 3 Gemini calls (`max_attempts = 3`); combined with unbounded trip length this multiplies cost/latency per request.
- **Email service** — no real external call currently (see §2).
- **No other external HTTP calls** (no SMTP, no payment, no currency APIs).

---

## 9. Error Handling

- **Structured `jsonify` responses** with `success` flag consistently.
- **`except Exception as error` → `"error": str(error)`** in many handlers leaks internal exception text to clients:
  - `app.py:135` (health, DB error)
  - `auth.py:208`, `:424`, `:489`, `:623`
  - `trips.py:216`, `:236`, `:284`, `:341`, `:388`, `:452`, `:482`, `:528`, `:581`
  
  This can expose DB names, SQLAlchemy internals, host info, or file paths. **Information leakage risk** — recommended to log server-side and return generic messages.
- **Verbose debug logging of request bodies:** `logger.debug("REGISTER REQUEST: %s", data)` (`auth.py:44`) and `logger.debug("LOGIN REQUEST: %s", data)` (`auth.py:309`) — **passwords are logged in plaintext** at DEBUG level. Significant sensitive-information exposure risk.
- **Unhandled exceptions:** `_build_itinerary` Gemini failures surface via `print(...)` in `itinerary_service.py` and are caught at the route level; generic 500 returned with `str(error)`.

---

## 10. Rate Limiting

- **None implemented.** No Flask-Limiter, no throttling middleware, no per-user/IP guards on any endpoint.
- High-risk unthrottled endpoints:
  - `/api/auth/login` — **brute-force** of passwords (no lockout).
  - `/api/auth/register` / `resend-verification` — **account/email enumeration** and signup spam.
  - `/api/auth/verify-email` — token guessing surface (though token is 32-byte urlsafe → infeasible).
  - `/api/trips/generate`, `/api/trips/<id>/regenerate` — **cost/latency DoS** via repeated Gemini calls (each triggers 1–3 LLM requests).
  - `/api/trips` — bulk enumeration.

---

## 11. Sensitive Information Exposure

- **Credentials / config in `.env`** referenced by var name only (not read here): `DB_USER`, `DB_PASSWORD`, `DB_HOST`, `DB_PORT`, `DB_NAME`, `JWT_SECRET_KEY`, `GEMINI_API_KEY`.
- **`config/settings.py:22-27`** `print()`s DB user/host/port/name to stdout at import time (password is not printed, but host/user/db-name are). Minor info disclosure in logs.
- **`app.py:154-157`** runs with `debug=True` on `0.0.0.0:5000` — enables the Flask debugger (remote code execution if exposed) and exposes the app to all interfaces, not just localhost. Recommended to keep bound to `127.0.0.1` and `debug=False` outside local dev.
- **Passwords logged at DEBUG** (`auth.py:44`, `:309`) — plaintext password in logs.
- **Verification token logged** by the placeholder email service (`email_service.py:35-39`) — the email-verification token is written to application logs. Anyone with log access can verify arbitrary accounts.
- **Error strings leaked** in `"error": str(error)` responses (see §9).
- **User enumeration via status/message differences:**
  - `register` → `409` "already exists" vs `201` (email existence oracle).
  - `login` → generic "Invalid email or password" for both cases (good), but missing/blank-field 400s differ.
  - `resend-verification` → `404` "No account was found for that email" vs `200` (clearly distinguishes existing emails) — **direct user enumeration oracle** (`auth.py:267-271`).
  - `update_current_user` email conflict → `409`, exposes which emails are taken.
- **No CSRF concern** for bearer-token API (not cookie-based); but the placeholder email flow that relies on the token being secret is weakened by logging.

---

## Summary of Notable Findings (for later testing)

| ID | Category | Finding | Severity |
|----|----------|---------|----------|
| A-1 | Info exposure | Passwords logged in plaintext (DEBUG) — `auth.py:44,309` | High |
| A-2 | Info exposure | Email verification token written to logs — `email_service.py:35` | High |
| A-3 | Enumeration | `resend-verification` distinguishes existing emails (404 vs 200) | Medium |
| A-4 | Enumeration | `register` returns 409 on existing email (signup oracle) | Low/Med |
| A-5 | Rate limiting | No rate limiting anywhere; login brute-force possible | High |
| A-6 | JWT | No logout/revocation; 15-min tokens; HS256 with env secret | Med |
| A-7 | Config | `debug=True` + bind `0.0.0.0` in dev (`app.py:154-157`) | Med (dev) |
| A-8 | Info exposure | `str(error)` leaked in many error responses | Med |
| A-9 | Input validation | No email format validation; weak password policy | Low/Med |
| A-10 | LLM | Prompt injection surface via user-content into Gemini prompt | Low |
| A-11 | DoS | Unbounded trip length × 3 Gemini retries per request | Med |
| A-12 | Input validation / info exposure | Typed `startDate`/`budget` (int/list) bypass validation → 500 with `str(error)` disclosed — confirmed in `generate-trip-security.md` | Low/Med |

**Attack surface is otherwise well-controlled:** ORM-based queries (no SQLi), ownership checks on all trip resources (no IDOR), password hashing, structured error envelope.

---

## Files Reviewed

- `backend/app.py`
- `backend/config/settings.py`
- `backend/config/database.py`
- `backend/routes/auth.py`
- `backend/routes/trips.py`
- `backend/services/cost_service.py`
- `backend/services/email_service.py`
- `backend/services/itinerary_service.py`
- `backend/models/user.py`
- `backend/models/trip.py`
- `backend/models/__init__.py`
- `backend/requirements.txt`
- `backend/migrations/versions/*`

## Files NOT accessed

- `backend/.env` (credentials — intentionally out of scope per instructions)
