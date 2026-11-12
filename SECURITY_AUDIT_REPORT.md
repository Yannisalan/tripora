# Tripora — Security Audit Report

- **Date:** 2026-11-09
- **Scope:** `backend/` (Flask API), `frontend/` (Flutter: Android, iOS, web), deployment config (`backend/Procfile`, `frontend/vercel.json`), CI (`.github/workflows/security.yml`), migrations.
- **Method:** Manual review of every route, model, service, config and migration; targeted reading of the Flutter auth, network, admin and analytics code; Bandit; pip-audit; reproduction tests run against the local in-memory test app (`security/tests/test_audit_remediation.py`). No production system was contacted.
- **Baseline:** the working tree already held uncommitted hardening from an earlier pass (token versioning, refresh-token rotation, secure token storage, input caps). This audit covers the code **as it stands on disk**, including those uncommitted changes. Baseline suite: **348 passed**.

> This report states what was found and how it was confirmed. It does not claim the application is free of vulnerabilities.

## 0. Architecture as verified (differs from the brief)

| Brief said | Code actually shows | Evidence |
|---|---|---|
| MySQL | **PostgreSQL** (psycopg 3; Neon owner role; Row-Level Security on `trips`) | `backend/config/settings.py:58-64`, `migrations/versions/f0e9d8c7b6a5_enable_row_level_security.py` |
| JWT auth | Flask-JWT-Extended HS256 access tokens (15 min) + **opaque, DB-stored, rotating refresh tokens** (30 days, SHA-256 hashed, reuse detection) | `routes/auth.py:159-332`, `models/user_refresh_token.py` |
| — | Google / Apple sign-in endpoints are **live on the API**, although the buttons are hidden in the app (`AppConfig.showThirdPartyAuth = false`) | `routes/auth.py:865-925`, `frontend/lib/core/config/app_config.dart:24` |
| — | Separate **admin API** gated by one shared static bearer token (`ADMIN_API_TOKEN`) | `routes/admin.py` |
| — | Third-party APIs: Gemini, Travelpayouts, Duffel, Open-Meteo, Frankfurter | `services/*`, `routes/weather.py`, `routes/rates.py` |
| — | No file upload feature (the document vault was removed by migration `a7b8c9d0e1f2`) | — |
| — | Backend runs under Gunicorn, 2 workers, **in-process** rate limiter | `backend/Procfile`, `services/rate_limiter.py` |

## 1. Findings

Status key: **Verified** = reproduced by an automated test against the local app. **Code-verified** = confirmed by reading the code; no runtime reproduction possible locally. **Potential** = depends on deployment facts the repository does not contain.

### TRP-01 — AI activity-swap endpoint has no rate limit — **HIGH** — Verified
- **Location:** `backend/config/settings.py:309-344` (bucket table has no `trips.swap_activity`); `services/rate_limiter.py:154-162` (unknown endpoints are **not** limited).
- **Exploit:** any logged-in user loops `POST /api/trips/<id>/swap-activity`. Each call runs up to 3 Gemini attempts. Registration is open and unverified (TRP-15), so accounts are free.
- **Impact:** unbounded Gemini spend and quota exhaustion. Once quota runs out, trip generation fails for every user.
- **Fix:** add a dedicated AI bucket for swap. Make the limiter fail closed for state-changing endpoints that have no bucket.

### TRP-02 — Reset-code verification is unthrottled (bucket name mismatch) — **MEDIUM** — Verified
- **Location:** `settings.py:326` configures `auth.forgot_password_verify`. The real endpoint is `auth.verify_reset_code` (`routes/auth.py:1200-1201`), so it gets no limit.
- **Exploit:** guess 6-digit codes without IP throttling. A 5-attempt lockout per code is in place (`RESET_MAX_ATTEMPTS`), which is why this is MEDIUM and not HIGH.
- **Impact:** weakens the defence-in-depth around account recovery.
- **Fix:** key the bucket on the real endpoint name, and add a test that every configured bucket names a real endpoint.

### TRP-03 — Third-party-backed endpoints are left unlimited — **MEDIUM** — Verified
- **Location:** `services/rate_limiter.py:47-49` declares `travel.flight_prices_route`, `rates.get_rates` and `rates.get_single_rate` with `limit: None`. `Config.rate_limit_buckets()` never overrides them. The earlier `SECURITY_TESTING_REPORT.md` says these were throttled. **That claim is incorrect.**
- **Impact:** Travelpayouts quota exhaustion. The rates endpoints are cached for 6 h, so their impact is lower.
- **Fix:** add the buckets to `Config`.

### TRP-04 — Admin token can be brute-forced online; comparison is not constant-time — **HIGH** — Verified (no throttling)
- **Location:** `routes/admin.py:42-56, 115-121`. None of the `/api/admin/*` endpoints has a bucket. `login-status` is a public yes/no oracle. The hand-rolled comparison exits early on a length mismatch.
- **Exploit:** unlimited guesses against `/api/admin/login-status`. Feasibility depends on the token's entropy, which the repository does not show.
- **Impact:** a correct guess exposes every user's name, email, region, trips and the IP activity log.
- **Fix:** strict per-IP bucket on every admin endpoint, `hmac.compare_digest`, a startup warning for short tokens. Longer term: role-based admin users (TRP-17).

### TRP-05 — Email change does not require re-authentication — **HIGH** — Verified
- **Location:** `routes/auth.py:1622-1648`.
- **Exploit:** someone holding a stolen or borrowed access token (15 min) sends `PATCH /api/auth/me {"email": "attacker@…"}`, then uses forgot-password. The reset code goes to the attacker's address.
- **Impact:** a short-lived session compromise becomes a **permanent account takeover**.
- **Fix:** require `currentPassword` whenever the email actually changes. Refuse email changes on social-only accounts, because their email is bound to the provider identity. **API change:** the client must send `currentPassword` with an email change. The Flutter service is updated to do this.

### TRP-06 — Pre-account-takeover through automatic social linking; unverified provider emails accepted — **HIGH** — Verified
- **Location:** `routes/auth.py:678-706` (links any existing same-email account); `routes/auth.py:716` and `services/social_auth_service.py:103` (Google `email_verified=false` is accepted).
- **Exploit:** the attacker registers `victim@gmail.com` with a password. Registration does not verify email (TRP-15). The victim later uses "Sign in with Google", and the backend silently links the identity to the attacker-created row. The attacker's password still opens the account the victim now fills with data.
- **Impact:** the attacker gets full read/write access to the victim's account.
- **Fix:** reject provider identities whose email is not verified. Never auto-link a provider identity to an existing password account (return 409, as the code already does for a different-provider conflict). A legitimate owner can recover through forgot-password, which also ends every other session (token_version bump). **Behaviour change:** the existing test `test_links_existing_password_account_to_google` encoded the unsafe behaviour and is updated.

### TRP-07 — Account deletion fails for any user with a refresh token — **HIGH** (privacy/compliance) — Verified
- **Location:** `routes/auth.py:1810-1856` does not delete `user_refresh_tokens`. The FK has no `ON DELETE CASCADE` (`migrations/versions/b7c1d2e3f4a5_create_user_refresh_tokens.py:46-50`).
- **Exploit/impact:** every user who has logged in gets HTTP 500 on `DELETE /api/auth/account`, and their data is retained. This breaks the in-app deletion that GDPR and the App Store / Play require. PostgreSQL always enforces FKs. SQLite hid the bug until `PRAGMA foreign_keys=ON` was set.
- **Fix:** delete the user's refresh tokens inside the deletion transaction.

### TRP-08 — Public page-view beacon trusts a client-supplied `userId` — **MEDIUM** — Verified
- **Location:** `routes/admin.py:339-345`.
- **Exploit:** an anonymous caller sends `{"path": "...", "userId": <any id>}`. That forges analytics attributed to real users. A non-existent id causes an FK error and HTTP 500. The Flutter client never sends `userId`.
- **Fix:** ignore the body value. Attribute the event only from a valid JWT.

### TRP-09 — Password change accepts 6-character passwords — **LOW** — Verified
- **Location:** `routes/auth.py:1700`. Registration and reset require 8 characters.
- **Fix:** one shared password policy (minimum 8, maximum 128, not all whitespace, not on a small common-password list) used by register, reset and change.

### TRP-10 — Client IP handling behind Render's proxy — **HIGH** (availability) — Potential
- **Location:** `app.py:86` uses `request.remote_addr` with no `ProxyFix`. `app.py:391-394` and `routes/admin.py:364-368` read the raw, spoofable `X-Forwarded-For`.
- **Exploit:** behind Render's load balancer, `remote_addr` is the proxy's address. All anonymous users then share one login/register/reset bucket (10 per 10 min), and one script can lock everyone out of login. Separately, the audit IP stored in `activity_logs` can be set to any value by the caller.
- **Fix:** `werkzeug.middleware.proxy_fix.ProxyFix`, with the trusted hop count read from `TRUSTED_PROXY_HOPS`. The default is 1 when Render's `RENDER` env var is present and 0 otherwise. Use `request.remote_addr` everywhere.

### TRP-11 — Account enumeration — **LOW** — Verified (login), Code-verified (register, timing)
- **Location:** `routes/auth.py:572-580` gives a distinct message for social-only accounts. `register` returns 409 for an existing email. `login` skips password hashing for unknown emails, so response timing reveals which accounts exist. `forgot-password` only sends SMTP for real accounts, which is also a timing difference.
- **Fix:** generic login message plus a dummy hash check. The 409 on register is kept as a UX trade-off and is documented. The forgot-password timing difference is documented; the fix is async email delivery.

### TRP-12 — Responses with tokens and personal data are cacheable — **LOW** — Verified
- **Fix:** `Cache-Control: no-store` and `Pragma: no-cache` on every `/api/` response that is authenticated or comes from `/api/auth/*`.

### TRP-13 — Provider verification errors returned verbatim to clients — **LOW** — Verified
- **Location:** `services/social_auth_service.py:91,148` passes library exception text into `SocialAuthError`. `routes/auth.py:765-768` returns it. `routes/trips.py:1030-1037` returns a raw `RuntimeError` message.
- **Fix:** generic client messages. Details go to the server log only.

### TRP-14 — Development server runs with `debug=True` — **LOW** — Code-verified (Bandit B201)
- **Location:** `app.py:463-469`. Gunicorn imports `wsgi:app`, so production is not affected unless someone runs `python app.py` on a server.
- **Fix:** debug only when `FLASK_DEBUG=1`, bound to 127.0.0.1 by default.

### TRP-15 — Registration does not verify email; `email_verified` defaults to `True` — **MEDIUM** — Code-verified — *Requires a product decision*
- **Location:** `routes/auth.py:485`, `models/user.py:30`.
- **Impact:** free throwaway accounts multiply every per-user limit. This is the root cause of TRP-06. Admin "verified" counts are meaningless.
- **Recommendation:** add verification (code by email, reusing `email_service`) before generating trips. This changes the sign-up UX, so it is **not** changed in this pass.

### TRP-16 — Account deletion does not require re-authentication — **MEDIUM** — Code-verified — *Requires UI change*
- A stolen 15-minute token can delete the account. The fix needs a password prompt in the delete dialog. Not changed in this pass; recommended.

### TRP-17 — Admin authentication is one shared static secret, kept in browser storage — **MEDIUM** — Code-verified
- **Location:** `routes/admin.py`; `frontend/lib/services/admin_service.dart:23-33` uses SharedPreferences (localStorage on web).
- **Impact:** no per-admin identity, no audit trail, no revocation short of rotating the secret, and the secret is readable by any XSS on the web origin.
- **Recommendation:** an admin role on `users`, admin access through the normal JWT, MFA. Mitigated in this pass by TRP-04.

### TRP-18 — Rate limits are per-process and reset on restart — **MEDIUM** — Code-verified
- With 2 Gunicorn workers, effective limits are up to 2× the configured values and reset on each deploy.
- **Recommendation:** a Redis-backed `RateLimitStorage`; the interface already exists.

### TRP-19 — Prompt injection through trip fields — **LOW** — Code-verified
- **Location:** `services/itinerary_service.py:674-690, 1245-1262`. User text is interpolated straight into the prompt.
- **Existing mitigations:** inputs are length-capped, output is schema-constrained JSON validated server-side (`_validate_itinerary`, `_validate_swap_activity`), the model has no tools, the output only reaches the requester's own trip, and Flutter renders it as plain text (no HTML/WebView).
- **Fix:** fence user values in a clearly delimited data block, with an instruction to treat it as data and never as instructions.

### TRP-20 — Database TLS is not enforced by the application — **MEDIUM** — Potential
- **Location:** `settings.py:58-64` builds the URI without `sslmode`. Neon rejects plaintext, but a migration to another host would silently allow it.
- **Fix:** `DB_SSLMODE`, defaulting to `require` for non-local hosts.

### TRP-21 — Web frontend served without security headers — **MEDIUM** — Code-verified
- **Location:** `frontend/vercel.json` has no `headers` block.
- **Fix:** HSTS, `X-Content-Type-Options`, `X-Frame-Options`/`frame-ancestors`, `Referrer-Policy`, `Permissions-Policy`. A full CSP for Flutter web needs a staging pass (CanvasKit/WASM, Google Sign-In) and is documented as follow-up.

### TRP-22 — Reset-token lookup scans every pending token with scrypt — **LOW** — Code-verified
- **Location:** `routes/auth.py:1412-1430`. CPU cost grows with concurrent resets. The reset token has 256 bits of entropy, so an indexed SHA-256 lookup would be safe. Documented; not changed, because changing it would invalidate in-flight reset tokens.

### TRP-23 — Apple nonce is optional — **LOW** — Code-verified
- `services/social_auth_service.py:151`. An identity token captured in flight could be replayed until it expires. Apple sign-in is not active in the app. Documented.

### TRP-24 — No strength check on `JWT_SECRET_KEY` / `ADMIN_API_TOKEN` — **LOW** — Code-verified
- **Fix:** log a startup warning below 32 characters. It does not fail hard, so an existing deployment cannot be bricked.

### TRP-25 — Verbose logging — **INFORMATIONAL**
- `app.py:30-35` logs the Travelpayouts key **length**. `itinerary_service.py:952,1412` logs raw Gemini output at ERROR level, which echoes user trip data. **Fix:** remove the key-length log. Raw AI output moves to DEBUG.

### TRP-26 — CORS falls back to localhost origins when `CORS_ORIGINS` is unset — **INFORMATIONAL**
- Bearer tokens are not ambient credentials, so CORS is not an auth boundary here. Set `CORS_ORIGINS` explicitly in production.

### TRP-27 — Android release builds fall back to debug signing — **LOW** — Code-verified
- `frontend/android/app/build.gradle.kts:71-73`. A store build signed with the debug key cannot be updated later. Make CI fail when `key.properties` is missing for release.

## 2. Controls verified as sound

- **SQL injection:** all queries use the ORM or bound parameters. No string-built SQL was found (`grep` for `text(f`, `execute(f`). Existing tests: `test_sql_injection*.py`.
- **JWT:** algorithm fixed to HS256 by Flask-JWT-Extended. Tests cover `alg=none`, algorithm confusion, forged signatures, expiry, malformed `sub`. A `ver` claim tied to `users.token_version` revokes tokens on password change, reset and deletion. The check fails closed.
- **Refresh tokens:** stored hashed, rotated on every use, family revoked on reuse, revoked on logout, password change and reset.
- **IDOR:** every trip, expense and weather query filters on `user_id` from the JWT; cross-user access returns 404. Postgres RLS on `trips` adds a second layer.
- **Password storage:** Werkzeug `scrypt` (salted, memory-hard). The prompt asks for Argon2id or bcrypt. scrypt is an OWASP-accepted alternative, so migrating would add risk without a security gain. Kept.
- **Password reset:** hashed 6-digit code, 15 min lifetime, 5-attempt lockout, single-use 30 min token, atomic conditional UPDATEs (race-tested), all sessions revoked on reset.
- **Secrets:** no secret files tracked in git (only `key.properties.example`). No Gemini or other provider keys in the Flutter code. All provider keys are server-side.
- **Request size:** `MAX_CONTENT_LENGTH` = 1 MB. Trip fields are length-capped; trip duration is capped at 365 days.
- **Flutter tokens:** `flutter_secure_storage`, no plaintext fallback, legacy SharedPreferences token migrated and deleted.
- **Dependencies:** `pip-audit -r backend/requirements.txt` reports **no known vulnerabilities** (2026-11-09).

## 3. Assessments

| Area | Assessment |
|---|---|
| **Overall posture** | Moderate. The core primitives (JWT, refresh rotation, ownership checks, ORM, reset flow) are well built and tested. The weaknesses are in the **seams**: rate-limit coverage, account-lifecycle flows (email change, social linking, deletion), the admin surface, and proxy-aware IP handling. |
| **Critical attack surfaces** | `/api/auth/*` (account lifecycle), `/api/trips/*` AI endpoints (cost), `/api/admin/*` (all PII behind one secret), the Render proxy boundary. |
| **AuthN/AuthZ** | Strong token mechanics. Weak at re-authentication for sensitive changes (TRP-05, TRP-16), identity linking (TRP-06) and email ownership (TRP-15). Authorization (ownership) is consistently enforced. |
| **Database** | ORM-only, parameterised, RLS on trips. Gaps: TLS not enforced in config (TRP-20), a missing cascade (TRP-07), and the app runs as the owner role (no runtime/migration privilege split; see roadmap). |
| **API** | Good validation on trips and expenses. Rate-limit coverage is the main gap (TRP-01..04). The limiter **fails open** for endpoints it does not know. |
| **Infrastructure** | API sets security headers and HSTS behind TLS. The web frontend sets none (TRP-21). In-process limiter (TRP-18). |
| **Dependencies** | Python: clean. Dart/Flutter: no automated advisory scan in CI. Recommend `dart pub outdated` review plus Dependabot for `pub`. |

## 4. Prioritised remediation roadmap

| Priority | Items | Plan |
|---|---|---|
| P0 (this pass) | TRP-01, 04, 05, 06, 07, 10 | Fix, then regression-test |
| P1 (this pass) | TRP-02, 03, 08, 09, 11, 12, 13, 14, 19, 20, 21, 24, 25 | Fix, then regression-test |
| P2 (needs product/infra decision) | TRP-15 email verification, TRP-16 re-auth on delete, TRP-17 admin roles + MFA, TRP-18 Redis limiter, runtime vs. migration DB roles | Documented with an implementation plan in `SECURITY_HARDENING_REPORT.md` |
| P3 | TRP-22, 23, 26, 27, full web CSP | Documented |

---

## 5. Phase 2 addendum (2026-11-09)

Re-inspection of the then-current tree (branch `security-hardening`, uncommitted on top of `c543a43`) before phase-2 changes. Database architecture confirmed: **PostgreSQL on Neon** (psycopg 3), Render web service (Gunicorn, 2 workers), Vercel static Flutter web build.

### 5.1 Status of previously open items

| ID | Phase-1 status | Phase-2 result |
|---|---|---|
| TRP-10 | Fixed in code, unverifiable locally | Hardened (IP validation, IPv6 /64, malformed-header fallback) and tested for spoofed/multi-hop/malformed/direct cases. Render hop count still needs a production check (hardening report §8). |
| TRP-15 | Open (product decision) | **Fixed**: email verification |
| TRP-16 | Open | **Fixed**: password / fresh provider re-auth for deletion |
| TRP-17 | Partly mitigated | **Fixed**: admin accounts, mandatory TOTP, sessions, audit; legacy token behind a flag pending migration |
| TRP-18 | Open | **Fixed**: Redis-backed limiter with documented failure mode |
| TRP-21 (CSP part) | Open | CSP written, verified in a real browser in **enforcing** mode, shipped **report-only** |
| TRP-22 | Open | **Fixed**: SHA-256 indexed reset tokens; legacy scrypt tokens still accepted until they expire |
| TRP-23 | Open | **Fixed**: Apple nonce mandatory |
| P2-5 (DB roles) | Open | **Implemented** (`backend/db/roles.sql`) and verified against PostgreSQL 16; production switch needs owner action |

### 5.2 New findings in phase 2

| ID | Severity | Finding | Location | Status |
|---|---|---|---|---|
| TRP-28 | MEDIUM | Refresh-token rotation was check-then-update: two concurrent refreshes with the same token could both succeed, forking the session family | `routes/auth.py::_rotate_refresh_token` | Fixed (conditional UPDATE; the loser revokes the family) |
| TRP-29 | MEDIUM | RLS context was set once per request with a transaction-local `set_config`; any mid-request `commit()` dropped it, and a session spanning requests kept the previous request's context | `app.py::_set_rls_context` | Fixed (`services/db_context.py`, re-applied at every transaction start and on context change) |
| TRP-30 | MEDIUM | RLS policies cast `current_setting(...)::integer`; once the GUC has been set on a pooled connection it reverts to `''`, so `''::integer` raises on later unauthenticated queries | migrations `f0e9d8c7b6a5`, `3e2d1c0b9a87` | Fixed (`NULLIF(...,'')`, migration `a9b8c7d6e5f4`) |
| TRP-31 | MEDIUM | `users` RLS had owner-only SELECT/UPDATE and no INSERT/DELETE policies: a least-privilege role could not log in, register or delete accounts, which blocked privilege separation | `f0e9d8c7b6a5` | Fixed (auth-flow / admin-read / owner-delete policies) |
| TRP-32 | LOW | Migration chain could not build an empty database (`DROP TABLE place_coordinates` on a table no migration creates): disaster recovery / CI / staging builds fail | `0922f2fc8de9` | Fixed (`DROP TABLE IF EXISTS`; full chain now runs in CI) |
| TRP-33 | LOW | Omitting the optional `budget` crashed cost calculation (HTTP 500) | `services/cost_service.py` | Fixed |
| TRP-34 | LOW | Registration still revealed existing accounts (409) | `routes/auth.py::register` | Fixed (identical 201 for every address; owner receives a notice email) |
| TRP-35 | INFO | The `google_sign_in` web plugin loads `accounts.google.com/gsi/client` at startup although Google sign-in is disabled on web | Flutter web | Blocked by the new CSP; allow it only if web Google sign-in is enabled |
| TRP-36 | INFO | Flutter tests `login_gate_test` and `layout_probe_test` hung or failed after the phase-1 token-store change (secure-storage I/O inside fake-async) | `frontend/test` | Fixed in the test harness |
| TRP-37 | INFO | `frontend/web/index.html` has no `<!DOCTYPE html>`/`<html>`/`<head>` (quirks mode); a 370 MB JDK sits in `frontend/web/` (git-ignored, so not deployed by Vercel, but a local `flutter build web` copies it into `build/web`) | `frontend/web` | Documented; not changed |
| TRP-38 | INFO | The admin UI has no in-app entry point or deep link (the app always starts at Home) | `lib/main.dart` | Documented; not changed |

### 5.3 Items reviewed with no new issue found

Mass assignment (`PATCH /me` whitelists fields; `role`/`emailVerified` ignored — tested), IDOR (all new endpoints derive identity from the token), CSRF (bearer tokens, no cookies), session fixation (admin pending→active token rotation; user tokens minted at login), SSRF (outbound hosts are fixed: Open-Meteo, Frankfurter, Travelpayouts, Duffel, Apple JWKS, Google certs), open redirects (none), file upload (none), logs (no codes, tokens, secrets or passwords logged by new code), cryptography (secrets module, SHA-256 for high-entropy tokens, scrypt for low-entropy codes/passwords, Fernet for TOTP secrets, HMAC-SHA1 TOTP per RFC 6238, constant-time comparisons).

### 5.4 Production database inspection (2026-11-10, read-only) and branch rehearsal

Neon project "Tripora" (`lively-term-04990062`, PostgreSQL 18), database `tripora`:

| ID | Severity | Finding | Status |
|---|---|---|---|
| TRP-39 | MEDIUM | The app connects as `neondb_owner`, which has **`BYPASSRLS`**. Row-Level Security, FORCE included, has never been enforced in production; code comments assumed it was. Ownership is still enforced in application code (IDOR tests), so this is a missing defence-in-depth layer, not an open IDOR. | Fixed by moving the web service to `tripora_runtime` (rehearsed; production switch pending, needs the new code first) |
| TRP-40 | MEDIUM | Roles created in the Neon Console/API become members of `neon_superuser` (BYPASSRLS). Creating the runtime role that way would quietly undo TRP-39's fix. | `roles.sql` and `docs/DEPLOYMENT.md` now say to create the role with SQL; the rehearsal verified no memberships |
| TRP-41 | INFO | Production schema is at `0922f2fc8de9`, so the phase-1 migrations (refresh tokens, token_version) were never applied. The deployed code is pre-phase-1. | Four pending migrations, all additive, rehearsed |
| TRP-42 | INFO | Neon's owner cannot even *mention* SUPERUSER/REPLICATION/BYPASSRLS in `ALTER ROLE` (`roles.sql` failed on it) | `roles.sql` fixed; attributes verified by query instead |

**Branch rehearsal.** Branch `security-rehearsal-2026-11-10` (`br-long-unit-b37mxs6q`) is a copy of production data with 17 users and 25 trips. It was done entirely through Neon server-side SQL; no credentials were exported.

- **Migrations:** all 53 statements of `0922f2fc8de9 → a9b8c7d6e5f4` applied in one transaction without error.
- **Role:** `tripora_runtime` was created with SQL, without a password. Attributes: all false; memberships: none.
- **RLS as `tripora_runtime`:**
  - no context: 0 users, 0 trips, 0 expenses visible;
  - an empty subject raises no error;
  - auth-flow: 17 users visible;
  - subject = user 9: only user 9's own row, their 13 trips, 0 foreign expenses;
  - admin-read: 17 users and 25 trips visible.
- **Forbidden operations, all rejected:** `DROP TABLE`, `CREATE TABLE`, `TRUNCATE`, reading `alembic_version`, `DELETE` on `admin_audit_log`, `SET row_security = off`, `ALTER TABLE ... DISABLE RLS`, `CREATE ROLE`, writing an invalid role value (CHECK constraint).
- **App-level flows on PostgreSQL 18** (local container, same migrations + `roles.sql`): `test_postgres_runtime_role.py` 13/13 passed.
