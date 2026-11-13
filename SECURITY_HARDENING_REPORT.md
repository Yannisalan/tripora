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

---

# P9. F3: per-account login throttle (2026-11-13, uncommitted)

Closes finding **F3** (P5.3): login throttling was per client IP only (10 / 10 min),
with no per-account budget, so distributed credential stuffing spread across many
IPs was not slowed for the targeted account. This adds a second, independent
rate-limit bucket keyed on the **account** (the normalized e-mail), bounding login
attempts for one account across every source IP. The per-IP limit is unchanged and
still applies in parallel.

> **Correction (2026-11-13, final review M1, see P13).** As implemented in this
> phase the per-account bucket was enforced **only on `POST /api/auth/login`**. The
> admin password step `POST /api/admin/auth/login` verifies the same password but
> was limited per IP only, so for admin accounts the "across every source IP" bound
> above did **not** hold. P13 applies the same shared counter to that endpoint.

Nothing is committed, pushed, or deployed; no Render/Neon/production access.

This section records the implementation **as it stands after the adversarial
self-review in P9.7** — the first cut used a read-then-count gate, which the review
found could be bypassed by a simultaneous burst; it was replaced by an atomic gate
before anything was committed.

## P9.1 Design

- **Second bucket, not a replacement.** The per-IP `auth.login` bucket stays in
  the `before_request` hook. The new bucket `auth.login_account` is applied
  **inside the login route**, because only the route sees the submitted e-mail and
  the outcome.
- **Atomic gate.** Enforced with `limiter.check()` — one atomic
  increment-and-compare per attempt, the same primitive the per-IP limiter uses. At
  most `limit` attempts per window are admitted no matter how many source IPs fire
  at once; the rest are refused **before** any password hash.
- **Checked before verification**, so a tripped account refuses even a correct
  password (stops a stuffing run from winning on the attempt that finally guesses
  right).
- **Reset on success.** A successful login clears the counter
  (`limiter.reset_key`), so legitimate use is never penalised; the effective metric
  is *consecutive* failed attempts, also bounded by the fixed window.
- **Keyed HMAC, never plaintext.** Key =
  `HMAC-SHA256(secret, "login-throttle:v1:" + normalized_email)` as hex. The raw
  address never appears in a key or a log. Secret is a dedicated
  `LOGIN_RATE_LIMIT_HMAC_KEY` if set, else the already-required `JWT_SECRET_KEY`
  (domain-separated by the label).
- **Normalization matches registration** (`str(email).strip().lower()`), so casing
  and whitespace cannot split one account across buckets.
- **Enumeration-safe.** Keyed on the submitted e-mail **whether or not an account
  exists**; a blocked attempt returns the same generic 429 as the global limiter,
  with no DB/hash work. Registered and unknown addresses are indistinguishable.
- **Fail-closed on the unexpected, fallback where safe.** An unexpected limiter
  error at the gate returns 503 (rejects) rather than silently admitting an
  unthrottled attempt. The *designed* Redis-outage path still counts in the
  per-process fallback store (default `fallback` mode) so login stays up; under the
  opt-in `closed` mode the bucket (now listed in `SENSITIVE_RATE_LIMIT_BUCKETS`)
  returns 503, consistent with `auth.login`.

Default: **20 failed attempts / account / hour**
(`RATE_LIMIT_LOGIN_ACCOUNT_LIMIT` / `RATE_LIMIT_LOGIN_ACCOUNT_WINDOW`).

## P9.2 Files

| File | Change |
|---|---|
| `backend/services/rate_limiter.py` | New `peek()` (read-only state, for tests/observability), `reset_key()` (clear one key in primary+fallback, for reset-on-success), `_peek_count()` helper, and `clear_key()` on both storage backends. Existing methods untouched. |
| `backend/config/settings.py` | New `RATE_LIMIT_LOGIN_ACCOUNT_LIMIT/WINDOW` (20 / 3600), `login_rate_limit_hmac_key()`, the `auth.login_account` bucket, and that bucket added to `SENSITIVE_RATE_LIMIT_BUCKETS`. |
| `backend/routes/auth.py` | Login route: `_account_login_key()`, the generic 429 builder, the 503 fail-closed builder, the atomic `check()` gate (RateLimitExceeded→429, RateLimitUnavailable/unexpected→503), and `reset_key()` on the success path. New imports: `hmac`, `time`, limiter symbols. |
| `security/tests/test_login_account_throttle.py` | New: 19 tests (A–G of the brief, Config default, unit checks, concurrency at both limiter and HTTP level, and storage-failure / fail-closed). |
| `security/tests/test_audit_remediation.py` | Extended the "every configured bucket names a real endpoint" guard to allow `auth.login_account` as a deliberate non-endpoint bucket (same exemption as `AI_GLOBAL`). |

## P9.3 Vulnerability addressed

- **Distributed credential stuffing (F3).** Before: rotating source IPs faced only
  the 10 / 10 min per-IP cap. After: the targeted account has a hard 20 / hour
  budget that no amount of IP rotation — simultaneous or sequential — can exceed,
  and once tripped even a correct password is refused for the rest of the window.

## P9.4 Reproducible tests (`security/tests/test_login_account_throttle.py`, 19)

- **A — same account, many IPs:** 5 failures (tightened limit) from 5 distinct IPs
  are 401; a 6th from a fresh IP is 429. A companion test proves a correct password
  from a fresh IP is also 429 once tripped.
- **B — many accounts, one IP:** 10 failures for distinct e-mails from one IP are
  401, the 11th is 429 — the per-IP protection still fires, independently.
- **C — normalization:** five casing/whitespace variants of one address share one
  bucket; a unit test asserts the key is deterministic, a 64-char hex digest, and
  contains neither `@` nor the local-part.
- **D — success not penalised:** a login below the limit succeeds; a success resets
  the counter to zero and the account gets a fresh budget.
- **E — no enumeration:** the blocked 429 for a real account and for an unknown
  address are byte-identical (status, JSON, headers), as are the sub-limit 401s.
- **F — expiry + boundary:** with a 1-second window the bucket resets on roll-over;
  a second test characterises the fixed-window boundary bound (≤ 2×limit across one
  roll-over, never more).
- **G — concurrency (atomic gate):** 300 threads behind a barrier call the gate;
  **exactly `limit` are admitted** and the rest atomically blocked. A second test
  fires 40 simultaneous HTTP login POSTs (distinct IPs, limit 1) and asserts exactly
  one is admitted (401) and the other 39 are 429.
- **Storage failure:** fallback mode still enforces via the per-process store when
  the primary is down; closed mode raises `RateLimitUnavailable` for a sensitive
  bucket; an unexpected gate error and a `RateLimitUnavailable` both make the login
  endpoint return **503 (fail-closed)**, never a silent unthrottled success.

## P9.5 Test results (2026-11-13, local, all actually run)

- Focused F3 module: **19 passed**.
- Full backend security suite: **547 passed, 45 skipped** (skips = the opt-in
  Postgres/Redis suites). No regressions. One pre-existing invariant test
  (`test_every_configured_bucket_names_a_real_endpoint`) was updated for the new
  non-endpoint bucket (P9.2).

## P9.6 Remaining limitations / risks

- **Targeted account-lockout DoS (accepted).** An attacker who can send ≥ `limit`
  failed logins for a victim's e-mail (needs ≥ 2 IPs to clear the 10/IP cap) locks
  that account — correct password included — until the window expires (≤ 1 hour) or
  a successful login resets it (which the victim cannot do while locked).
  *(Update 2026-11-13, P13 / L1: a completed password reset now also clears the
  counter; before P13 a reset did not.)* This is
  the inherent availability/brute-force trade-off of any account throttle. It is
  **temporary and self-recovering**, not a permanent lock, and the threshold stays
  at the agreed 20 (not silently changed). Future softening, if the trade-off is
  judged wrong: a step-up challenge (CAPTCHA) on throttle instead of a hard block,
  owner notification on repeated lockouts, and/or IP-reputation weighting.
- **Fixed-window boundary (≤ 2×limit).** Across one window roll-over an account can
  see up to 2×limit attempts in a short span (characterised in F). Accepted for a
  20/hour budget; a sliding window would remove it but diverge from the shared
  fixed-window infrastructure. Not implemented.
- **Per-worker budget without Redis.** With `REDIS_URL` unset the counter is
  per-process and resets on restart, so the effective budget is multiplied by the
  Gunicorn worker count — the same caveat as every other bucket (F4). Atomic,
  cross-worker enforcement requires Redis (its `INCR` is the shared atomic op);
  setting `REDIS_URL` (owner action) provides it.
- **No lockout notification.** F3 slows stuffing; it does not notify the account
  owner. Out of scope here.
- Scope note: F6, F7 and F9 were explicitly **not** started in this phase.

## P9.7 Adversarial self-review (2026-11-13)

A focused review of the first F3 cut was run against six areas. Findings and resolutions:

1. **Concurrency — real bug, fixed.** The first cut gated with a read
   (`peek()`) and counted failures separately (`register_failure()`). A
   simultaneous burst — exactly the distributed stuffing F3 targets — would all read
   the counter below the limit and all be admitted before any increment landed; the
   **cold-start burst bypassed the limit entirely**. Replaced with the atomic
   `limiter.check()` gate (increment-and-compare), which admits at most `limit`
   under any contention. Proven by a 300-thread limiter test and a 40-request HTTP
   test (both assert *exactly* `limit` admitted). Cross-worker atomicity holds with
   Redis `INCR`; without Redis it is per-worker (documented above).
2. **Storage failure — fail-open path closed.** The first cut caught every
   exception at the gate and then *continued* (fail-open). Now an unexpected gate
   error returns 503; the designed Redis-outage fallback (per-worker counting) is
   preserved for the default mode, and `closed` mode returns 503. Tests simulate a
   failing primary store and an unexpected gate error.
3. **Window boundaries.** Fixed-window allows ≤ 2×limit across a roll-over
   (characterised and tested). Judged acceptable for 20/hour; sliding window not
   adopted, to preserve compatibility with the existing limiter. No code change.
4. **Denial of service.** Targeted account lockout is possible and is the accepted,
   temporary trade-off (documented in P9.6). Threshold unchanged at 20. The
   correct-password-blocked behaviour is retained deliberately.
5. **Test quality.** Concurrency tests use real threads behind a `threading.Barrier`
   (genuine simultaneity, not mocks) and assert exact admit/block counts; the HTTP
   concurrency test exercises the real endpoint. Normalization, unknown accounts,
   success, multi-IP and expiry are all covered by behavioural (not mocked) tests.
6. **Final verification.** Focused suite 19/19; full suite 547 passed / 45 skipped;
   full diff inspected; this report corrected to the measured results.

---

# P10. F6: production startup validation for weak secrets (2026-11-13, uncommitted)

Closes finding **F6** (P5.3): a `JWT_SECRET_KEY` shorter than 32 characters (and a
short `ADMIN_API_TOKEN`) only logged a start-up warning. Production now **refuses
to start** (RENDER=true) when a critical authentication secret is missing or weak,
while development, staging and the test suite keep the warn-only behaviour.

Nothing is committed, pushed, or deployed; no Render/Neon/production access.

## P10.1 Design

- **Production condition:** `RENDER=true` (case-insensitive), the agreed F6
  signal. `_is_production()` reads it live.
- **Strength rule:** `_is_strong_secret(v)` = present AND `len(v.strip()) >= 32`.
  This rejects missing (`None`), empty, whitespace-only, and short values in one
  predicate.
- **JWT_SECRET_KEY:** always required and strong in production — it signs every
  session token. Missing/empty/whitespace/short → refuse start.
- **ADMIN_API_TOKEN:** validated as **conditionally mandatory**. The only code
  path that accepts it is the legacy shared-token admin check
  (`routes/admin.py:_legacy_token_matches`), which is gated on
  `ADMIN_LEGACY_TOKEN_ENABLED`. So the token is required and strong **only while
  that flag is true** (its default); when the legacy path is disabled the token is
  dead configuration and is not validated (so turning the legacy path off is the
  supported way to run without it). An empty token already fails safe at runtime
  (grants no access), but with the legacy path enabled a weak/missing token is a
  real brute-force surface, hence the hard failure.
- **Lifecycle:** enforced in `_validate_production_secrets()`, called at the very
  top of `create_app()` (immediately after `app.config.from_object`, **before**
  ProxyFix, blueprints, JWT, the DB and Redis). A failure aborts app construction;
  the process never begins serving. Outside production the same function calls the
  existing `_warn_weak_secrets()` and returns.
- **No value disclosure:** errors and logs name the variable and the required
  length only; the secret value never appears. Raised as a dedicated
  `ConfigurationError`. No replacement secret is ever generated; no hardcoded
  secret is introduced.

## P10.2 Files

| File | Change |
|---|---|
| `backend/app.py` | New `ConfigurationError`, `_is_production()`, `_is_strong_secret()`, and `_validate_production_secrets()` (fatal in production, warn-only otherwise). `_warn_weak_secrets()` now uses the shared predicate (and reports a missing JWT secret too). `create_app()` calls the validator instead of the bare warning. |
| `security/tests/test_production_secret_validation.py` | New: 30 tests (A–J of the brief) including the strength predicate, production failures, non-production warn-only, value-non-disclosure, and a lifecycle test that `create_app()` aborts. |

No change to `routes/admin.py`, `services/admin_auth.py` or any authentication
logic: admin and user auth behave exactly as before.

## P10.3 Vulnerability addressed

- **Weak production secrets accepted at start-up (F6).** Before: a short
  `JWT_SECRET_KEY` (offline-forgeable session tokens) or a short, legacy-enabled
  `ADMIN_API_TOKEN` (online-guessable full-admin credential) only produced a log
  line that is easy to miss. After: production will not start with them, forcing
  the misconfiguration to be fixed before any traffic is served.

## P10.4 Reproducible tests (`security/tests/test_production_secret_validation.py`, 30)

- **A/B (valid):** strong JWT + strong admin token (legacy on) passes; strong JWT
  with legacy **off** passes even with no admin token.
- **C/E/G (JWT):** short, missing, empty and whitespace-only `JWT_SECRET_KEY` each
  raise `ConfigurationError` naming the variable.
- **D/F/G (admin):** short/missing/empty/whitespace-only `ADMIN_API_TOKEN` raises
  **when legacy is enabled**, and is **ignored when legacy is disabled**.
- **H (enforcement):** `RENDER=true`/`TRUE` enforce; a lifecycle test shows
  `create_app()` itself raises (startup actually blocked), not just the helper.
- **I (dev):** with `RENDER` unset/`false`/`0`/`no`, weak secrets do **not** raise
  (a warning is logged instead).
- **J (test env):** the conftest `app` fixture still builds, and the exact test
  posture (RENDER unset, long JWT, short admin token, legacy on) does not raise.
- **No disclosure:** two tests assert the secret value never appears in the raised
  exception; one asserts both bad secrets are reported together.

## P10.5 Test results (2026-11-13, local, all actually run)

- Focused F6 module: **30 passed** (0.07 s).
- Full backend security suite: **577 passed, 45 skipped** (547 before F6 + 30 new;
  skips = the opt-in Postgres/Redis suites). No regressions.

## P10.6 Remaining limitations / operational note

- **Deployment gate (intended).** Because `ADMIN_LEGACY_TOKEN_ENABLED` defaults to
  true, a production deploy of this change will **fail to start** if the live
  `JWT_SECRET_KEY` or `ADMIN_API_TOKEN` is missing or < 32 characters. That is the
  point of F6, but it means the owner must confirm the production values are
  strong (or set `ADMIN_LEGACY_TOKEN_ENABLED=false`) **before** deploying — exactly
  the values already listed as a deploy requirement in P2.6 / `docs/DEPLOYMENT.md`.
  No production value was read or changed by this work.
- **Scope.** Only `JWT_SECRET_KEY` and `ADMIN_API_TOKEN` are enforced, as F6
  specifies. Other secrets (`MFA_ENCRYPTION_KEY`, provider API keys) still rely on
  their own existing checks and are out of F6's scope.
- Scope note: F7 and F9 were explicitly **not** started in this phase.

---

# P11. F9: fixed, safe client-facing error responses (2026-11-13, uncommitted)

Closes finding **F9** (P5.3). The P5.3 review rated it "Info / negligible" because
most `str(error)` responses carried hand-written messages. A full audit found that
the same handlers also caught exceptions whose text was **not** written for clients.
They leaked raw input echoed by the parser, provider names and credential state, and
(in server logs) SQL bind values. Every client-facing exception message now comes
from an allow-list.

Nothing is committed, pushed, or deployed. There was no Render, Neon, Vercel or
production access. F7 was not started.

## P11.1 Audit (all of `backend/`, excluding `venv`)

Searched: `str(error|exc|e)`, exception interpolation (`{error}`, `%s` with
exceptions), `repr`, `traceback`/`format_exc`, `errorhandler`, every
`except ... as` in `routes/`, and the JWT loaders.

| Location | Before | Sensitive? | Verdict |
|---|---|---|---|
| `routes/trips.py` generate + PATCH: cost `except ValueError` → `str(error)` (400) | Any `ValueError` from `cost_service`/`date.fromisoformat`. E.g. `startDate: "2026-09-01xyz"` passes the payload parser (`[:10]`) but cost parsing returned **`Invalid isoformat string: '2026-09-01xyz'`** | **Yes.** It reflects raw input and the exception class's wording, and any future `ValueError` in the call chain would also be echoed | **Fixed** |
| `routes/trips.py` generate + PATCH: `_parse_trip_payload` `except ValueError` → `str(error)` (400) | Only app-written messages today, but a stdlib `ValueError` inside the parser would be echoed | Latent | **Fixed** (allow-listed) |
| `routes/trips.py` ×7, `routes/expenses.py` ×5: identity `except ValueError` → `str(error)` (401) | Always `"Invalid authenticated user."` | Latent | **Fixed** (constant) |
| `routes/auth.py` ×5 (`/me` GET/PATCH, `/account` DELETE, `/verify-email`, `/verify-email/resend`): `except InvalidIdentityError` → `str(error)` (401) | Always `"Invalid authenticated user."` | Latent | **Fixed** (constant) |
| `routes/travel.py` `_db_error_response` (502) for stays, cars, flight search, flight prices | **`"Live travel search is not configured. Duffel credentials are missing."`**, **`"Travelpayouts rejected the API credentials."`**, provider-unreachable messages | **Yes.** It names the vendor and reveals credential/configuration state | **Fixed** |
| `routes/travel.py` flight search location lookup (400) | `TravelpayoutsError` text | Mixed: the lookup messages are intentional user guidance, but other `TravelpayoutsError`s could reach this path | **Fixed** (lookup messages kept, rest generic) |
| No app-level error handler | Unhandled exceptions and `abort()` returned Werkzeug HTML pages. These carry no traceback with debug off, but `abort(…, description=…)` text is rendered verbatim and responses were not JSON | Latent | **Fixed** (JSON handlers) |
| SQLAlchemy engine | `logger.exception` on DB failures writes `[parameters: …]`: e-mails, password/reset-code hashes, token versions | **Yes, in server logs** | **Fixed** (`hide_parameters=True`) |
| `routes/trips.py` cost warning log `"…failed: %s", error` | Logged raw input/exception text | Low (server log) | Now logs the exception type only |

Already safe, left unchanged: all `except Exception` 500 handlers in
trips/expenses/admin/auth/health (fixed messages + `logger.exception`); social
login (TRP-13, generic message); `rates.py` and `weather.py` (generic 503 /
"temporarily unavailable"); the JWT loaders (fixed messages); `admin_auth.py`
(`AdminAuthUnavailable` text is never returned); the rate limiter's
`StorageError(str(error))` (internal only, never logged with detail or returned);
`social_auth_service` / `itinerary_service` exception interpolation (caught by
generic handlers before any response).

## P11.2 Remediation

- **`backend/services/client_errors.py` (new).** `ClientValidationError(ValueError)`
  marks a message written for the client. `client_message(error, fallback)` returns
  `str(error)` only for that class (non-empty) and `fallback` for anything else,
  including plain stdlib `ValueError`s. It also holds the shared constants
  `INVALID_SESSION_MESSAGE`, `GENERIC_SERVER_ERROR` and `UNEXPECTED_ERROR_MESSAGE`.
  Because the class subclasses `ValueError`, every existing `except ValueError`
  still catches it.
- **Trips.** The 17 `raise ValueError(...)` in `_parse_trip_payload` became
  `ClientValidationError` with **identical text**. `cost_service` raises
  `ClientValidationError("End date must be after start date.")`. The payload and
  cost handlers return `client_message(error, "Trip details are invalid.")`, still
  with status 400.
- **Identity errors (trips, expenses, auth).** Every handler returns
  `INVALID_SESSION_MESSAGE` (same text as before, now a constant) with 401.
- **Travel.** The new `TravelpayoutsLookupError(TravelpayoutsError,
  ClientValidationError)` is raised only by `resolve_city_to_iata`, and its three
  user-guidance messages are unchanged. `_provider_error_response` (renamed from
  `_db_error_response`) returns `"Travel search is temporarily unavailable. Please
  try again later."` with the same **502**, `error: travel_provider_error` and
  `code: PROVIDER_ERROR`. The vendor detail is logged server-side. A non-lookup
  provider error during flight-search resolution now returns that 502 instead of a
  400 that echoed the provider text.
- **App-level handlers (`app.py` `_register_error_handlers`).**
  - `HTTPException`: JSON `{success:false, message:<fixed per status>, error:<HTTP
    name>}` with the original status. `description` is never returned. `Allow`,
    `Retry-After` and `WWW-Authenticate` are preserved.
  - Any status ≥ 500 returns the generic message.
  - Unhandled `Exception`: rolls back the session, runs `logger.exception`, and
    returns a generic JSON 500.
    - *Corrected 2026-11-13 (final review I3); the original text said the log held
      the "type, method and path only".*
    - The log message names the exception type, method and path.
    - `logger.exception` **also records the exception's message and the full
      traceback**, so any data inside the exception text reaches the server log
      (never the client).
    - The handler itself never logs the request body or headers.
    - SQL bind values are hidden by `hide_parameters`. PostgreSQL `DETAIL` lines
      (e.g. `Key (email)=(…) already exists`) are part of the exception message and
      are still logged (final review L3).
  - Flask-JWT-Extended's own handlers are more specific, so they still win; the JWT
    401 responses are unchanged.
- **Logs.** `create_app()` sets `hide_parameters=True` in
  `SQLALCHEMY_ENGINE_OPTIONS` (via `setdefault`, so the conftest/SQLite options
  still merge). DB exception text in logs no longer contains bind values.
  *(Clarified 2026-11-13: server-generated `DETAIL` text can still contain row
  values; see the correction above and P13.)*

API contract: status codes and JSON shapes are unchanged everywhere. Message text
changed only where it was unsafe:
- travel 502 message;
- the trips 400 fallback for non-validation parser errors;
- the flight-search provider error, now 502 instead of 400;
- unknown routes/methods/oversized bodies now get JSON instead of HTML.

The Flutter client does not branch on any changed text (searched `frontend/`).

## P11.3 Files

| File | Change |
|---|---|
| `backend/services/client_errors.py` | New: `ClientValidationError`, `client_message`, shared message constants. |
| `backend/routes/trips.py` | Allow-listed validation errors, constant session message, generic cost fallback, type-only cost log. |
| `backend/routes/expenses.py` | Constant session message. |
| `backend/routes/auth.py` | Constant session message (5 handlers + `_current_user_id`). No auth logic change. |
| `backend/routes/travel.py` | `_provider_error_response` with a fixed message; lookup vs provider split. |
| `backend/services/travelpayouts_service.py` | `TravelpayoutsLookupError` for `resolve_city_to_iata`. |
| `backend/services/cost_service.py` | Its one validation message raised as `ClientValidationError`. |
| `backend/app.py` | JSON `HTTPException`/`Exception` handlers; `hide_parameters=True`. |
| `security/tests/test_f9_error_disclosure.py` | New: 43 tests. |
| `security/tests/test_login_account_throttle.py` | Flaky-test fix only (see P11.6). |

## P11.4 Reproducible tests (`security/tests/test_f9_error_disclosure.py`, 43)

Each test plants a secret-looking DSN (`postgresql://…:hunter2-secret@…`) and/or
SQL text in an exception, then asserts that neither (nor `Traceback` /
`password_hash`) appears in the JSON body.

- **Helper (8):**
  - `ClientValidationError` messages pass through;
  - stdlib `ValueError`, `RuntimeError`, `KeyError` and provider errors fall back;
  - an empty message falls back;
  - the class is still a `ValueError`.
- **Trips (14):**
  - the stdlib date error is not echoed on generate or PATCH;
  - the same-day cost message is kept;
  - six payload validation messages are kept exactly (body equality);
  - an injected `ValueError` returns the generic 400;
  - an injected `RuntimeError` returns the generic 500;
  - identity errors return the fixed 401 on 3 routes;
  - a DB `OperationalError` on list hides the SQL, the bind e-mail and the DSN.
- **Identity / auth (5):**
  - expenses identity error;
  - `/me`, `/verify-email` and `/verify-email/resend` identity errors;
  - Apple social-verification detail is hidden.
- **Travel (6):**
  - unconfigured Duffel stays and cars, and unconfigured Travelpayouts prices, each
    use the real service with credentials removed and need no network;
  - rejected credentials;
  - a non-lookup error during resolve;
  - in each of these: the generic 502, `code` kept, and no "Duffel",
    "Travelpayouts", "credentials" or "not configured" in the body;
  - the lookup message is kept (400).
- **Global handlers (9):**
  - an unhandled exception gives the generic JSON 500, the log has its type and
    path, and the log has **no** request-body password or Authorization token;
  - an unhandled DB error hides the SQL and bind values;
  - `abort(400/503, description=…)` text is hidden;
  - 404, 405 (with `Allow`) and 413 return JSON;
  - a DB failure in a route without local try/except (`/verify-email/resend`)
    returns the generic 500;
  - JWT 401 handlers are unchanged.
- **Logs (2):**
  - `db.engine.hide_parameters is True`;
  - a real failing statement's exception text has no bind value and says the
    parameters are hidden.

**Negative control:** with the pre-F9 route files, `app.py` and `cost_service.py`
temporarily restored, **23 of 43 fail**. The 20 that pass are the helper unit tests
and the "keep legitimate message" tests, which is correct. The F9 files were then
restored, and the diff was re-checked.

## P11.5 Test results (2026-11-13, local, all actually run)

- Focused F9 module: **43 passed**.
- Full security suite (`pytest`, `security/tests`): **620 passed, 45 skipped**
  (577 before F9 + 43 new; the skips are the opt-in Postgres/Redis suites).
- Backend suite (`pytest backend -m "not integration"`): **42 passed, 2
  deselected**.
  - An unfiltered `pytest backend` run reported `test_itinerary.py::test_generate_itinerary`
    as failed. That test is marked `integration`, calls the **live Gemini API** with
    the locally configured key, and received `504 DEADLINE_EXCEEDED`.
  - It is unrelated to F9: neither the test nor `itinerary_service.py` changed.
  - It was not re-run, to avoid further external calls.
- Diff review: only the files in P11.3 changed for F9. CRLF/LF endings match the
  originals. Nothing is committed.

## P11.6 Flaky F3 test fixed (test-only)

`TestWindowExpiry::test_account_bucket_expires_after_window` (P9) used a 1 s
epoch-aligned window. The three attempts (~0.3 s each of scrypt hashing) crossed a
window boundary in roughly half of all runs, so the third attempt got 401 instead
of 429. It failed 5 of 8 runs **with or without** the F9 changes.

The test now uses a 3 s window and starts at a fresh window boundary. It passed 6
of 6 runs plus the full suite. No limiter code changed.

## P11.7 Remaining intentional disclosures (justified)

- **Hand-written validation messages** (trip payload, cost "End date must be after
  start date.", expense validation, travel input checks, auth validation). These
  are written for users and contain no internal state.
- **Travel location lookup messages** ("Could not find that location. Check the
  spelling…"). This is user guidance, and the input itself is not echoed.
- **Social login conflict/verification wording** (unchanged, TRP-13). The text is
  generic and names only the provider the client chose.
- **`rates.py` / `weather.py` "temporarily unavailable" messages.** These are
  generic and contain no detail.

## P11.8 Remaining limitations

- **Server-side logs still contain some exception detail by design.** This
  includes provider messages, Open-Meteo response bodies (≤500 chars, no secrets:
  the API is keyless), and Gemini error payloads. SQL bind values and request
  bodies/headers are not logged by the new handler.
  - Ensure the Render log drain access is restricted.
  - Log retention is F7, which was not started.
- **`/verify-email` and `/verify-email/resend` still have no local try/except.**
  DB failures there now go through the global handler: generic JSON 500 plus
  rollback. That is safe, but the message is less specific.
- **`hide_parameters` is applied in `create_app()`.** Any other engine (e.g.
  Alembic's own `env.py` connection) is unaffected. Migrations run from the CLI, not
  from request paths.
- **No live/production verification.** That requires a deploy, which is reserved
  for the owner.

---

# P12. F7: log retention and secure purge (2026-11-13, uncommitted)

Closes finding **F7** (P5.3): `activity_logs` (IP addresses, paths, user ids; 2414
rows in production at P5) and `admin_audit_log` had no retention. There is now a
dry-run-by-default `flask logs purge` command.

Nothing is committed, pushed, or deployed. There was no Render/Neon/Vercel or
production access, and **the purge was never executed against a real database**.
The only databases used were the in-memory SQLite test DB and the disposable local
container `tripora_security_test`.

## P12.1 Investigation (verified schema)

| | `activity_logs` | `admin_audit_log` |
|---|---|---|
| Timestamp | `created_at DateTime NOT NULL`, default `datetime.utcnow` (**naive UTC**), indexed `ix_activity_logs_created_at` | same, `ix_admin_audit_log_created_at` |
| Outgoing FK | `user_id → users.id` (no ON DELETE action) | `admin_user_id → users.id ON DELETE SET NULL` |
| Incoming FKs | **none** | **none** |
| Writers | `app.py` after-request hook, `POST /api/admin/page-view` | `admin_auth.audit()` (commits separately and never raises), admin routes, `flask admin` CLI |
| Existing deletes | account deletion removes the user's own rows (`routes/auth.py`) | none |
| RLS (migration `d5e6f7a8b9c0`, FORCE) | `activity_logs_delete_owner`: the runtime role may only delete rows whose `user_id` = JWT subject | no DELETE policy; `roles.sql` **revokes DELETE** from `tripora_runtime` |

Consequences for the design:
- Deleting log rows cannot violate any FK.
- The cutoff must be naive UTC.
- The purge must run as the database **owner** (`DB_MIGRATION_*`, like migrations).
- Under the runtime role, a DELETE either affects zero rows silently (RLS) or fails
  (no grant). Both cases must be detected; neither may report success.

## P12.2 Implementation

- **`backend/services/log_retention.py` (new)**, function `purge_expired_logs(...)`.
  - **Policy:** `activity_logs` keeps **90 days**; `admin_audit_log` keeps **365
    days**.
    - Overrides may only *lengthen* retention. Shorter values raise `ValueError`
      before anything runs.
    - `batch_size` must be between 1 and 10000.
  - **UTC:** one timezone-aware `datetime.now(timezone.utc)` reference per run,
    truncated to whole seconds and converted to naive UTC.
    - `cutoff = reference − retention`.
    - A naive reference time is rejected.
    - Expired means `created_at < cutoff` (strict), so a row exactly at the cutoff is
      kept.
  - **NULL timestamps:** never match `<`, so they are always kept. They are counted
    and reported.
  - **Single transaction:**
    - counts for both tables, then batched deletes for both, then the purge's own
      audit record, then **one commit**;
    - any exception rolls everything back and raises `RetentionError`;
    - the error message carries table names and counts only, and the log gets only
      the exception type.
  - **Memory:** `DELETE … WHERE id IN (SELECT id … WHERE created_at < :cutoff
    ORDER BY id LIMIT :n)`, repeated until it affects 0 rows. No row is loaded
    into Python.
  - **No silent no-op:** after deleting, eligible rows are recounted. If any remain,
    it raises (`"<table>: N expired row(s) could not be deleted (insufficient
    privileges or row-level security?)"`) and rolls back.
  - **Audit is not weakened:**
    - every executed purge appends `admin_audit_log` action `log_retention_purge`;
    - that record holds the reference time and, per table, retention days, cutoff,
      eligible and deleted counts;
    - it commits **atomically** with the deletions, so a purge can never commit
      without its audit record;
    - it is new, so it is never itself eligible.
    - Dry runs write nothing.
  - **RLS context:** `db_context.scoped(auth_flow=True, admin_read=True)`, the same
    as the existing `flask admin` commands. Under the owner this changes nothing
    (BYPASSRLS).
- **`backend/services/cli.py`:** new group `logs`, command `purge`, registered in
  `register_cli`. Options:
  - `--execute` (flag, default off);
  - `--activity-days` (`IntRange(min=90)`);
  - `--audit-days` (`IntRange(min=365)`);
  - `--batch-size` (1–10000).

  The command prints:
  - the mode (`DRY RUN (nothing will be deleted)` / `EXECUTE`);
  - the reference time;
  - per table: retention days, cutoff (ISO `…Z`), eligible count, rows kept
    without a timestamp, and the deleted count when executing;
  - a final summary.

  Failures exit with code 1 and print the rollback message. **No record content is
  ever printed or logged.**
- **No scheduling.** Nothing runs automatically: no cron, no background thread, no
  request hook.

Operator usage (owner credentials, the same pattern as migrations):

```
DB_USER=$DB_MIGRATION_USER DB_PASSWORD=$DB_MIGRATION_PASSWORD flask --app wsgi logs purge            # review
DB_USER=$DB_MIGRATION_USER DB_PASSWORD=$DB_MIGRATION_PASSWORD flask --app wsgi logs purge --execute  # delete
```

## P12.3 Files

| File | Change |
|---|---|
| `backend/services/log_retention.py` | New: policy, cutoff, batched transactional purge, audit record. |
| `backend/services/cli.py` | New `logs purge` command; `register_cli` adds the `logs` group. Existing `admin` commands unchanged. |
| `security/tests/test_log_retention.py` | New: 37 tests (in-memory SQLite). |
| `security/tests/test_log_retention_postgres.py` | New: 6 opt-in integration tests (real PostgreSQL, runtime and owner roles). New env var `TRIPORA_PG_OWNER_URL` (owner of the disposable DB). |

No model, migration, route, RLS policy or grant changed.

## P12.4 Tests

`test_log_retention.py` (37):
- **Cutoffs (6):**
  - policy values 90/365;
  - the cutoff is naive UTC;
  - +05:00 and −08:00 references give the same cutoff as UTC;
  - naive references are rejected;
  - the default reference is the current UTC time with whole seconds;
  - **boundary:** a row exactly at the cutoff is kept and a row 1 µs older is
    deleted, in both tables.
- **Rules (8):**
  - a dry run counts 3/2 eligible rows, deletes nothing and writes no audit record;
  - the API defaults to a dry run;
  - execute deletes exactly the 91/120/400-day activity rows and the 366/500-day
    audit rows, and keeps 0/1/89-day and 0/100/364-day rows;
  - 100–300-day audit rows are kept (a separate, longer policy);
  - the purge audit record has the counts, cutoffs and `Z` suffixes, contains
    **no** IP or path, and is itself recent;
  - repeated runs delete 0 the second time;
  - empty tables work;
  - 2510 rows with batch size 1000 issue exactly 5 DELETE statements (3 + 1 empty
    for activity, 1 for audit), deleting 2500 and keeping 10.
- **NULL (1):** on a drifted table that allows NULL `created_at`, 2 NULL rows are
  reported and kept, and only the expired dated row is deleted.
- **Transactions (10):**
  - a failure in the audit-table step rolls back the activity deletions already
    made, and the error does not echo the injected IP;
  - a simulated RLS zero-row delete is detected (`activity_logs: 3 expired row(s)
    could not be deleted`) and rolled back;
  - a failure while recording the purge audit rolls back all deletions;
  - 6 invalid argument sets (shorter retention, batch 0/10001) touch nothing;
  - longer retention is honoured.
- **CLI (12):**
  - with no flag: a dry run that prints the mode, both retention periods, `Z`
    cutoffs and counts, deletes nothing, and prints no IP or path;
  - `--execute` deletes and reports the commit;
  - 8 unsafe or unknown argument sets (`--activity-days 30`, `--audit-days 90`,
    `--batch-size 0`, `--execute --activity-days 1`, `--force`, `-y`,
    `--execute yes`, `--dry-run=false`) are rejected with a non-zero exit and
    nothing deleted;
  - a failure exits 1 with the rollback message and no record content;
  - `--help` documents that nothing is deleted without `--execute`.

`test_log_retention_postgres.py` (6, real PostgreSQL 16, local disposable
container):
- **Runtime role:**
  - a dry run sees the counts;
  - `--execute` on `activity_logs` is blocked by RLS (zero rows) → detected →
    rolled back;
  - the `admin_audit_log` DELETE fails with SQLSTATE **42501
    insufficient_privilege** → rolled back;
  - the CLI exits 1 with no content in its output;
  - in all four cases the seeded rows are unchanged and no purge record is written.
- **Owner:**
  - a failure mid-run rolls back the real deletions;
  - the CLI `--execute --batch-size 1` deletes only the expired seeded rows,
    keeps recent ones, writes one purge audit record, and a second run deletes 0.

## P12.5 Test results (2026-11-13, local, all actually run against the final code)

- Focused F7 SQLite module: **37 passed**.
- F7 PostgreSQL module plus the existing runtime-role suites
  (`test_log_retention_postgres.py`, `test_rls_runtime_role.py`,
  `test_postgres_runtime_role.py`) on the disposable container: **44 passed**
  (6 new + 38 existing).
- Full security suite (`pytest`): **657 passed, 51 skipped**.
  - That is 620 before F7 + 37 new.
  - The skips are the 45 opt-in Postgres/Redis tests plus the 6 new opt-in F7
    Postgres tests.
- Backend suite (`pytest backend -m "not integration"`): **42 passed, 2
  deselected** (no live external API calls).
- Diff review: F7 touches only the files in P12.3. CLI output was checked for
  record content (none).

## P12.6 Remaining limitations

- **Not executed anywhere real.** The production row counts and the first real
  dry run are owner actions. The first production use should be a dry run with
  owner credentials; review its counts, then run `--execute`.
- **Owner credentials required.** Under `tripora_runtime` the purge always fails,
  safely and atomically. That is intended; it does not weaken RLS or the
  append-only audit grant.
- **No scheduling.** Retention is enforced only when an operator runs the command
  (suggested: monthly). Any automation (e.g. a Render cron job using the owner
  credentials) is a separate owner decision.
- **One transaction per run.** This is fine at current volumes (thousands of rows).
  With millions of expired rows, the first run holds row locks for its duration.
  Inserts of new rows are unaffected because they never match the cutoff.
- **Database only.** Backups and Neon point-in-time history retain purged rows
  until their own retention expires. Render/stdout log retention is configured in
  the platform, not here.
- **"Approximately" is implemented as exact.** It is exactly 90 × 24 h and
  365 × 24 h; leap years are not special-cased.

---

# P13. Final adversarial review of F3/F6/F9/F7, and remediation of M1 + L1 (2026-11-13, uncommitted)

## P13.1 Final review findings (as reported; read-only audit)

The review was read-only:
- the working-tree hash was identical before and after;
- probes lived outside the repo, on in-memory SQLite plus the disposable local PG16
  container;
- there was no production or cloud access.

Verdict: **requires minor fixes**. Nothing Critical or High was found.

| ID | Sev. | Finding | Status after P13 |
|---|---|---|---|
| M1 | Medium | `POST /api/admin/auth/login` verifies the same account password but had only per-IP limiting. Review evidence: 60 wrong guesses over 6 IPs all returned 401 with the account counter at 0; the correct password then returned 200 + `pendingToken` and also worked on `/api/auth/login`. | **Fixed** (P13.2) |
| L1 | Low | Targeted lockout. 20 failures from 2 IPs block the victim's correct password for up to 1 h, and a password reset did not clear it. | **Partly mitigated.** A completed reset now clears it; the lockout itself remains the accepted trade-off. |
| L2 | Low | The in-memory limiter never evicts keys; F3 adds one attacker-chosen key per e-mail (300 e-mails → 300 entries). Applies only without Redis. | Open (fixed operationally by Redis, F4) |
| L3 | Low | PostgreSQL `DETAIL` lines (row values) remain in logged exception text despite `hide_parameters`. Server logs only. | Open; P11.2 corrected |
| L4 | Low | The purge audit record has no operator attribution. | Open |
| I1 | Info | `LOGIN_RATE_LIMIT_HMAC_KEY` strength is not validated. | Open |
| I2 | Info | F6 is keyed on `RENDER=true` only and checks length, not entropy. `RATE_LIMIT_ENABLED=false` silently disables F3. | Open |
| I3 | Info | Report inaccuracies in P9 (coverage) and P11.2 (log contents). | **Corrected** (in place, marked) |
| I4 | Info | `purge_expired_logs()` rolls back a programmatic caller's pending work. | Open (the CLI is unaffected) |
| I5 | Info (hypotheses) | Concurrent purges, lock duration and very large tables. | Not reproduced |

## P13.2 M1 remediation: one shared per-account counter

- **`backend/routes/auth.py`:** the F3 gate is extracted **unchanged** into two
  helpers, and `login()` now calls them (behaviour identical; the F3 suite is green).
  - `enforce_account_login_throttle(normalized_email)`: same HMAC key, same
    `auth.login_account` bucket, same atomic `limiter.check`, same generic 429 and
    fail-closed 503.
  - `clear_account_login_throttle(normalized_email)`.
- **`backend/routes/admin_auth.py` (`admin_login`):**
  - The gate is called **after the existing input check and before the user lookup
    and password hash**, for every address. Admin, non-admin and unknown e-mails
    therefore get identical responses at every count, so throttling doesn't reveal
    whether an account exists or is an admin.
  - A throttled attempt is audited as `login_throttled` (`admin_user_id` NULL,
    because there is no lookup before the gate), so the audit trail is not weakened.
  - The counter is cleared only after a **verified admin password**, the same rule
    as the user login. TOTP or a recovery code is still required afterwards.
  - Unchanged: MFA enrollment, pending tokens, `enrollment_closed`, sessions and
    authorization. The MFA-unavailable 503 still returns before anything is counted.
  - A correct password for a **non-admin** account at the admin endpoint is a failed
    admin attempt: it is counted and not reset.

## P13.3 L1 remediation: completed reset clears the lockout

In `reset_password`, the account's normalized e-mail is captured with the matched
user, and `clear_account_login_throttle(email)` runs **only after the conditional
UPDATE affected exactly one row and `commit()` succeeded**.

These paths never clear the counter:
- requesting a code;
- a wrong code;
- an invalid, expired or reused token;
- a password-policy rejection;
- "same as old password";
- a rowcount mismatch;
- an exception.

Only that account's counter is cleared.

## P13.4 Tests (`security/tests/test_shared_account_throttle.py`, 17)

- **Shared counter (5):**
  - user-login failures lock the admin login (correct password → 429, no admin
    session row);
  - admin-login failures lock the user login (correct password → 429, no token);
  - alternating endpoints across 12 distinct IPs give 5×401 then 7×429;
  - the review reproduction (30 guesses over 30 IPs → 5×401 + 25×429; the correct
    password is then 429 on **both** endpoints);
  - a 30-thread simultaneous mixed burst admits exactly 1.
- **Admin behaviour (7):**
  - success resets the counter, and the full enroll → activate → `/me` flow still
    works;
  - a pending token alone gets 401 on `/me`;
  - identical 401/429 bodies for admin, non-admin and unknown addresses;
  - a non-admin correct password is counted;
  - throttled attempts are audited;
  - an account-gate fault returns 503 with no session;
  - MFA unavailable returns 503 before counting.
- **L1 (5):**
  - a completed reset clears the counter and the new password logs in;
  - a reset clears an admin lockout (the lockout is asserted first);
  - code request, wrong code, invalid token, policy and same-password failures clear
    nothing (the `reset_key` spy is never called for the account bucket, and the
    account stays 429);
  - a reused token doesn't clear a later lockout;
  - only the reset account is cleared.

**Negative control:** with the pre-fix `auth.py` and `admin_auth.py` temporarily
restored, **13 of 17 fail**. The 4 that pass are the preservation tests: pending
token, MFA-unavailable, failed resets don't clear, reused token. The fixed files were
restored and checked byte-identical by hash.

## P13.5 Test results (2026-11-13, local, final code)

- Focused: `test_shared_account_throttle.py` together with the F3, password-reset,
  phase-2 admin and backend-only admin suites: **128 passed**.
- Full security suite: **674 passed, 51 skipped** (657 + 17 new; the skips are the
  opt-in Postgres/Redis suites).
- Backend `-m "not integration"`: **42 passed, 2 deselected**.
- Diff: the only changes this phase are in `backend/routes/auth.py` (two helpers,
  the `login()` call sites, the reset clear), `backend/routes/admin_auth.py`, the new
  test file, and this report. F6, F7 and F9 code is untouched.

## P13.6 Remaining limitations

- **The lockout itself remains (L1).** Without a reset, an attacker can still keep an
  account locked for the window. The reset path is the owner's recovery route, and
  social login is unaffected. A step-up challenge instead of a hard block would be a
  separate design change.
- **A verified admin password resets the shared counter before TOTP.** This mirrors
  the user login. It only helps someone who already knows the password; TOTP has its
  own per-session attempt limit plus per-IP limits.
- **Other password checks** (`DELETE /api/auth/account`, password change in
  `PATCH /api/auth/me`) require a valid JWT and are not on the shared counter. They
  are only reachable by someone who already holds the account's session.
- L2, L3, L4, I1, I2, I4 and I5 remain as listed in P13.1. Production behaviour
  still depends on Redis (F4) for cross-worker counting.
