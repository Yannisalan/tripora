# Tripora — Security Hardening Report

- **Date:** 2026-11-09
- **Companion documents:** `SECURITY_AUDIT_REPORT.md` (findings TRP-01…27), `SECURITY_TESTING_GUIDE.md`, `SECURITY.md` (policy, env vars, incident response).
- **Environment:** all testing ran locally (in-memory SQLite, AI/weather/email stubbed). Nothing was run against Render, Vercel, Neon or any third-party API.

> Tripora is materially harder to attack than at the start of this pass. It is **not** "secure" in any absolute sense. §6 lists what remains, and several items need decisions only the product owner can make.

## 1. Verification method

For every CRITICAL/HIGH finding and most MEDIUM/LOW ones:
1. A test asserting the secure behaviour was written in `security/tests/test_audit_remediation.py`.
2. It ran against the unmodified code. **16 of 19 tests failed**, which reproduced the weakness (TRP-01…09, 11, 12, 13).
3. The fix was applied, and the same test was re-run. It passed.
4. The full suite was re-run. 5 pre-existing tests failed because they asserted the old unsafe behaviour. They were rewritten to assert the secure contract (§4). None was deleted or loosened in a way that hides a defect.

TRP-10 (proxy IP) cannot be reproduced locally because it depends on Render's proxy. It is covered by two tests: spoofed `X-Forwarded-For` is ignored without a trusted hop, and with one trusted hop the proxy-appended address is used.

## 2. Findings: before → after

| ID | Severity | Finding | Status | Evidence |
|---|---|---|---|---|
| TRP-01 | HIGH | AI swap endpoint unlimited | **Fixed**: `trips.swap_activity` bucket (20/10 min), and the limiter now fails closed (`DEFAULT_READ`/`DEFAULT_WRITE`) for any endpoint without a bucket | `test_trp01_*`, `test_unbucketed_write_endpoint_falls_back_to_default_write` |
| TRP-02 | MEDIUM | Reset-code verify unthrottled (wrong bucket name) | **Fixed** | `test_trp02_*`, `test_every_configured_bucket_names_a_real_endpoint` |
| TRP-03 | MEDIUM | Flight-prices and rates endpoints unlimited | **Fixed** | `test_trp03_*` (2 cases) |
| TRP-04 | HIGH | Admin token brute force; non-constant-time compare | **Fixed**: per-IP admin buckets (`login-status` 10/10 min, others 60/10 min), `hmac.compare_digest`, weak-secret startup warning | `test_trp04_*` |
| TRP-05 | HIGH | Email change without re-auth leads to account takeover | **Fixed**: `currentPassword` required for an actual email change; social-only accounts cannot change email; basic format check | `test_trp05_*` (3 cases) |
| TRP-06 | HIGH | Pre-account-takeover through social auto-linking; unverified provider email accepted | **Fixed**: no auto-linking (409); `email_verified` must be `true` (403) | `test_trp06_*` (2), updated `test_google_social_auth.py` |
| TRP-07 | HIGH | Account deletion fails (FK on refresh tokens) | **Fixed**: refresh tokens deleted in the same transaction | `test_trp07_*` (with SQLite FK enforcement on) |
| TRP-08 | MEDIUM | Page-view beacon trusts body `userId` | **Fixed**: attribution only from a valid JWT | `test_trp08_*` (2) |
| TRP-09 | LOW | 6-char password on change | **Fixed**: shared policy (8–128, not blank, common-password list) for register, reset and change; Flutter validator aligned to 8 | `test_trp09_*`, `test_registration_rejects_weak_passwords` (4) |
| TRP-10 | HIGH (potential) | Proxy address used as client IP; spoofable XFF in logs | **Fixed**: `ProxyFix` with `TRUSTED_PROXY_HOPS` (auto 1 on Render, else 0); `remote_addr` everywhere | `test_trp10_*` (2), `test_trusted_proxy_hop_uses_proxy_appended_address` |
| TRP-11 | LOW | Login enumeration (message and timing) | **Fixed** for login (generic message plus dummy hash). Register 409 kept (UX); forgot-password SMTP timing documented | `test_trp11_*` |
| TRP-12 | LOW | Token/PII responses cacheable | **Fixed**: `Cache-Control: no-store` on `/api/auth/*` and authenticated `/api/*` | `test_trp12_*` |
| TRP-13 | LOW | Provider/library errors returned to client | **Fixed** | `test_trp13_*` |
| TRP-14 | LOW | `debug=True` dev runner | **Fixed**: opt-in `FLASK_DEBUG=1`, loopback bind (also `wsgi.py`) | Bandit: 0 medium+ findings |
| TRP-15 | MEDIUM | No email verification at registration | **Open**: product decision (§6) | — |
| TRP-16 | MEDIUM | Delete account without re-auth | **Open**: needs a UI prompt (§6) | — |
| TRP-17 | MEDIUM | Shared static admin secret, kept in browser storage | **Partly mitigated** (TRP-04); redesign open (§6) | — |
| TRP-18 | MEDIUM | Per-process in-memory limiter | **Open**: infra (§6) | — |
| TRP-19 | LOW | Prompt injection | **Mitigated**: user values fenced as data in both prompts; existing schema plus validation retained | Review only (no LLM in tests) |
| TRP-20 | MEDIUM (potential) | DB TLS not enforced | **Fixed**: `DB_SSLMODE`, default `require` for remote hosts | Config review |
| TRP-21 | MEDIUM | Web app without security headers | **Fixed** (HSTS, nosniff, XFO, Referrer-Policy, Permissions-Policy, COOP). **CSP open** | `frontend/vercel.json` |
| TRP-22 | LOW | O(n) scrypt scan for reset token | **Open** (documented) | — |
| TRP-23 | LOW | Apple nonce optional | **Open** (Apple sign-in not shipped) | — |
| TRP-24 | LOW | No secret-strength check | **Fixed** (startup warning, non-fatal) | — |
| TRP-25 | INFO | Key length logged; raw AI output at ERROR | **Fixed** (presence only; AI output to DEBUG) | — |
| TRP-26 | INFO | CORS localhost fallback | **Documented** (set `CORS_ORIGINS`) | — |
| TRP-27 | LOW | Android release falls back to debug signing | **Open** (documented) | — |

Also fixed while reviewing:
- The SMTP port default was a typo, `4665`. It is now `465`, so password-reset email works when `MAIL_PORT` is unset.
- `docs/DEPLOYMENT.md` claimed that reset codes are logged when SMTP is unset. The code does not log them, and the doc is corrected.
- The earlier `SECURITY_TESTING_REPORT.md` claimed rates and flight-price buckets were added. They were configured with `limit: None`. That is now corrected (TRP-03).

## 3. Before / after

| Area | Before | After |
|---|---|---|
| Account takeover paths | 2 verified (TRP-05 email change, TRP-06 social pre-hijack) | 0 known; residual root cause TRP-15 |
| Endpoints with no rate limit | swap (Gemini), verify-reset-code, flight prices, 2× rates, 5× admin, any future route | none: unknown routes get default budgets |
| Account deletion | HTTP 500 for every user who had logged in | works; refresh tokens removed |
| Client IP trust | proxy IP (shared bucket) or caller-chosen XFF | real client IP from trusted hop count only |
| Enumeration | login revealed social-only accounts and timing | uniform message and timing on login |
| Password policy | 8 on register/reset, 6 on change, no upper bound | 8–128 everywhere, common list blocked |
| Response caching | unspecified | `no-store` on auth and authenticated API |
| Web headers | none | HSTS, nosniff, XFO, Referrer, Permissions, COOP |
| CI | pytest + pip-audit | + Bandit (gating), Semgrep (reporting), Flutter analyze/tests, weekly schedule, Dependabot (pip, pub, actions) |
| Security tests | 348 | **375** (27 new in `test_audit_remediation.py`) |

## 4. API / behaviour changes (documented contract changes)

| Change | Who is affected | Migration |
|---|---|---|
| `PATCH /api/auth/me` with a **new** `email` now needs `currentPassword` (401 otherwise). Social-only accounts get 400. | Profile screen | `AuthService.updateCurrentUser` now sends `currentPassword` whenever the user typed it. Users open the "change password" section, enter the current password and save. Re-sending the unchanged email still needs no password. |
| Social sign-in for an email that already has an account returns **409** instead of linking | Hidden in the app (`showThirdPartyAuth=false`) | The user signs in with their password. Proper linking ("link Google" while signed in) is a follow-up. |
| Social sign-in with an unverified provider email returns **403** | Rare (mostly Workspace accounts) | None |
| Login for social-only accounts returns the generic "Invalid email or password." | Hidden feature | None |
| Weak or common passwords rejected at register, reset and change | New passwords only; existing logins unaffected | None |
| Page-view beacon bucket changed from 10/10 min to 60/min | Analytics only (the old limit dropped most events) | None |

Tests rewritten because they asserted the old unsafe behaviour: `test_google_social_auth.py` (4 tests) and `test_sql_injection_audit.py::test_patch_email_payloads_do_not_bypass_conflict_check` (now supplies `currentPassword`).

## 5. Files

**Modified:** `backend/app.py`, `backend/config/settings.py`, `backend/routes/auth.py`, `backend/routes/admin.py`, `backend/routes/trips.py`, `backend/services/itinerary_service.py`, `backend/wsgi.py`, `frontend/lib/services/auth_service.dart`, `frontend/lib/screens/profile/profile_screen.dart`, `frontend/vercel.json`, `.github/workflows/security.yml`, `docs/DEPLOYMENT.md`, `security/tests/test_google_social_auth.py`, `security/tests/test_sql_injection_audit.py`.

**Added:** `SECURITY_AUDIT_REPORT.md`, `SECURITY_HARDENING_REPORT.md`, `SECURITY_TESTING_GUIDE.md`, `SECURITY.md`, `backend/.env.example`, `.github/dependabot.yml`, `security/tests/test_audit_remediation.py`.

**New runtime dependencies:** none. `ProxyFix` and `hmac` already ship with Werkzeug and the standard library. **CI-only tools:** Bandit, Semgrep, pip-audit, subosito/flutter-action.

**Database migrations:** none needed for these fixes.

## 6. Tests executed (2026-11-09, local)

| Command | Result |
|---|---|
| `pytest` (security suite) before changes | 348 passed |
| `pytest security/tests/test_audit_remediation.py` before fixes | **16 failed, 3 passed** (weaknesses reproduced) |
| same, after fixes | 27 passed (incl. new guards) |
| `pytest` (security suite) after | **375 passed, 0 failed** |
| `pytest backend -m "not integration"` | 42 passed, 2 deselected |
| `pip-audit -r backend/requirements.txt` | No known vulnerabilities |
| `bandit -r backend … -ll` | 0 medium/high issues (before: B201 debug=True HIGH, 2× B104) |
| `flutter analyze` | No issues |
| `flutter test` auth/token/api-client tests | 22 passed |
| Semgrep | **Not run locally** (no Windows build). Wired into CI as report-only until a baseline is triaged |

## 7. Remaining risks and recommended next steps

| # | Item | Why it's open | Recommended implementation |
|---|---|---|---|
| P2-1 | **Email verification** (TRP-15) | Changes the sign-up UX | Send a 6-digit code at register (reuse the reset-code machinery and `email_service`); `email_verified=False` until confirmed; block trip generation until verified; stop defaulting `email_verified=True` in `User.__init__`. |
| P2-2 | **Re-auth for account deletion** (TRP-16) | Needs a password field in the delete dialog | Accept `currentPassword` on `DELETE /api/auth/account` (social accounts: fresh provider token). |
| P2-3 | **Admin redesign** (TRP-17) | Architecture change | `users.role`; admin endpoints behind JWT plus role check; MFA (TOTP); audit log of admin reads; drop the shared token and its localStorage copy. |
| P2-4 | **Shared rate-limit store** (TRP-18) | Needs Redis (e.g. Render Key Value) | Implement `RateLimitStorage` with `INCR`/`EXPIRE`; keep the in-memory store for tests. |
| P2-5 | **Least-privilege DB roles** | Needs Neon role setup | Runtime role with DML only on app tables (no DDL, no `BYPASSRLS`); a separate owner role used only by `flask db upgrade` in the release step. Admin RLS bypass then needs a `SECURITY DEFINER` view or a dedicated role. |
| P2-6 | **Provider spend caps** | Console setting | Set Gemini, Travelpayouts and Duffel quota alerts and hard caps. |
| P3-1 | Web CSP | Flutter web needs CanvasKit/WASM and Google Sign-In origins; must be tested in staging | Start with `Content-Security-Policy-Report-Only`, collect reports, then enforce. |
| P3-2 | Reset-token lookup (TRP-22) | Would invalidate in-flight reset tokens | Store SHA-256 of the 256-bit token with a unique index; look up directly. |
| P3-3 | Apple nonce (TRP-23) | Apple sign-in not shipped | Make the nonce mandatory before enabling Apple. |
| P3-4 | Android signing (TRP-27) | Build config | Fail `assembleRelease` when `key.properties` is missing. |
| P3-5 | Breached-password check | Network dependency | HIBP k-anonymity range API on register/change. |
| P3-6 | Forgot-password timing | Needs a background job | Queue email delivery so the response time does not depend on SMTP. |
| P3-7 | JWT `iss`/`aud` claims | Low value with a single service | Add when a second token consumer appears. |

## 8. Production deployment requirements

Required before or with this deploy:
1. **Render env:** `JWT_SECRET_KEY` and `ADMIN_API_TOKEN` must each be ≥ 32 random characters. Check the startup log for warnings. `CORS_ORIGINS` must be set to the Vercel origin. Do **not** set `FLASK_DEBUG`. `TRUSTED_PROXY_HOPS` can be left unset (Render auto-detects 1).
2. **DB:** Neon accepts `sslmode=require`. Run `flask db upgrade` for the earlier uncommitted migrations (refresh tokens, token_version) **before** starting the new code.
3. **Vercel:** redeploy so `vercel.json` headers take effect, then verify with `curl -I`.
4. **Branch protection** on `main`: require the `security-tests`, `bandit` and `dependency-audit` checks.
5. **Smoke test after deploy:** register, log in, generate a trip, swap an activity, change the email (with current password), delete a test account.

## 9. Ongoing practice

- Every security fix ships with a test that fails on the old code.
- Merge Dependabot PRs weekly. A failing pip-audit blocks the merge.
- Triage the Semgrep baseline, then make it gating.
- Re-run this audit after any new endpoint, provider or auth change.
- Run an external penetration test before any marketing launch or once real user volume exists.


---

# Phase 2 (2026-11-09)

- **Branch:** `security-hardening`, created from `main`. **Nothing has been committed.**
- **Method:** same as phase 1. Write a failing test first where the weakness is reproducible, then fix, then run the full regression.
- **New in phase 2:**
  - tests against a **real PostgreSQL 16**, with the app connected as the least-privilege role;
  - tests against a **real Redis 7** (both local, disposable containers);
  - **headless Chrome** runs of the Flutter web build with the CSP **enforced**.

## P2.1 Resolved

| Item | What was built | Verified by |
|---|---|---|
| **TRP-15 Email verification** | See details below | `test_phase2_hardening.py::TestEmailVerification` (16 tests); browser E2E: register, then 403 on trips, then verify, then 200 |
| **TRP-16 Account deletion** | See details below | `TestAccountDeletion` (7 tests, including 3 trips + expenses + weather + 2 refresh tokens + logs, with SQLite FK enforcement on); PG runtime-role E2E; browser E2E (wrong password: 401, account kept; correct: 200, row gone, login fails) |
| **TRP-17 Admin authentication** | See details below | `TestAdminAuth` (14 tests) + RFC 6238 vectors; PG runtime-role admin test; live HTTP E2E against the runtime-role server; `admin_login_screen_test.dart` (2 tests) |
| **DB privilege separation** | See details below | `test_postgres_runtime_role.py` (13 tests): 9 forbidden statements rejected, role attributes, RLS fails closed, full user + admin flows as the runtime role |
| **TRP-10 Proxy** | `services/client_ip.py`, see details below | 8 parametrised resolution cases, an IPv6 test, and a login-budget-behind-proxy test |
| **TRP-18 Distributed limiter** | `RedisRateLimitStorage`, see details below | `test_redis_rate_limiter.py` (7 tests, real Redis: cross-worker sharing, restart persistence, exactly 10 of 60 allowed under threads, TTL, outage fallback/closed); limiter unit tests (4) |
| **CSP** | Policy in `frontend/vercel.json` as **Report-Only**; reports collected by `POST /api/csp-report` | Headless Chrome against the release web build with the policy **enforced** (results below) |
| TRP-22, 23, 28–34, 36 | See audit report §5.2 | Tests in `test_phase2_hardening.py`, the PG suite and the Flutter suite |

### TRP-15: email verification

**Backend**
- Code: 6 digits, scrypt-hashed, valid 30 minutes.
- Lockout after 5 wrong attempts.
- Single use, enforced by a conditional UPDATE.
- Resend: 60 s cooldown plus a per-user hourly limit.
- `POST /api/auth/verify-email` and `POST /api/auth/verify-email/resend` both require a signed-in session. Verifying therefore needs both the password and the inbox.
- Until verified, trips, AI, expenses, travel and weather return `403 {"error":"email_unverified"}`. Verification status is read from the database on every request.

**Registration**
- Identical response for new, unverified and existing addresses.
- Owners of existing accounts get a rate-limited notice email.
- Re-registering an *unverified* address replaces its credentials and revokes its sessions, which evicts squatters.
- A password reset marks the address as verified.
- Google/Apple: the provider must assert `email_verified: true` as a JSON boolean.
- Existing accounts keep their stored verification status.

**Flutter**
- Register signs in automatically and opens the *Verify your email* screen: code entry, resend countdown, expired and already-verified handling, switch account.
- Login sends unverified users to that screen.
- Any API `403 email_unverified` routes there centrally, through `ApiClient`.

### TRP-16: account deletion

**Re-authentication**
- Password accounts must send `currentPassword`.
- Social-only accounts must send a fresh provider token: same `provider_id`, issued at most 10 minutes ago, with the nonce for Apple.

**What is deleted** (one transaction)
- Expenses, weather cache, trips, activity logs and refresh tokens.
- Admin sessions, MFA records and recovery codes.
- Then the user row.
- Admin audit rows are kept, with a NULL actor.

**Other safeguards**
- Refresh tokens now have `ON DELETE CASCADE` as a second line of defence.
- The endpoint is rate-limited per user.

**Flutter**
- First dialog: consequences plus a password field, or "Confirm with Google/Apple" for social accounts.
- Second step: a final "Delete permanently?" confirmation.
- Loading and error states.

No "saved destinations" are stored anywhere, on the server or on the device, so there is nothing extra to delete.

### TRP-17: admin authentication

**Roles**
- New `users.role` column: CHECK `user`/`admin`, default `user`.
- Nobody is granted admin automatically, and no API endpoint writes the role.
- Operator CLI: `flask admin grant`, `reset-mfa`, `revoke`, `revoke-sessions`, `list`.

**Login**
1. Password check creates a pending session (5 minutes).
2. The second factor is a TOTP code or a single-use recovery code.
   - TOTP follows RFC 6238 (stdlib implementation), accepts ±1 time step, and blocks replay via `last_used_step`.
3. Success issues a **new** active session token, so the pending token cannot be reused.

**Enrollment**
- Only possible inside a 24-hour window opened by the CLI.
- TOTP secrets are Fernet-encrypted with `MFA_ENCRYPTION_KEY`.
- 10 recovery codes are issued, stored as SHA-256 hashes.

**Sessions**
- Opaque 256-bit token; only its hash is stored.
- 30-minute idle timeout and 8-hour absolute lifetime; revocable.
- Ended by a password change or reset, or by role revocation.
- 5 bad codes burn a pending session.

**Authorization and audit**
- Every admin request is authorized server-side.
- Every request is written to `admin_audit_log`, which is append-only for the runtime role.

**Legacy token**
- `ADMIN_API_TOKEN` is still accepted while `ADMIN_LEGACY_TOKEN_ENABLED=true`, so the migration cannot lock you out.
- Each legacy use is audited and logged as a warning.

**Flutter**
- New admin sign-in flow: credentials, then enrollment (setup key / otpauth link) and recovery codes on first use, or code / recovery-code verification afterwards.
- The admin session token is kept in memory only. The old SharedPreferences copy is purged.

### DB privilege separation

**`tripora_runtime` role** (`backend/db/roles.sql`)
- DML only: no DDL, no object ownership, no BYPASSRLS, no CREATEROLE or CREATEDB.
- No access to `alembic_version`.
- No UPDATE or DELETE on `admin_audit_log`.
- Statement and idle-in-transaction timeouts.
- Default privileges cover tables created later.

**Migrations** run as the owner, in a pre-deploy command that uses `DB_MIGRATION_USER` and `DB_MIGRATION_PASSWORD`.

**Required supporting fixes** (TRP-29/30/31)
- The RLS context is re-applied for every transaction.
- RLS policies are NULL-safe.
- New `users` policies cover the pre-authentication flows.
- Admin cross-user reads go through `app.admin_read` instead of `SET row_security = off`.

### TRP-10: proxy handling

- Only the right-most `TRUSTED_PROXY_HOPS` entries are used (ProxyFix).
- The result must parse as an IP address; otherwise the direct peer address is used.
- IPv4-mapped IPv6 addresses are normalised.
- IPv6 clients are rate-limited per /64.

### TRP-18: distributed limiter

- One MULTI/EXEC per request (`SET NX EX` + `INCR`).
- Increment-then-compare, so concurrent requests cannot overshoot the limit.
- Failure strategy:
  - `fallback` (default): per-process memory, an ERROR log line, and a 30 s circuit breaker;
  - `closed`: 503 for the auth, reset, verify, admin and AI buckets.
- No client-side retries; 0.5 s timeouts.
- New buckets: verify, resend, admin auth, CSP reports, and a platform-wide `AI_GLOBAL` (300 per hour).

### CSP

- `POST /api/csp-report` logs only the directive, the blocked origin and the page path.
- Query strings are stripped, bodies are capped at 16 KB, and the endpoint is rate-limited.

**Browser verification, with the policy enforced**
- The app renders: CanvasKit from gstatic, Google Fonts, Unsplash and Wikimedia images.
- Register, verify, trips, profile and delete flows all work.
- The only violation is the unused Google GSI script (TRP-35).
- Report delivery was confirmed in the backend log.

## P2.2 Files

**Backend, modified**
- `app.py`, `config/settings.py`, `routes/auth.py`, `routes/admin.py`
- `services/rate_limiter.py`, `services/social_auth_service.py`, `services/email_service.py`, `services/cost_service.py`
- `models/user.py`, `models/user_refresh_token.py`, `models/__init__.py`
- `migrations/versions/0922f2fc8de9_*.py`, `requirements.txt`, `.env.example`

**Backend, added**
- `models/admin_security.py`, `routes/admin_auth.py`
- `services/admin_auth.py`, `services/cli.py`, `services/client_ip.py`, `services/db_context.py`
- `db/roles.sql`
- `migrations/versions/a9b8c7d6e5f4_email_verification_roles_admin_security.py`

**Flutter, modified**
- `lib/services/auth_service.dart`, `lib/services/admin_service.dart`
- `lib/core/network/api_client.dart`, `lib/core/auth/auth_guard.dart`
- `lib/screens/auth/login_screen.dart`, `lib/screens/auth/register_screen.dart`, `lib/screens/profile/profile_screen.dart`
- `lib/screens/admin/admin_login_screen.dart`, `lib/screens/admin/admin_screen.dart`
- `lib/routes/app_routes.dart`
- `lib/core/l10n/app_localizations.dart`: 39 keys; user-facing strings in all 6 languages, admin strings in English
- `vercel.json`, `test/login_gate_test.dart`, `test/layout_probe_test.dart`

**Flutter, added**
- `lib/screens/auth/verify_email_screen.dart`
- `test/security_phase2_test.dart`, `test/verify_email_screen_test.dart`, `test/admin_login_screen_test.dart`

**Tests**
- Updated helpers: `security/tests/conftest.py`, `security/tests/helpers.py`.
- New test files: `test_phase2_hardening.py`, `test_redis_rate_limiter.py`, `test_postgres_runtime_role.py`.
- Updated test files: `test_audit_remediation.py`, `test_authorization_idor.py`, `test_jwt_token_validation.py`, `test_password_reset.py`, `test_password_reset_concurrency.py`, `test_refresh_tokens.py`, `test_input_validation.py`, `test_sql_injection_audit.py`.
- Each update makes the test assert the new secure contract: credentials on delete, verification before features, generic registration, SHA-256 reset tokens. No test was deleted.

**CI and docs**
- `.github/workflows/security.yml`: new `integration-postgres-redis` job; the full Flutter suite now runs.
- All four security docs and `docs/DEPLOYMENT.md`.

**Migration**
- `a9b8c7d6e5f4`, backward compatible.
- Upgrade, downgrade, then upgrade again was verified on PostgreSQL 16.

**New dependency**
- `redis==8.1.0`, released 2026-07-30; pip-audit clean.
- TOTP, encryption and IP handling use the standard library and the already-pinned `cryptography`.

**New environment variables**
- `MFA_ENCRYPTION_KEY`, `ADMIN_LEGACY_TOKEN_ENABLED`, `ADMIN_SESSION_IDLE_MINUTES`, `ADMIN_SESSION_MAX_HOURS`
- `REDIS_URL`, `RATE_LIMIT_FAILURE_MODE`, `REDIS_RETRY_SECONDS`
- `RATE_LIMIT_VERIFY_*`, `RATE_LIMIT_VERIFY_RESEND_*`, `RATE_LIMIT_AI_GLOBAL_*`
- `DB_MIGRATION_USER`, `DB_MIGRATION_PASSWORD` (deploy step only)

## P2.3 Test execution (2026-11-09, local, all actually run)

| Suite | Result |
|---|---|
| Security suite (`pytest`, SQLite) | **433 passed**, 20 skipped (the opt-in suites below) |
| PostgreSQL runtime-role + Redis integration | **20 passed** (13 + 7) |
| Backend unit (`pytest backend -m "not integration"`) | **42 passed** |
| Flutter `flutter test` (full suite) | **76 passed**. Before this phase, 2 files were failing or hanging. |
| `flutter analyze` | No issues |
| pip-audit | No known vulnerabilities |
| Bandit `-ll` | 0 medium/high. The low-severity hits are false positives (message constants, backoff jitter). |
| Browser E2E (headless Chrome, CSP enforced, runtime role, Redis) | Register, verify, trips, and delete with a wrong then a right password all passed. Admin flow verified over live HTTP and by widget test. |
| Semgrep | **Not run locally** (no Windows build). Runs report-only in CI. |

## P2.4 Remaining risks

| Severity | Risk | Notes / next step |
|---|---|---|
| **MEDIUM** | Production is not yet on the new architecture | Until the owner performs the steps in `docs/DEPLOYMENT.md` (migration, runtime role, Redis, MFA key, admin bootstrap, legacy token off), production keeps phase-1 behaviour. |
| **MEDIUM** | Render proxy hop count not verified in production | `TRUSTED_PROXY_HOPS` defaults to 1 on Render. If Render puts another proxy in front, rate limits fall back to keying on that proxy. Verify once: compare an `ip_address` in `activity_logs` with your real IP. |
| **MEDIUM** | Legacy shared admin token still accepted | Intended until an MFA admin exists; then set `ADMIN_LEGACY_TOKEN_ENABLED=false`. |
| **LOW** | CSP is report-only | Enforce after clean production reports. Flutter web requires `style-src 'unsafe-inline'`. |
| **LOW** | Registration followed by automatic sign-in still lets a caller tell whether a password matches an existing account | Inherent to password login; bounded by the register and login rate limits. |
| **LOW** | `fallback` limiter mode weakens limits per worker during a Redis outage | Choose `closed` if outages are rarer than this risk. |
| **LOW** | Forgot-password response time differs for existing accounts (SMTP) | Needs async email delivery. |
| **LOW** | Android release builds fall back to debug signing (TRP-27) | Build-config decision. |
| **LOW** | Google/Apple re-authentication for deletion is untested on real devices | Social sign-in UI is hidden; only unit-tested with mocked providers. |
| **INFO** | TRP-35, 37, 38 | See audit report §5.2. |

No unresolved CRITICAL or HIGH findings are known. That statement covers the checks performed; it is not a guarantee.

## P2.5 Manual actions that need your authorization

1. Commit the branch (nothing has been committed).
2. Production database (**rehearsed on a Neon branch on 2026-11-10, all green**; see audit report §5.4):
   - apply the 4 pending migrations. They are safe while the old code is still deployed, because every change is additive with defaults;
   - create `tripora_runtime` **with SQL** (not the Neon console) and apply `roles.sql`. Harmless while unused;
   - switch Render `DB_USER`/`DB_PASSWORD` to the runtime role **only after the new code is deployed**. The currently deployed code would fail login under that role.
3. Render:
   - create a Key Value (Redis) instance and set `REDIS_URL`;
   - set `MFA_ENCRYPTION_KEY` and `DB_MIGRATION_*`;
   - set the pre-deploy command.
4. Make sure SMTP or Resend works in production. Sign-up now depends on it.
5. Bootstrap the first admin with `flask admin grant`, enroll TOTP, then disable the legacy token.
6. Redeploy Vercel, watch the CSP reports, and later switch the header to enforcing.
7. Replace the placeholder security contact in `SECURITY.md`.


## P2.6 Production database change log (2026-11-10, authorized by the owner)

Neon project `lively-term-04990062`, branch `production` (`br-sparkling-resonance-b3b58cfb`), database `tripora`.

| Time (UTC) | Step | Result |
|---|---|---|
| 04:58 | Pre-checks: head `0922f2fc8de9`, 17 users, 25 trips, 5 expenses, no `tripora_runtime`; live API healthy, DB-backed login 401 | Matched the rehearsal baseline |
| 05:00 | Backup: branch `backup-before-security-migration-2026-11-10` (`br-bold-lab-b3dfhg6h`, no compute, LSN `0/4CFCEA0`) | Created |
| 05:00 | Rollback script: `backend/db/rollback_a9b8c7d6e5f4_to_0922f2fc8de9.sql` (alembic offline downgrade) | Saved |
| ~05:00 | Migrations `0922f2fc8de9 → a9b8c7d6e5f4` as one transaction: `lock_timeout 5s`, abort if the starting head is wrong, abort if the final head isn't reached; 53 statements identical to the rehearsal | Committed |
| ~05:01 | `CREATE ROLE tripora_runtime LOGIN` (**no password**) + `roles.sql` grants and default privileges. No test-only membership grant. | Committed |
| 05:01 | Verification (read-only) | See below |
| 05:01 | Live app verification | See below |
| 05:03 | Rehearsal branch `br-long-unit-b37mxs6q` deleted after a dependency check | Deleted; production and backup branches remain |

### Database verification

- **Schema and data**
  - head `a9b8c7d6e5f4`;
  - 17 users, 25 trips, 5 expenses (unchanged);
  - all users have `role='user'`, 0 admins, all `token_version=1`;
  - 15 RLS policies.
- **`tripora_runtime` attributes**
  - superuser, createdb, createrole, replication, bypassrls: all false;
  - LOGIN true, connection limit 40;
  - `statement_timeout=30s`, `idle_in_transaction_session_timeout=60s`;
  - member of no role, and owns 0 objects.
- **Privileges**
  - schema: USAGE yes, CREATE no;
  - DML on all app tables (0 tables missing SELECT) and USAGE on all sequences;
  - `alembic_version`: no read;
  - `admin_audit_log`: INSERT only (no UPDATE/DELETE);
  - TRUNCATE: no.
- **Membership:** `neondb_owner` holds `tripora_runtime` with ADMIN option only (no INHERIT, no SET). This is the automatic PG16+ creator grant, and it lets the owner set the role's password.

### Live app verification (deployed pre-phase-1 code, still connected as the owner)

- `/api/health`: 200 (database connected).
- Login for an unknown email: 401.
- Forgot-password: 200 (generic response).
- `/api/trips` without a token: 401.
- `/api/rates/base/USD`: 200.
- The app's own `activity_logs` rows were written at 05:01, after the migration, so writes work.

### Not done, by instruction

- No password was set on `tripora_runtime`.
- Render credentials and environment variables were not changed.
- The app was not switched to the runtime role.
- Nothing was deployed or committed.

### Recovery, if ever needed

1. Restore from branch `br-bold-lab-b3dfhg6h` or Neon point-in-time restore (6 h history), **or**
2. Run the rollback SQL as the owner, then `DROP ROLE tripora_runtime` after revoking its grants.


---

# P3. Runtime-role transition preparation (2026-11-10)

- **Goal:** make Row-Level Security real for `tripora_runtime` and prove it with that role.
- **Production:** nothing changed in this phase. No credential, environment variable, deployment, commit or destructive operation.
- **Test environment:** local PostgreSQL 18 (same major version as Neon production) built the production way:
  1. the owner runs all migrations;
  2. `backend/db/roles.sql` is applied;
  3. the app and every test connect as a `tripora_runtime` **login**, not the owner and not `SET ROLE`.
- **Rate limits:** a local Redis 7.

## P3.1 Inspection findings

| Area | Finding |
|---|---|
| Connection config | The URI is built from the `DB_*` parts. `sslmode=require` for remote hosts. Flask-SQLAlchemy pool (5 + 10 overflow per worker, `pool_pre_ping`, recycle 300 s). Production `DB_HOST` is Neon's PgBouncer pooler (transaction mode). |
| Transactions / context | Already handled by `services/db_context.py`: identity is re-applied at every transaction start with transaction-local `set_config`. **Gap found:** a context change while a transaction was already open was not applied. The operator CLI hit this under RLS (`new row violates row-level security policy for table "admin_mfa"`). |
| RLS coverage | Only `users`, `trips` and `trip_expenses` had policies. `weather_cache`, `user_refresh_tokens`, `activity_logs` and the four admin tables had none. `trip_expenses` INSERT/UPDATE did not check that the parent trip belongs to the same user. |
| User-owned data | `users`, `trips` (AI itineraries live in `trips.itinerary` / `estimated_cost`), `trip_expenses`, `weather_cache` (by `trip_id`), `user_refresh_tokens`, `activity_logs` (nullable `user_id`, holds IP addresses), `admin_mfa`, `admin_recovery_codes`, `admin_sessions`, `admin_audit_log`. **No "saved destinations" exist**: there is no table and no device storage (only heart icons in the UI). |
| Admin DB operations | Cross-user reads only, through the `app.admin_read` setting after server-side admin authorization. Role changes only through the CLI. |
| Background jobs | No scheduler, worker or thread. The only job-like code is the operator CLI (`services/cli.py`), which uses explicit `db_context.scoped(...)`. |
| Migrations | Run as the owner (pre-deploy). The runtime role cannot run DDL. |

## P3.2 Tables protected by RLS and their policies

Migration `d5e6f7a8b9c0` (backward compatible; downgrade → upgrade verified).

**Settings the policies read**
- `sub` = the verified **access-token** subject (`NULLIF(...,'')::int`).
- `auth_flow` = set only by pre-authentication endpoints and the CLI.
- `admin_read` = set only after admin authorization.

All three are written by the server, transaction-local, and never taken from request input.

| Table | RLS | Policies |
|---|---|---|
| `users` | enabled | SELECT own \| auth_flow \| admin_read · INSERT auth_flow · UPDATE own \| auth_flow · DELETE own |
| `trips` | forced | SELECT own \| admin_read · INSERT/UPDATE/DELETE own (`user_id = sub`) |
| `trip_expenses` | forced | SELECT/DELETE own · INSERT/UPDATE own **and** the parent trip is the caller's (new) |
| `weather_cache` | forced (new) | ALL only where the parent trip is the caller's (`EXISTS` on `trips`, itself under RLS) |
| `user_refresh_tokens` | forced (new) | SELECT/UPDATE auth_flow \| own · INSERT auth_flow · DELETE own |
| `activity_logs` | forced (new) | INSERT only with `user_id IS NOT DISTINCT FROM sub` (no forged attribution) · SELECT admin_read \| own (anonymous rows never visible) · DELETE own |
| `admin_mfa`, `admin_recovery_codes`, `admin_sessions` | forced (new) | ALL auth_flow · DELETE own (account deletion also relies on `ON DELETE CASCADE`) |
| `admin_audit_log` | forced (new) | INSERT auth_flow \| admin_read · SELECT admin_read · no UPDATE/DELETE grant |

**Supporting code changes**
- `services/db_context.py`: every context change, including `scoped()` enter and exit, is re-applied to an already-open transaction. Failed transactions are skipped. The end-of-request reset never raises.
- `app.py`:
  - the RLS subject comes **only from an access-type JWT** (a refresh-type token is ignored);
  - `teardown_request` clears the context so no worker thread carries identity into the next request.
- `ActivityLog` and `AdminAuditLog` insert without `RETURNING` (`implicit_returning=False`). Otherwise RLS would need a writer-side SELECT policy, which would expose anonymous log rows and their IP addresses.
- `/api/admin/page-view` reads the new id before commit (the post-commit reload is an admin-only SELECT).

## P3.3 Runtime-role compatibility

Feature matrix, run through the real app as `tripora_runtime` (all passed):

| Area | Features |
|---|---|
| Accounts | Registration (new, duplicate, unverified re-registration), email verification, login, logout, account deletion with all owned data |
| Sessions | Refresh rotation, replay rejection, logged-out refresh rejected |
| Passwords | Forgot → verify → reset, password change |
| Trips & AI | Trip create, update, regenerate (AI), swap activity (AI), delete |
| Expenses & weather | Expense create, list, update, delete; weather endpoint (cache write/read) |
| Analytics | Anonymous and authenticated page views, `api_request` logging |
| Admin | Admin login + TOTP enrollment, cross-user stats/users, admin audit rows, operator CLI grant/list |

**No feature needs more than the runtime role's grants.** Two incompatibilities were found and fixed in code. Neither was fixed by widening permissions:
- the page-view id was read after commit;
- account deletion could not see the user's own log rows (DELETE needs a SELECT policy).

The same flows were also run as the **owner** with the new code (runbook step 3) and pass.

## P3.4 Tests executed (2026-11-10, all actually run)

| Suite | Result |
|---|---|
| `test_rls_runtime_role.py` (new, as `tripora_runtime` login, PG18) | **25 passed** |
| `test_postgres_runtime_role.py` (PG18) | **13 passed** |
| `test_redis_rate_limiter.py` (Redis 7) | **7 passed** |
| Mutation check: RLS disabled on `trips` | 11 of the 25 RLS tests **failed** as expected; passed again after re-enabling |
| Security suite (SQLite) | **433 passed**, 45 skipped (the opt-in integration suites above) |
| Backend unit | **42 passed** |
| Bandit `-ll` | 0 medium/high |

**What `test_rls_runtime_role.py` covers**
- Role posture: no bypass, no memberships; RLS enabled on all 10 tables.
- Anonymous context: reads nothing and can write nothing.
- Cross-user read/update/delete across 10 statements: 0 rows.
- 11 unauthorized writes rejected: foreign trip, expense on another user's trip, expense attributed to another user, moving an expense or trip to another user, forged activity-log attribution, refresh token / admin session / MFA row / audit row outside the auth flow, weather cache for another user's trip.
- Admin reads only with `admin_read`, and `admin_read` does not grant writes; a user JWT cannot reach admin data.
- Pool leakage: a **single-connection pool** shows no identity after commit, rollback or SQL error; app requests do not leak identity between requests.
- Spoofed identity via query, body, custom headers or a refresh-type JWT is ignored.
- CLI: works with an explicit context and fails closed without one.
- Full feature matrix (P3.3).

Flutter was not re-run in this phase: no Flutter code changed since the 76-test pass.

## P3.5 Connection-pooling results

- Identity lives only in transaction-local settings. Commit, rollback and errors all drop it, verified on a one-connection pool.
- Pooled connections never carry a session-level identity. An empty, previously-set setting is handled by the NULL-safe policies.
- Works with Neon's PgBouncer in transaction mode, because nothing is set at session level.

## P3.6 Remaining privilege requirements / limitations

| Severity | Item |
|---|---|
| MEDIUM | RLS is **not active in production** until runbook steps 1–5 are done; `neondb_owner` has BYPASSRLS. |
| LOW | `users` is ENABLE-only (not FORCE). This is irrelevant on Neon because the owner bypasses RLS anyway, and the runtime role is never the owner. |
| LOW | `auth_flow` grants broad `users` / `user_refresh_tokens` visibility inside pre-authentication endpoints (lookup by email or token is inherent). App code limits what those endpoints return. |
| LOW | The admin context reads all rows of `users`, `trips` and `activity_logs`. It is authorized per request and audited, but not row-scoped. |
| INFO | Cascades (`ON DELETE CASCADE`/`SET NULL`) run as the table owner and bypass RLS by design. Account deletion relies on them for the admin tables. |
| INFO | The tests ran on local PostgreSQL 18. The 2026-11-10 branch rehearsal ran the earlier policies on a copy of production. Migration `d5e6f7a8b9c0` itself has not yet run on Neon. |

## P3.7 Deployment instructions

Exact steps (environment variables, connection-string format, password setup, migration, Render switch, verification, rollback): `docs/DEPLOYMENT.md` → **"Runbook: switching production to `tripora_runtime`"**.

SQL for review:
- `backend/db/upgrade_a9b8c7d6e5f4_to_d5e6f7a8b9c0.sql`
- `backend/db/rollback_d5e6f7a8b9c0_to_a9b8c7d6e5f4.sql`
- `backend/db/rollback_a9b8c7d6e5f4_to_0922f2fc8de9.sql`

**Pending your authorization:**
1. Apply `d5e6f7a8b9c0` to production.
2. Set the runtime password.
3. Commit and deploy.
4. Switch `DB_USER`.

---

# P4. Production runtime-role transition (2026-11-12, authorized by the owner)

## P4.1 Stage 1: migration d5e6f7a8b9c0 applied to production

Pre-checks (all run against Neon project `lively-term-04990062`, branch `production` / `br-sparkling-resonance-b3b58cfb`, database `tripora`):

- Starting version: `alembic_version = a9b8c7d6e5f4` (single row). Migration chain has one head; `d5e6f7a8b9c0` revises `a9b8c7d6e5f4`.
- Server: PostgreSQL 18.6, same major version as the local PG18 runtime-role test suite (P3.4).
- Columns referenced by the policies exist (`user_id` on the six user tables, `trip_id` on `weather_cache` / `trip_expenses`). `trips` has no `trip_id` column, so the unqualified `trip_id` in the `trip_expenses` sub-selects binds to the outer row as intended.
- Existing backup `backup-before-security-migration-2026-11-10` (`br-bold-lab-b3dfhg6h`) is present and untouched. It predates `a9b8c7d6e5f4`.
- An additional backup was created at the exact pre-migration state: `backup-before-rls-d5e6f7a8b9c0-2026-11-12` (`br-flat-wildflower-b37inoex`, parent LSN `0/4DBA150`, no compute).
- Upgrade SQL was rendered from the migration module itself; rollback SQL in `backend/db/rollback_d5e6f7a8b9c0_to_a9b8c7d6e5f4.sql` matches `downgrade()`.

Execution: all 50 upgrade statements plus the `alembic_version` update ran in a single transaction, preceded by a guard that aborts unless the version is exactly `a9b8c7d6e5f4`. It committed without error.

Post-checks:

- `alembic_version = d5e6f7a8b9c0`.
- RLS enabled on all 10 application tables; FORCE on 9. `users` is ENABLE without FORCE (unchanged from a9b8c7d6e5f4). FORCE only affects the table owner, which already has BYPASSRLS, so this has no effect on `tripora_runtime`.
- 31 policies total: users 6, trips 5, trip_expenses 4, user_refresh_tokens 4, activity_logs 3, admin_mfa 2, admin_recovery_codes 2, admin_sessions 2, admin_audit_log 2, weather_cache 1.
- `tripora_runtime` grants unchanged (no privilege added). `admin_audit_log` stays INSERT/SELECT only.
- Row counts intact (users 17, trips 25, trip_expenses 5, activity_logs 2414).
- The deployed app still connects as `neondb_owner` (BYPASSRLS), so it is unaffected.

Rollback, if needed: run `backend/db/rollback_d5e6f7a8b9c0_to_a9b8c7d6e5f4.sql` as the owner (one transaction). Last resort: restore from `br-flat-wildflower-b37inoex`.

## P4.2 Authentication exception: `app.auth_flow` user lookups

What it is. Before a JWT exists, login, registration, social login, refresh, logout and password reset must find a `users` row by e-mail or by token. RLS cannot scope those reads to "own row" because there is no subject yet. The app therefore sets the transaction-local setting `app.auth_flow = 'on'` for the endpoints in `AUTH_FLOW_ENDPOINTS` (`backend/app.py`) and in the admin CLI. While it is on, these policies apply:

- `users_auth_flow_select`: SELECT on every row (also with `app.admin_read`).
- `users_auth_flow_update`: UPDATE on every row.
- `users_auth_flow_insert`: INSERT.
- `refresh_tokens_select` / `refresh_tokens_update` / `refresh_tokens_insert`: every refresh-token row.
- `admin_mfa_auth_flow`, `admin_recovery_codes_auth_flow`, `admin_sessions_auth_flow`: every row.

Why it is not client-controllable. The setting comes only from `request.endpoint` matched against a fixed server-side set, applied with `set_config(..., true)` per transaction, and reset at the start of each request (`services/db_context.py`). No header, body field or JWT claim can turn it on.

Residual risk. Inside those endpoints the database no longer limits which user rows are reachable. A logic bug or injection in any of them could read or modify any account. The limit is application code only. Severity stays LOW (P3.6) but it is the widest remaining gap in the RLS model.

Assessment: it can be restricted further. Options, in order of effort:

1. Trim the endpoint list (small, low risk). Several entries run after a JWT or admin session exists and may not need table-wide reads: `auth.logout`, `auth.update_current_user`, `admin_auth.admin_me`, `admin_auth.admin_logout`, `admin_auth.admin_regenerate_recovery_codes`. Each needs a per-endpoint check of which queries run before the subject is known. `update_current_user` only needs a cross-row read for the e-mail uniqueness check; option 2 covers that.
2. SECURITY DEFINER helpers for cross-row checks (small). For example `tripora_email_taken(text) RETURNS boolean`, owned by `neondb_owner`, `SET search_path = public`, EXECUTE granted only to `tripora_runtime`. The caller learns one boolean, not the rows.
3. Key-scoped lookup instead of a blanket flag (medium). Replace `app.auth_flow` on `users` with narrower settings that carry the lookup key, set by the server from the validated request: `app.auth_email` (policy: `lower(email) = lower(current_setting('app.auth_email', true))`) for login, register and forgot-password; `app.auth_user_id`, set by the server after it validates a refresh token or reset code, for the follow-up update. Refresh-token policies can be keyed on `token_hash = current_setting('app.auth_token_hash', true)`. Result: a bug in an auth endpoint exposes at most the row matching the key being authenticated.
4. SECURITY DEFINER login functions (largest). Move lookup and credential update into functions such as `tripora_auth_lookup(email)` returning only id, password hash, status and token version, and drop the `users_auth_flow_*` policies. Requires refactoring ORM queries in `routes/auth.py` and `services/social_auth_service.py`.

Recommendation: do 1 and 2 first, then 3 for `users` and `user_refresh_tokens`, after the runtime-role switch is stable. Neither should be bundled into the current transition. Each needs its own migration, tests on a branch (`security/tests/test_rls_runtime_role.py` pattern), and owner approval.

---

# P5. Backend-only administration and security review (2026-11-12)

Scope decision by the owner: administration stays on the backend; the Flutter admin UI is postponed. Backend admin security is unchanged.

## P5.1 Flutter admin UI removed

- Deleted: `lib/screens/admin/admin_login_screen.dart`, `lib/screens/admin/admin_screen.dart`, `lib/services/admin_service.dart`, `test/admin_login_screen_test.dart`, and the 30 `admin.*` strings in `lib/core/l10n/app_localizations.dart`.
- `lib/routes/app_routes.dart`: `/admin` and `/admin/login` removed. New `AppRoutes.unknownRoute` (wired as `onUnknownRoute` in `main.dart`) opens Home for any unknown path, so old bookmarks do not crash navigation.
- New `lib/core/security/legacy_storage_cleanup.dart`, run at every app start from `main.dart`: deletes the `admin_token` key that the pre-hardening admin UI stored in SharedPreferences (browser `localStorage` on the web). Idempotent; never throws; other preferences are untouched.
- Kept: `services/activity_service.dart` posts to the public `/api/admin/page-view` beacon (anonymous user analytics, not an admin feature).
- No admin-only package dependencies existed, so `pubspec.yaml` is unchanged.

Historical sections above that mention these files describe the state at the time.

## P5.2 Backend administration preserved (unchanged)

Admin API (`routes/admin.py`, `routes/admin_auth.py`), password + TOTP sign-in, enrollment, single-use recovery codes, server-side `role` check, `flask admin grant|list|reset-mfa|revoke|revoke-sessions`, `admin_audit_log`, the `app.admin_read` RLS context, and the legacy-token fallback (still on by default; still audited as `legacy_token_access`). First-admin provisioning without a UI is documented in `docs/DEPLOYMENT.md` §e.

New guard test `security/tests/test_admin_backend_only.py` walks the live URL map: every `/api/admin/*` route other than the beacon, `login-status`, the sign-in steps and the idempotent logout returns 401, with no data in the body, for no credential, a normal user's JWT, and a forged bearer.

## P5.3 Security review findings (not fixed in this phase unless stated)

| # | Area | Severity | Finding | Exploitability | Proposed fix |
|---|---|---|---|---|---|
| F1 | Admin auth | Medium | Shared `ADMIN_API_TOKEN` fallback is on by default: one static secret, no MFA, no expiry, no per-person attribution. Old browsers may still hold a copy in `localStorage` until they open the new app once. | Anyone holding the token reads all users, trips and logs. Limited to 60 req / 10 min and audited. | Provision an MFA admin (DEPLOYMENT.md §e), verify, then `ADMIN_LEGACY_TOKEN_ENABLED=false` and remove the variable. Optionally rotate the token now, which invalidates any copy left in browsers. |
| F2 | Session / XSS | Medium | CSP is report-only. On the web, `flutter_secure_storage` encrypts with a key kept in the same origin's storage, so a script injected into the origin can read the 30-day refresh token. | Requires an XSS in the Flutter web origin or a compromised third-party script. | Enforce the CSP after a clean report period. Longer term: refresh token in an `HttpOnly; Secure; SameSite=Strict` cookie scoped to `/api/auth/refresh`. |
| F3 | Abuse | Medium | Login throttling is per client IP (10 / 10 min); there is no per-account budget. | Distributed credential stuffing across many IPs is not slowed per account. | Add a second bucket keyed on the normalized e-mail hash (e.g. 20 / hour), with a generic response so it does not reveal whether the account exists. |
| F4 | Abuse | Medium (until Redis) | Without `REDIS_URL`, limits are per Gunicorn worker and reset on restart. | Effective budget is multiplied by the worker count and resets on deploys. | Set `REDIS_URL` (Render Key Value). Code already supports it. |
| F5 | RLS | Low | `app.auth_flow` grants table-wide `users` / refresh-token visibility inside 22 endpoints (P4.2). | Needs a separate bug in one of those endpoints. | P4.2 options 1-3. |
| F6 | Config | Low | A `JWT_SECRET_KEY` shorter than 32 characters only logs a warning at start-up. | A weak secret could be brute-forced offline from any issued token. | Refuse to start when `RENDER=true` and the secret is short, after confirming the production value is long enough. |
| F7 | Logging | Low | `activity_logs` (IP, user agent; 2414 rows in prod) and `admin_audit_log` have no retention policy. | Privacy / GDPR exposure, not an access-control issue. | Scheduled purge (e.g. 90 days for activity, 1 year for audit) via a `flask` CLI command. |
| F8 | DB privileges | Info | `tripora_runtime` inherits `TEMP` on the database from PUBLIC. | No data access; temp tables are session-private. | `REVOKE TEMP ON DATABASE tripora FROM PUBLIC` in a future migration. |
| F9 | Error handling | Info | Some routes return `str(error)`, but only for the app's own `InvalidIdentityError` / validation `ValueError` messages. | No stack traces or SQL reach the client. | Map these to fixed messages when the routes are next touched. |

Checked and found sound: parameterized SQL everywhere (no string-built SQL in routes, services or models); Werkzeug scrypt password hashing; short-lived access tokens with rotating refresh tokens and reuse detection; `token_version` revocation; e-mail-enumeration-safe register and reset responses; reset-code attempt lockout; RLS on all 10 tables; security headers (HSTS, `nosniff`, `X-Frame-Options: DENY`, Referrer-Policy); no file-upload endpoints; no secrets in the repository; Flutter release builds strip debug logging.

## P5.4 Tests (2026-11-12, local, all run)

- Security suite: 437 passed, 45 skipped (the skipped ones are the PG / Redis suites below).
- Backend unit: 42 passed (2 deselected, integration).
- PG 18 runtime role + RLS + Redis: 45 passed.
- `flutter analyze`: no issues. `flutter test`: 76 passed.

---

# P6. Production-readiness audit (2026-11-12, verification and documentation only)

No production SQL, no Render/Neon changes, no commits. Production facts below come from the read-only queries recorded in P4 and the stage-4 checks earlier the same day.

## P6.1 Repository

- Branch `security-hardening` = `main` = `origin/main` = `c543a43`. All work is uncommitted: 48 modified, 44 untracked, 3 deleted (the Flutter admin files).
- No tracked `.env`, key or credential files. `.env` is ignored in the root, `backend/` and `frontend/`.
- A secret scan of the full diff plus untracked files finds only local test credentials (`local-runtime-test-only`, `tester:s3cr3t@db.example.com`).
- Dependency changes are deliberate:
  - security patch bumps: `certifi`, `pyasn1`, `PyJWT`, `urllib3`, `Werkzeug`;
  - new `redis` (rate limiter) and a new `requirements-dev.txt`;
  - Flutter adds `flutter_secure_storage`.
- `pip check` is clean. `pip-audit` is clean (run with `--disable-pip --no-deps` on the fully pinned file, after the default mode failed to build its temporary environment).
- There is one migration head, `d5e6f7a8b9c0`, which matches production.
- Documentation fixes in this phase:
  - `backend/.env.example` gained `RESEND_FROM_EMAIL`, `RESEND_FROM_NAME` and a `TRIPORA_ENV` note;
  - the stale `ADMIN_API_TOKEN` comment in `config/settings.py` is corrected;
  - the rollback section of `docs/DEPLOYMENT.md` now lists both backup branches and the code-rollback rule.

## P6.2 Production environment checklist (Render web service)

"Before" means the value must be correct before the first deploy of this branch. "Later" means it is set during a later step.

| Variable | Required | Default | If missing / wrong | When |
|---|---|---|---|---|
| `DB_USER`, `DB_PASSWORD`, `DB_HOST`, `DB_PORT`, `DB_NAME` | Yes | none | App refuses to start. | Before: unchanged owner values. Later (step F): runtime role. |
| `DB_SSLMODE` | No | `require` for non-local hosts | Unset is safe. A weaker value disables TLS protection. | Unchanged |
| `DB_MIGRATION_USER`, `DB_MIGRATION_PASSWORD` | Only for the pre-deploy command | none | Pre-deploy fails and blocks the deploy. | Later (step F), together with the pre-deploy command |
| `JWT_SECRET_KEY` | Yes | none | Start-up fails. Under 32 characters only logs a warning (F6). Changing it logs every user out. | Before: keep the current value; confirm it has 32+ characters |
| `JWT_ACCESS_TOKEN_MINUTES`, `REFRESH_TOKEN_DAYS` | No | 15, 30 | Defaults are the intended values. | Unchanged |
| `CORS_ORIGINS` | Should be set | localhost and placeholder origins | The web app cannot call the API, or local origins stay allowed. Low risk: auth uses bearer tokens, not cookies. | Before: confirm it lists the Vercel origin |
| `TRUSTED_PROXY_HOPS` | No | 1 on Render (`RENDER=true`) | A wrong value lets clients spoof their IP into the limiter and logs. | Unchanged (leave unset) |
| `MAIL_HOST`, `MAIL_USER`, `MAIL_PASSWORD` (+ `MAIL_PORT`, `MAIL_USE_TLS`, `MAIL_FROM`, `MAIL_FROM_NAME`) | One provider is required | port 465, SSL | No verification or reset e-mail, so new users cannot verify and cannot use trips. The API still returns a generic success; only the logs show the failure. | Before: verify delivery |
| `RESEND_API_KEY`, `RESEND_FROM_EMAIL`, `RESEND_FROM_NAME` | Alternative to SMTP | sender `onboarding@resend.dev` | With the default sender, only the Resend account owner receives mail. | Before, if Resend is used |
| `TRIPORA_ENV` | No | production | `development`/`test` makes e-mail report success without sending. | Before: confirm it is unset |
| `REDIS_URL` | Recommended | none (in-memory) | Limits are per worker and reset on deploy (F4); an error is logged on Render. | Before if possible, otherwise soon after |
| `RATE_LIMIT_FAILURE_MODE` | No | `fallback` | `closed` returns 503 on auth/admin/AI during a Redis outage. | Unchanged |
| `RATE_LIMIT_ENABLED` | No | `true` | `false` disables all abuse protection. | Before: confirm it is not `false` |
| `MFA_ENCRYPTION_KEY` | For admin MFA | none | Admin MFA endpoints return 503; the legacy token still works. Losing the key forces every admin to re-enroll. | Before step H (can be set before the deploy) |
| `ADMIN_SESSION_IDLE_MINUTES`, `ADMIN_SESSION_MAX_HOURS` | No | 30, 8 | Defaults are the intended values. | Unchanged |
| `ADMIN_API_TOKEN` | Transitional | none (shared-token path off) | Unset before an MFA admin exists = no admin access at all. | Keep until step I, then delete |
| `ADMIN_LEGACY_TOKEN_ENABLED` | No | `true` | `false` before an MFA admin exists = no admin access. | Step I only |
| `REQUEST_LOGGING_ENABLED`, `LOG_LEVEL` | No | `true`, `INFO` | `DEBUG` logs more detail. | Unchanged |
| `GEMINI_API_KEY`, `DUFFEL_API_TOKEN`, `TRAVELPAYOUTS_API_KEY`, `GOOGLE_CLIENT_ID_*`, `APPLE_CLIENT_ID` | Feature keys | none | The feature fails closed. | Unchanged |
| `FLASK_DEBUG` | No | `0` | Ignored under Gunicorn. | Unchanged |

## P6.3 Runtime role

The grants that `backend/db/roles.sql` produces on local PG 18 match the production read-only snapshot exactly:
- DML (read, insert, update, delete) on the 10 application tables;
- `admin_audit_log`: INSERT and SELECT only;
- nothing on `alembic_version`;
- sequences: USAGE and SELECT;
- no CREATE on the schema;
- connection limit 40, `statement_timeout=30s`, `idle_in_transaction_session_timeout=60s`;
- no superuser, createdb, createrole, replication or bypassrls attribute, and no role memberships.

Other checks:
- **Connection pool:** 2 Gunicorn sync workers × SQLAlchemy's default pool (5 + 10 overflow) = at most 30 connections, under the limit of 40.
- **Credentials:** migrations need the owner (DDL, `alembic_version`), so runtime and migration credentials stay separate. The web process uses `DB_USER`/`DB_PASSWORD` = runtime role; the pre-deploy command uses `DB_MIGRATION_*`.
- **Gap for future tables:** tables the owner creates later automatically grant DML to the runtime role, but RLS is not enabled automatically. `test_every_user_table_has_rls_enabled` checks only a fixed list of tables. Recommended: a test that fails when any table readable by the runtime role (except `alembic_version`) lacks RLS.

How to prove production uses the runtime role after the switch. All checks are read-only, run as the owner in the Neon SQL editor:
1. Run:
   ```
   SELECT usename, application_name, state, count(*)
   FROM pg_stat_activity WHERE datname = 'tripora' GROUP BY 1,2,3;
   ```
   App connections should show `tripora_runtime`. `neondb_owner` should appear only for your own editor session.
2. Repeat the query after a sign-in and a trip load in the app, so the rows come from live traffic.
3. Check the Render logs: there should be no `InsufficientPrivilege`, `permission denied` or `row-level security` errors.
4. Functional proof of RLS: signed in as user A, open a trip ID that belongs to user B. Expect 404. Admin stats under MFA should still show all users (admin-read policy).

## P6.4 F1–F9 status

All nine findings are still open. None was fixed in this phase.

| # | Status | Practical risk now | Depends on | Blocks first deploy? |
|---|---|---|---|---|
| F1 legacy admin token | Open | Anyone with the token can read all users, trips and logs. | `MFA_ENCRYPTION_KEY`, first MFA admin | No. Retire it in step I. |
| F2 report-only CSP / web token storage | Open | An XSS could steal 30-day refresh tokens. | A week of clean CSP reports | No |
| F3 no per-account login limit | Open | Distributed credential stuffing is not slowed per account. | Code change + tests | No |
| F4 no Redis | Open (config) | Limits multiply by 2 workers and reset on each deploy. | Render Key Value instance | No, but set it with or right after the deploy |
| F5 broad `auth_flow` | Open | Needs a separate bug in an auth endpoint. | Runtime-role cutover first | No |
| F6 short JWT secret only warns | Open | Matters only if the production secret really is short. | Owner confirms the length | No, but confirm the length before the deploy |
| F7 no log retention | Open | Privacy / compliance. | CLI command + schedule | No |
| F8 `TEMP` from PUBLIC | Open | Negligible. | Migration | No |
| F9 `str(error)` messages | Open | Negligible (app-defined messages only). | None | No |

Recommended order after deployment: F4, then the cutover (step F), then F1 (steps H and I), then F6, F3, F2, F5, F7, and finally F8/F9.

## P6.5 Deployment sequence

**A. Pre-deployment (owner, Render)**
- Confirm e-mail delivery locally, using the `send_email` one-liner from the stage-4 notes.
- Confirm `TRIPORA_ENV` is unset, `RATE_LIMIT_ENABLED` is not `false`, `CORS_ORIGINS` is set and `JWT_SECRET_KEY` has 32+ characters.
- Add `MFA_ENCRYPTION_KEY` and `REDIS_URL` if they are ready.
- Do not change `DB_*`. Do not set a pre-deploy command yet.

**B. Commit and merge**
- Commit on `security-hardening` and review the diff.
- Fast-forward `main` and push. Render deploys on push.

**C. Backend**
- Watch the deploy log.
- `GET /api/health` should return 200 with the database connected.
- Expect no start-up errors, except a Redis warning if `REDIS_URL` is still unset.

**D. Frontend**
- Confirm that Vercel deploys from `main`.
- Existing users sign in again once: their old tokens last 15 minutes and the old client has no refresh token.
- Opening the new app deletes any stored `admin_token`.

**E. Authentication tests**
1. Sign in with an existing account.
2. Request a password-reset e-mail for an account you control. Do not complete the reset.
3. Optional: sign up with a plus-address, verify it, then delete the account in the app.
4. Use trips, expenses and weather.
5. Log out and back in.
6. Wait 15 minutes, then confirm the session refreshes silently.

**F. Runtime-role cutover** (needs separate authorization)
- Follow runbook steps 4–5 in `docs/DEPLOYMENT.md`:
  - remove `flask db upgrade` from Render's Build and Start commands (corrected 2026-11-12, see P7): under `tripora_runtime` it cannot read `alembic_version`;
  - `DB_MIGRATION_*` = owner, and the Pre-Deploy command is the only place migrations run;
  - `DB_USER`/`DB_PASSWORD` = runtime role.

**G. RLS verification**
- Run the four checks in §P6.3.

**H. Admin MFA provisioning**
- Follow `docs/DEPLOYMENT.md` §e, steps 1–6.

**I. Legacy-token retirement**
1. Only after H is verified, set `ADMIN_LEGACY_TOKEN_ENABLED=false`.
2. Confirm the old token now gets 401.
3. Delete `ADMIN_API_TOKEN`.

**J. Rollback**
- After F: first set `DB_USER`/`DB_PASSWORD` back to the owner.
- Code (corrected 2026-11-12, see P7): roll back only to a commit that contains all migration files up to the production revision. Any older commit fails to deploy with `Can't locate revision identified by 'd5e6f7a8b9c0'` whenever Render runs `flask db upgrade`. No schema change is needed for such a rollback. Vercel "Instant Rollback" is unaffected.
- Schema: `backend/db/rollback_d5e6f7a8b9c0_to_a9b8c7d6e5f4.sql`.
- Data: the backup branches or Neon point-in-time restore.

## P6.6 Tests (2026-11-12, after this phase's edits)

- Security suite: 437 passed, 45 skipped.
- Backend unit: 42 passed.
- PG 18 runtime role + RLS + Redis: 45 passed.
- Bandit: 0 medium or higher. pip-audit: clean.
- Flutter: unchanged since P5 (analyze clean, 76 passed).

---

# P7. Render deploy failure: "Can't locate revision identified by 'd5e6f7a8b9c0'" (2026-11-12)

- Cause: production `alembic_version` is `d5e6f7a8b9c0`, but the five migrations `b7c1d2e3f4a5`, `c8d2e3f4a5b6`, `e1f2a3b4c5d6`, `a9b8c7d6e5f4` and `d5e6f7a8b9c0` were never committed. Every commit up to `c543a43` ends at `0922f2fc8de9`. A Render command (not in the repo; the documented build command is only `pip install`) runs `flask db upgrade`, which cannot resolve the database's revision.
- Reproduced locally: `c543a43` as committed fails with the same error against a PG 18 database at `d5e6f7a8b9c0`; with the five files added, `flask db upgrade` exits 0 as a no-op and `db current` reports `d5e6f7a8b9c0 (head)`.
- Commits after `8b6974f` (`1b104bf`, `c543a43`) change only `frontend/`; `backend/` is byte-identical. This explains why Render still runs `8b6974f`.
- No production database change is needed. Fix: commit the five migration files.
- Documentation corrected: rollback rules and the runtime-role cutover (Build/Start commands must not run migrations) in `docs/DEPLOYMENT.md`, and P6.5 F and J above.

---

# P8. Bot protection: Cloudflare Turnstile + honeypot (2026-11-12, uncommitted)

Protected endpoints: `POST /api/auth/register` and `POST /api/auth/forgot-password`. Login, verification, password reset completion, refresh tokens, admin MFA, RLS context and e-mail delivery are unchanged.

## P8.1 Backend

- `services/turnstile.py`: Siteverify client.
  - Checks `success`, the expected `action` (`register` / `forgot_password`) and, when `TURNSTILE_ALLOWED_HOSTNAMES` is set, the `hostname`.
  - Maps Cloudflare's error codes: `timeout-or-duplicate` covers both expired and reused tokens.
  - Rejects missing, blank, non-string and oversized (over 2048 characters) tokens locally, without a network call.
  - Timeout 5 s (connect 3 s), no redirects.
  - Never raises. Network errors, non-200 answers, bad JSON and secret errors become `unavailable`.
  - Logs only the reason, the action and Cloudflare's error-code names. Never the token, secret, IP or body.
- **Enabled resolution:**
  - explicit `TURNSTILE_ENABLED` wins;
  - when unset, protection is on unless `TRIPORA_ENV` is development or test;
  - start-up logs an error when it is on without keys, and a warning when it is turned off on Render.
- `services/bot_protection.py`: the reusable honeypot (`website`) plus the Turnstile check.
  - Whitespace-only honeypot values are ignored; non-string values count as filled.
  - Failure responses: 400 `turnstile_failed`, or 503 `turnstile_unavailable`.
- `routes/auth.py`:
  - **register:** the honeypot is checked first and answered with the normal generic 201, with no side effects. Turnstile is checked after field validation, so a typo does not burn the token, and before any database access.
  - **forgot-password:** both checks run before the account lookup. The honeypot gets the generic 200. A challenge failure does not depend on the address, so there is no account enumeration.
  - `turnstileToken` and `website` are redacted from debug logs.
- `routes/turnstile.py`:
  - `GET /api/turnstile/config` returns the enabled flag and the public site key only.
  - `GET /api/turnstile/challenge` is the Android challenge page:
    - a per-request nonce CSP (`default-src 'none'`, scripts and frames only from itself and `challenges.cloudflare.com`, `frame-ancestors 'none'`);
    - `no-store`;
    - the action and theme are validated, and config values are JSON-escaped.
- `app.py`:
  - registers the blueprint and logs the start-up status;
  - the global CSP hook now keeps a CSP a route has already set. Every other route is unchanged, and a test checks this.
- `config/settings.py`: read-tier rate-limit buckets for the two new endpoints. The existing register and forgot-password limits are unchanged and still run before the bot checks.

## P8.2 Flutter

All new files are under `lib/core/security/turnstile/`.
- **Shared:**
  - `turnstile_config.dart` loads `/api/turnstile/config` once (retries after a failure) and accepts only an `/api/turnstile/` challenge path.
  - `turnstile_event.dart` is a strict message parser.
  - `turnstile_controller.dart` tracks status and the single-use token, expires the token after 280 s, and holds the honeypot reader.
  - `turnstile_field.dart` is the form block: loading, disabled, error and retry states.
- **Web** (`turnstile_view_web.dart`):
  - loads Cloudflare's script once, in explicit render mode, and renders it in an `HtmlElementView` (flexible size, light or dark theme);
  - handles the callback, expiry, timeout and error callbacks, plus reset and remove;
  - the same platform view holds the honeypot: a real `<input name="website">` hidden by the static `.tp-website` rule in `web/index.html` (off-screen, not `display:none`), `aria-hidden`, `tabindex=-1`, `autocomplete=off`.
- **Android/iOS** (`turnstile_view_io.dart`, `turnstile_challenge_page.dart`, `turnstile_challenge_policy.dart`):
  - a "Confirm you are human" tile opens a full-screen WebView on the backend challenge page;
  - JavaScript is on; DOM storage is the `webview_flutter_android` default (on); file and content access are off;
  - only the challenge page may load as the top-level page, and Cloudflare's iframe is limited by the page CSP;
  - the token comes back through the `TriporaTurnstile` JavaScript channel and is validated before use.
  - Desktop platforms without a WebView report "unavailable".
- **Native honeypot:** native apps have no DOM a bot could fill, so the honeypot is always sent empty there. Turnstile plus the backend checks are the control on those platforms.
- **Screens:** both screens block submit until a token is available, send `turnstileToken` and `website`, and reset the widget after every attempt. On the forgot-password screen the widget appears on the "request code" step only.
- **Other files:**
  - `services/auth_service.dart`: optional `turnstileToken` and `honeypot` parameters;
  - `app_localizations.dart`: 11 `turnstile.*` strings in 6 languages;
  - `vercel.json`: report-only CSP adds `https://challenges.cloudflare.com` to `script-src`, `frame-src` (previously `'none'`) and `connect-src`.
- **New dependencies:** `webview_flutter` 4.14.1 and `webview_flutter_android` 4.14.1, both published by flutter.dev. Turnstile has no native SDK; a WebView is Cloudflare's supported route on mobile.

## P8.3 Configuration (owner actions)

See `docs/DEPLOYMENT.md` §g:
- create a Managed widget in Cloudflare with both hostnames;
- on Render, set `TURNSTILE_SECRET_KEY`, `TURNSTILE_SITE_KEY` and `TURNSTILE_ALLOWED_HOSTNAMES`.

**Deploying this code without those keys turns sign-up and password reset into 503 responses.** That is the intended fail-closed behaviour, but it makes the keys a deployment prerequisite.

## P8.4 Tests (2026-11-12, local; Siteverify always mocked, never called)

- `security/tests/test_bot_protection.py`: 61 tests, all passed. Coverage:
  - tokens: valid, invalid, missing, blank or non-string, oversized, expired, reused, wrong action, wrong hostname;
  - failures: connect and read timeouts, connection error, Cloudflare 5xx, unparseable body, enabled without a secret;
  - field errors do not burn the token;
  - honeypot: filled, non-string, empty or whitespace, enforced with Turnstile off;
  - forgot-password: generic responses, no reset code on failure, no account enumeration;
  - rate limit runs first, and failed challenges and honeypot requests consume the budget;
  - enabled resolution, the strict timeout, the real request settings (no network), no tokens or secret in logs, log redaction;
  - config endpoint, challenge-page CSP, nonce, escaping and injection;
  - other routes keep the default CSP.
- `security/tests/conftest.py`: the general suite pins Turnstile off, and any test that would reach Cloudflare fails at teardown.
- Results:
  - full security suite: 498 passed, 45 skipped (the PG and Redis suites, run separately);
  - PG 18 runtime role + RLS + Redis: 45 passed;
  - Bandit: 0 medium or higher (new LOW B105 flags are constant names, not secrets).
- `frontend/test/turnstile_test.dart`: 26 tests, all passed. Coverage:
  - message parser;
  - Android navigation policy and challenge URL;
  - controller states, expiry and reset;
  - config parsing, caching and retry;
  - `AuthService` request fields;
  - the native `TurnstileField` via an injected launcher: disabled, token, cancel, malformed token, unsupported platform, config error and retry, missing site key;
  - `index.html` honeypot CSS and `vercel.json` CSP.
- Flutter: `flutter analyze` is clean, `flutter test` passes 102, and `flutter build web --release` compiles.
- `frontend/test/turnstile_web_test.dart` is a browser test of the web widget, against a stubbed `window.turnstile`.
  - **First attempt:** it did not run. `flutter test --platform chrome` never connected; even a trivial one-assertion test failed with "Connection closed before test suite loaded".
- **Browser test (P8.2, 2026-11-12): 5/5 passed in headless Chrome 157.** The suite also passed with three random test orders (seeds 1, 42 and 9001).
  - **Root cause of the hang:** a Flutter 3.44.8 tool bug on Windows. The test server's CanvasKit handler (`flutter_tools/lib/src/test/flutter_web_platform.dart`, `_localCanvasKitHandler`) checks `path.fromUri(url).startsWith('canvaskit/')`. On Windows that path uses backslashes, so every `/canvaskit/...` request returns 404. The test page hard-codes `canvasKitBaseUrl: "/canvaskit/"`, so the engine never starts and the suite never reports back. This hits every browser test on Windows. Chrome, network, firewall, ports and the test code were not the cause; the DevTools console showed the 404s.
  - **Workaround, without changing the Flutter SDK:** on a 404 the test server falls through to its handler that serves `frontend/test/`. Before running, copy the SDK's own files from `C:\flutter\bin\cache\flutter_web_sdk\canvaskit\` (`canvaskit.js`, `canvaskit.wasm` and `chromium\`) into `frontend/test/canvaskit/`. Delete that copy afterwards; never commit it.
  - **Test defect fixed (test-only change):**
    - Widget tests do not hand frames to the web engine, so `HtmlElementView` views were never created and `turnstile.render` was never called.
    - The test now installs `EnginePlatformViews`, the same technique as Flutter's own `HtmlElementView` tests: `ui_web.debugOverridePlatformViewRegistry` plus a mock `platform_views` channel. It runs the app's real view factory and attaches the element to the page.
    - All assertions are unchanged. No app code changed.
  - **Mutation check:** changing the `action` sent to Turnstile, or the honeypot's `tabIndex`, makes the suite fail. The app file was restored byte-for-byte.
- `flutter build apk --debug` was started to compile-check the Android WebView plugin but was stopped by the host because the system was low on memory.
- **Android build retried (2026-11-12): succeeded.**
  - **Cause of the earlier failure:** `android/gradle.properties` asks for `-Xmx8G -XX:MaxMetaspaceSize=4G` on a 15.7 GB machine that had about 3 GB of commit charge free. An orphaned Gradle daemon and Kotlin daemon from the killed build also held about 3.2 GB.
  - **Fix for this build (no file changed):**
    - stopped the orphaned daemons;
    - built with `GRADLE_OPTS='-Dorg.gradle.jvmargs="-Xmx2g -XX:MaxMetaspaceSize=768m -XX:ReservedCodeCacheSize=256m" -Dorg.gradle.daemon=false -Dorg.gradle.workers.max=2 -Dorg.gradle.parallel=false'`;
    - passed `--android-project-arg=kotlin.compiler.execution.strategy=in-process`.
  - **Result:** `build/app/outputs/flutter-apk/app-debug.apk` in 121 s, with `WebViewFlutterPlugin` registered.
  - **Still not verified:** running on a physical device. The manual procedure is in the P8 Android verification notes.

## P8.3 Real-browser verification and production readiness (2026-11-12)

**Setup (local only):**
- Flutter web release build pointed at a local Flask backend.
- A scratch database `tripora_p83` in the local Postgres test container, since dropped.
- The local `backend/.env` points at **Neon production**. Every run overrode the `DB_*` and mail variables in the process environment, so `.env` was not used for them.
- Cloudflare's **real** `api.js` and widget, with Cloudflare's published dummy keys. A real widget could not be created (owner action).
- Headless Chrome 157, driven over the DevTools protocol.

**Verified:**
- **Widget:** the real Cloudflare widget loads and renders on sign-up and on forgot-password.
- **Token hand-off:** the token reaches Flutter and is sent as `turnstileToken`, with `website: ""`.
- **Backend calls Cloudflare:** it called the real Siteverify endpoint.
- **Action check:** dummy keys return no `action`, so the backend rejected them with `action_mismatch`, for both `register` and `forgot_password`. This confirms the strict action check against real Cloudflare responses.
- **Spent tokens:** Cloudflare's "token spent" test secret (`3x…AA`) returns `timeout-or-duplicate`. The backend mapped it to `expired_or_reused` and answered 400.
- **Missing token:** 400, with no network call.
- **Honeypot:**
  - It is off-screen (`left: -10000px`, 1×1 px, `overflow: hidden`) through the static `.tp-website` rule in `index.html`, with `tabIndex = -1` and `aria-hidden`.
  - 40 Tab presses gave it no focus events.
  - When filled, the backend answers the generic 201 or 200, makes no Siteverify call and creates no user.
- **Re-verification** (forced-interactive key `3x…FF`):
  - submitting without verifying is blocked client-side, with no request sent;
  - after a submit, `turnstile.reset` runs once and the widget asks again;
  - a second submit without re-verifying is blocked with no request.
- **Android challenge page:** it renders the real widget and issues a token under its nonce CSP, with no CSP violations. It also sends `no-store`, `X-Frame-Options: DENY` and `frame-ancestors 'none'`.
- **Logs:** they contained no token, secret or password.

**Not verified (needs a real development widget whose hostnames include `localhost`):**
- acceptance of a valid token with the exact `register` / `forgot_password` action;
- the hostname check against a real hostname;
- expiry and reuse of **real** tokens. Only Cloudflare's simulated `timeout-or-duplicate` was tested.

**Docs:**
- `docs/DEPLOYMENT.md` §g now has:
  - the exact hostnames and the Render variable table;
  - the coordinated rollout (`TURNSTILE_ENABLED=false` during the transition, then enforcement) and a post-enforcement smoke test;
  - the rollback;
  - the Resend testing-sender limitation (it blocks public sign-up verification **and** password-reset e-mails);
  - the need for a separate development widget for local tests.
- `backend/.env.example`: the dummy-key behaviour is now confirmed.

## P8.4 Finalization: local safety, Cloudflare rejection paths, web retry fix (2026-11-12)

**Local database safety (new):** `backend/config/local_safety.py`, enabled with `TRIPORA_LOCAL_ONLY=1`.
- **Never loads `backend/.env`.** That file points at production. Configuration comes from the process environment plus `backend/.env.local` (gitignored; template `backend/.env.local.example`, kept trackable via a `.gitignore` exception).
- **Refuses any non-loopback `DB_HOST`, Neon included,** while the configuration is built, before an engine or connection exists. Migrations use the same `DB_HOST`, so they are covered too.
- **Refuses to run under the `flask` CLI unless `FLASK_SKIP_DOTENV=1`.**
  - Found during this stage: the Flask CLI auto-loads `.env` from the working directory before the app is imported.
  - The guard caught it: the run was refused because `DB_HOST` was Neon.
  - The earlier P8.3 runs, which used `flask run`, therefore also had the non-database `.env` values (Gemini key, mail) in their process. Their database and mail settings were explicitly overridden.
- **Forces e-mail simulation:** nothing is ever sent.
- **No effect without the flag,** so deployed environments behave exactly as before.
- **Start script:** `backend/scripts/run_local.sh` sets the flags, migrates the local database and serves on 127.0.0.1:5000. Commands are in SECURITY_TESTING_GUIDE §1d.
- **Changed callers:** `config/settings.py`, `services/email_service.py` and `services/itinerary_service.py` now call `local_safety.load_environment()` instead of `load_dotenv()`.
- **Tests:** `security/tests/test_local_safety.py`, 30 tests. They include a subprocess that traps every DNS and socket call and proves a Neon host is refused before any network attempt.
- **Live check:**
  - local start succeeded (`"database":"connected"`, local database at `d5e6f7a8b9c0`);
  - start with `DB_HOST=*.neon.tech` was refused, for both `db upgrade` and `run`;
  - no secrets appeared in the logs.

**Turnstile rejection paths against real Cloudflare (local backend, local database):**

| Case | Result |
|---|---|
| Missing / non-string token | 400, `reason=missing`, no network call |
| Oversized token (2100 characters) | 400, `reason=invalid`, no network call |
| Invalid token (always-fail secret `2x…`) | 400, `reason=invalid codes=invalid-input-response` |
| Token without `action` (always-pass secret `1x…`, even with a garbage token) | 400, `reason=action_mismatch` |
| Spent token (`3x…` secret, P8.3) | 400, `reason=expired_or_reused codes=timeout-or-duplicate` |
| Cloudflare unreachable (outbound HTTPS through a dead proxy) | 503 `turnstile_unavailable` in about 3 s, `codes=network-error` |
| Enabled without keys | 503 on both endpoints and on the challenge page, plus a start-up error |
| Honeypot filled, including a non-string value | generic 200/201, no Siteverify call, no user created |

**BLOCKED (owner must create a development widget, hostname `localhost`):**
- acceptance of a genuine token for `register` and for `forgot_password`;
- account creation only after verification;
- identical forgot-password responses with a genuine token;
- wrong action and wrong hostname with a genuine token;
- real Cloudflare expiry after 300 s, and real reuse.

The procedure is in SECURITY_TESTING_GUIDE §1e.

**Web fix (`turnstile_field.dart`):** when Cloudflare's script was blocked or `render` failed, the web form showed no explanation and had no working retry. Submitting was blocked, so it still failed closed.
- An `unavailable` status now shows the load-error text and a retry on the web.
- The view is keyed per load attempt, so a retry builds a fresh widget. Before this, the cached config kept the old view and the retry did nothing.
- A new browser test fails without the fix and passes with it.

**Tests and builds (2026-11-12, this stage):**
- Backend:
  - security suite 528 passed / 45 skipped;
  - backend unit tests 44 passed;
  - PG 18 runtime role + RLS + Redis 45 passed;
  - Bandit 0 medium or higher.
- Flutter:
  - analyze clean; VM tests 102 passed;
  - browser tests 6/6 (two random orders, CanvasKit workaround);
  - web release build OK; Android debug APK built with temporary low-memory Gradle overrides (no file changes).
