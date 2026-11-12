# Security Testing Guide

How to run, extend and interpret Tripora's security checks. Everything here runs **locally** against an in-memory SQLite app with Gemini, weather and email stubbed. No test contacts production or third-party APIs.

## 1. Run everything locally (Windows / PowerShell)

```powershell
cd C:\Users\odjoy\tripora

# Security regression suite (authn, authz/IDOR, JWT, rate limits, SQLi, input validation, audit PoCs)
backend\venv\Scripts\python -m pytest -q

# Backend unit tests
backend\venv\Scripts\python -m pytest backend -q -m "not integration"

# Dependency CVEs
backend\venv\Scripts\python -m pip install pip-audit bandit
backend\venv\Scripts\python -m pip_audit -r backend\requirements.txt

# Python SAST (fails on medium+)
backend\venv\Scripts\python -m bandit -r backend -x backend\migrations,backend\dev_scripts,backend\venv -ll

# Flutter
cd frontend
flutter analyze
flutter test                       # full suite
```

Semgrep has no native Windows build. Run it in Docker or WSL:

```bash
docker run --rm -v "$PWD:/src" semgrep/semgrep semgrep scan \
  --config p/python --config p/flask --config p/secrets --config p/jwt --config p/owasp-top-ten \
  --exclude backend/migrations --exclude frontend/build
```

### 1b. Integration suites (PostgreSQL runtime role + Redis)

These run the real app as the least-privilege DB role and the limiter against
a real Redis. They are skipped unless their env vars are set. Use disposable
local containers (Podman or Docker), bound to loopback:

```bash
podman run -d --name tripora-pg-test -e POSTGRES_USER=tripora_owner   -e POSTGRES_PASSWORD=local-test-only -e POSTGRES_DB=tripora_security_test   -p 127.0.0.1:55432:5432 docker.io/library/postgres:16-alpine
podman run -d --name tripora-redis-test -p 127.0.0.1:56379:6379 docker.io/library/redis:7-alpine

# migrate as owner, then create + grant the runtime role
cd backend
DB_USER=tripora_owner DB_PASSWORD=local-test-only DB_HOST=127.0.0.1 DB_PORT=55432 DB_NAME=tripora_security_test JWT_SECRET_KEY=local-only-0123456789abcdefghijkl GEMINI_API_KEY=dummy venv/Scripts/python -m flask --app wsgi db upgrade
podman exec tripora-pg-test psql -U tripora_owner -d tripora_security_test   -c "CREATE ROLE tripora_runtime LOGIN PASSWORD 'local-runtime-test-only';"
podman cp db/roles.sql tripora-pg-test:/tmp/roles.sql      # MSYS_NO_PATHCONV=1 in Git Bash
podman exec tripora-pg-test psql -U tripora_owner -d tripora_security_test   -v migrator=tripora_owner -f /tmp/roles.sql
cd ..

TRIPORA_PG_RUNTIME_URL=postgresql+psycopg://tripora_runtime:local-runtime-test-only@127.0.0.1:55432/tripora_security_test TRIPORA_TEST_REDIS_URL=redis://127.0.0.1:56379/15 backend/venv/Scripts/python -m pytest -q security/tests/test_postgres_runtime_role.py security/tests/test_redis_rate_limiter.py   security/tests/test_rls_runtime_role.py
```

CI runs the same steps in the `integration-postgres-redis` job (service
containers), including the full migration chain from an empty database.

### 1c. Browser verification of the CSP (manual, before enforcing)

1. `flutter build web --release --dart-define=API_BASE_URL=http://127.0.0.1:5051`
2. Run the backend locally on :5051 with `CORS_ORIGINS=http://127.0.0.1:5052`
   (email and AI must be stubbed/disabled; never use production keys).
3. Serve `build/web` on :5052 with the policy from `frontend/vercel.json` sent as
   an **enforcing** `Content-Security-Policy` header (API origin swapped to
   `http://127.0.0.1:5051`, `upgrade-insecure-requests` dropped for plain http).
4. In Chrome: load the app, register, verify, browse trips, delete the account.
   Listen for `securitypolicyviolation` events / console "Refused to ..." errors.
   The only expected violation is `accounts.google.com/gsi/client` (see report).

### 1d. Running the backend locally: local-only safety mode (required)

`backend/.env` points at the **production** database. Never start the backend
with it. Use local-only mode (`backend/config/local_safety.py`). It:
- never reads `backend/.env`;
- refuses any non-loopback `DB_HOST`, Neon included, before any connection;
- refuses the `flask` CLI unless `FLASK_SKIP_DOTENV=1`, because the CLI would auto-load `.env`;
- never sends e-mail.

One-time setup (Git Bash, repo root; the test container is from §1b):
```
cp backend/.env.local.example backend/.env.local     # gitignored; fill JWT_SECRET_KEY
podman exec tripora-pg-test psql -U tripora_owner -d tripora_security_test -c "CREATE DATABASE tripora_local"
```
Start (migrates `tripora_local`, then serves on http://127.0.0.1:5000):
```
bash backend/scripts/run_local.sh            # add --no-migrate to skip migrations
```
Stop: Ctrl+C in that terminal. If it runs in the background, stop the process
listening on port 5000. Values in the process environment override
`backend/.env.local`; `DB_HOST` is still checked.

Check: `curl http://127.0.0.1:5000/api/health` returns `"database":"connected"`.
Starting with `DB_HOST=<anything>.neon.tech` must fail with `LocalSafetyError`.
`security/tests/test_local_safety.py` covers all of this.

### 1e. Turnstile end-to-end with a development widget (manual)

Cloudflare's dummy keys do not return `action`, so a genuine token can only be
tested with a real widget.
1. Cloudflare → Turnstile → Add widget:
   - mode Managed;
   - hostname `localhost` only;
   - never reuse the production widget.
2. Put its keys into `backend/.env.local` yourself: `TURNSTILE_SITE_KEY`,
   `TURNSTILE_SECRET_KEY`, `TURNSTILE_ALLOWED_HOSTNAMES=localhost`,
   `TURNSTILE_ENABLED=true`.
3. Start the backend (§1d) and serve a web build:
   ```
   flutter build web --release --dart-define=API_BASE_URL=http://localhost:5000
   ```
   Serve `frontend/build/web` on http://localhost:3000. The host must be
   `localhost`, not `127.0.0.1`: the widget only allows `localhost`.
4. Android: start the app with `--dart-define=API_BASE_URL=http://localhost:5000`
   and run `adb reverse tcp:5000 tcp:5000`, so the challenge page's hostname is
   `localhost`.
5. Rejection cases that need a genuine token:
   - **Wrong action:** solve on forgot-password, send that token to `/register`; expect `action_mismatch`.
   - **Wrong hostname:** restart with `TURNSTILE_ALLOWED_HOSTNAMES=example.org`; expect `hostname_mismatch`.
   - **Reuse:** send the same token twice; the second gets `expired_or_reused`.
   - **Expiry:** keep an unused token for more than 300 s, then send it; expect `expired_or_reused`.

### 1f. Flutter browser tests on Windows

`flutter test --platform chrome` hangs on Windows (Flutter 3.44.8). The test
server's CanvasKit handler answers 404 for backslash paths. Workaround, then
remove the copy (never commit it):
```
C=/c/flutter/bin/cache/flutter_web_sdk/canvaskit
mkdir -p frontend/test/canvaskit/chromium
cp $C/canvaskit.js $C/canvaskit.wasm frontend/test/canvaskit/
cp $C/chromium/canvaskit.js $C/chromium/canvaskit.wasm frontend/test/canvaskit/chromium/
(cd frontend && flutter test --platform chrome test/turnstile_web_test.dart)
rm -r frontend/test/canvaskit
```

## 2. What the suites cover

| File (`security/tests/`) | Area |
|---|---|
| `test_audit_remediation.py` | One test per finding in `SECURITY_AUDIT_REPORT.md` (TRP-01…13), plus guards: every bucket names a real endpoint, every endpoint gets a budget, password policy, proxy trust boundary |
| `test_jwt_authentication.py`, `test_jwt_token_validation.py` | `alg=none`, algorithm confusion, forged signatures, expiry, malformed `sub`, token_version revocation |
| `test_refresh_tokens.py` | Rotation, reuse detection (family revocation), logout, expiry |
| `test_authorization_idor.py`, `test_idor_user_a_b.py`, `test_idor_extended.py` | Cross-user access to trips, expenses, weather, swap, regenerate |
| `test_password_reset*.py` | Code lifetime, lockout, single-use token, races |
| `test_rate_limiting.py` | 429 shape, per-user/per-IP keying, env config |
| `test_sql_injection*.py` | Injection payloads through every query path |
| `test_input_validation.py`, `test_generate_trip_input.py` | Types, lengths, ranges, body size |
| `test_error_handling.py`, `test_info_disclosure_fixes.py` | No stack traces or internals in responses |
| `test_google_social_auth.py` | Server-side token verification, no auto-linking, unverified email rejected |
| `test_phase2_hardening.py` | Email verification (gate, single use, lockout, expiry, resend cooldown, enumeration-safe register, squatter eviction), re-authenticated deletion (all owned rows, FK enforcement, social re-auth freshness), admin accounts + TOTP (RFC 6238 vectors, enrollment window, replay, recovery codes, idle timeout, revocation, legacy flag, audit), proxy/IP resolution (spoof, hops, malformed, IPv6 /64), limiter failure modes, AI global budget, refresh-rotation race, CSP report endpoint |
| `test_redis_rate_limiter.py` *(opt-in)* | Shared counters across "workers", restart persistence, atomicity under 60 threads, TTL, outage fallback/closed modes |
| `test_rls_runtime_role.py` *(opt-in, integration)* | RLS on all 10 user-associated tables proven as the `tripora_runtime` login: anonymous, cross-user read/update/delete, 11 unauthorized writes, admin context, single-connection pool leakage (commit/rollback/error), API spoofing, CLI contexts, full feature matrix. A run as the owner is refused by design. |
| `test_postgres_runtime_role.py` *(opt-in, integration)* | Runtime role cannot run DDL / read `alembic_version` / rewrite audit log / disable RLS; RLS fails closed; full user + admin flows under the runtime role |

**Rate limits in tests:** `conftest.py` disables rate limiting for the general suite. Tests that exercise limits must opt in. Use the `production_limits` fixture in `test_audit_remediation.py`, which loads the real `Config.rate_limit_buckets()`, or configure buckets explicitly as `test_rate_limiting.py` does.

**Foreign keys:** SQLite does not enforce FKs unless `PRAGMA foreign_keys=ON` is set, and PostgreSQL always enforces them. Any test of deletion paths should turn the pragma on; see `test_trp07_*`.

**Verified users in tests:** `helpers.create_logged_in_user` registers, logs in and completes email verification through the real API; `conftest.capture_verification_emails` records the codes instead of sending them (`helpers.last_verification_code`). Use `helpers.delete_account` (sends the password) for deletion.

**Flutter widget tests and secure storage:** inside `testWidgets` the secure-storage plugin's platform I/O never completes (fake-async zone). Set `TokenStore.debugForceSecureStorage = false` (memory-only) in widget tests that touch the session, as `login_gate_test.dart` and `layout_probe_test.dart` do; otherwise the test hangs.

**External DB:** `TRIPORA_TEST_DB_URI` can point at a *disposable* Postgres database to exercise RLS. `conftest.py` refuses non-disposable names. Never point it at production.

## 3. Writing a new security test

1. Write the test **first**. It must fail on the vulnerable code.
2. Use only synthetic users (`helpers.create_logged_in_user`) and `@example.com` addresses.
3. Assert on **behaviour** (status code, data visible, row state), not on implementation details.
4. Fix the code and watch the test pass. Then run the full suite.
5. Reference the finding ID in the test name or docstring.

## 4. Manual checks before a release

- [ ] `CORS_ORIGINS` in Render lists only the production web origin(s).
- [ ] `JWT_SECRET_KEY` and `ADMIN_API_TOKEN` are ≥ 32 random characters (no startup warning in the Render logs).
- [ ] `FLASK_DEBUG` is not set; the start command is `gunicorn … wsgi:app`.
- [ ] `curl -I https://<api>/api/health` shows `Strict-Transport-Security`, `X-Content-Type-Options`, `Content-Security-Policy`.
- [ ] `curl -I https://<web>` shows HSTS, `X-Frame-Options`, `Referrer-Policy`.
- [ ] Release Android build is signed with the upload key, not the debug key.
- [ ] Provider consoles (Gemini, Travelpayouts, Duffel) have spend or quota caps.
- [ ] Dependabot PRs and the weekly workflow run are green.

## 5. Baselines

- **OWASP ASVS 4.0.3, Level 2**: target for authentication (V2), session management (V3), access control (V4), validation (V5), error handling and logging (V7), API (V13).
- **OWASP API Security Top 10 (2023)**: API1 BOLA → IDOR suites. API2 broken auth → JWT/refresh/reset suites. API4 resource consumption → rate-limit guards. API5 function-level authz → admin tests. API8 misconfiguration → headers/debug checks.

A green run means these specific checks passed. It does not mean the application has no vulnerabilities.
