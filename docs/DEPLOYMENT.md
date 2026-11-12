# Tripora Deployment Runbook

Free-tier production stack:

- **Frontend (Flutter web)** → [Vercel](https://vercel.com) (static hosting, free, no expiry)
- **Backend (Flask API)** → [Render](https://render.com) web service (free compute)
- **Database (PostgreSQL)** → [Neon](https://neon.tech) or [Supabase](https://supabase.com) (free tier, persistent — no 30-day expiry)

> Render's free **Postgres** database self-destructs after 30 days. For anything
> with real users, us a free persistent Postgres from **Neon** or **Supabase**
> instead. This backend was ported from MySQL to PostgreSQL (`psycopg` v3) to
> support exactly this setup.

---

## 1. Database — Neon (or Supabase)

1. Create a Neon account and a new **Project** (choose the nearest region).
2. Copy the **connection string** — it looks like:
   `postgresql://user:password@ep-xxxx.aws.neon.tech/neondb?sslmode=require`
3. Break it into these env values (the backend builds the URI from parts):

   | Env var | Value from the connection string |
   |---------|----------------------------------|
   | `DB_USER` | `user` (before the `:`) |
   | `DB_PASSWORD` | `password` (between `:` and `@`) |
   | `DB_HOST` | host, e.g. `ep-xxxx.aws.neon.tech` |
   | `DB_PORT` | `5432` |
   | `DB_NAME` | database name, e.g. `neondb` |

   The URI is assembled as `postgresql+psycopg://user:password@host:5432/dbname`.

> Supabase: same idea, use `DATABASE_URL`-style Postgres creds + `?sslmode=require`.

---

## 2. Backend — Render web service (free)

1. Push the `backend/` folder to a Git repo (GitHub).
2. In Render: **New → Web Service**, connect the repo, set Root Directory to `backend`.
3. Settings:
   - **Build Command**: `pip install -r requirements.txt`
   - **Start Command**: `gunicorn --bind 0.0.0.0:5000 --workers 2 --timeout 120 wsgi:app`
   - **Instance Type**: Free
4. **Environment** tab — add the DB values from step 1, plus:
   - `JWT_SECRET_KEY` = a long random string (>= 32 chars)
   - `MFA_ENCRYPTION_KEY`, `REDIS_URL`, `DB_MIGRATION_USER`,
     `DB_MIGRATION_PASSWORD` — see "Security architecture (phase 2)" below
   - `CORS_ORIGINS` = `https://<your-vercel-app>.vercel.app` (your frontend origin; comma-separate multiple)
   - `GOOGLE_CLIENT_ID_WEB`, `GOOGLE_CLIENT_ID_ANDROID`, `GOOGLE_CLIENT_ID_IOS`, `APPLE_CLIENT_ID` as needed
   - `RATE_LIMIT_ENABLED` = `true`
   - `FLASK_APP` = `app` — needed for the `flask db` migration CLI
   - `DUFFEL_API_TOKEN` = `…` (server-only; leave **unset** to make the
     stay/car travel search fail closed)
   - `TRAVELPAYOUTS_API_KEY` = `…` (server-only; flight prices fail closed when
     unset)

5. On first deploy, run migrations **once** against the production DB. Do this
   **after** the web service is up. Either:
   - **From Render's Shell tab** (your service → **Shell**), then:
     ```
     flask db upgrade
     ```
   - **Or from your local machine** against the production DB (often easier for
     a first setup). With `DB_*` env vars pointing at your Neon/Supabase DB:
     ```
     cd backend
     .\venv\Scripts\python -m flask --app app db upgrade
     ```
   - Migrations are **not** run automatically at boot (they'd race on scale-ups).
   - If any Render command runs `flask db upgrade` (see "Security architecture
     (phase 2)" a.), **every migration applied to production must be
     committed** before the next deploy. A commit whose newest migration is
     older than the database's `alembic_version` fails to deploy with
     `Can't locate revision identified by '…'`. This happened on 2026-11-12
     when `d5e6f7a8b9c0` and its four predecessors had been applied but not
     committed. Render appears to skip auto-deploys for commits that change
     nothing under `backend/` (Root Directory): on 2026-11-12 it was still
     running `8b6974f` while `main` was at `c543a43` (frontend-only commits).
   - Note: `gunicorn` is pinned in `backend/requirements.txt`, so it installs
     automatically during the Render build. The start command is in `Procfile`.

### Security architecture (phase 2) — required production setup

These steps change production configuration. Each one needs the owner's
explicit go-ahead; none is performed automatically.

**a. Migrations run as the owner, in a pre-deploy step, before new code.**
Render → service → Settings → *Pre-Deploy Command*:
```
DB_USER=$DB_MIGRATION_USER DB_PASSWORD=$DB_MIGRATION_PASSWORD flask --app wsgi db upgrade
```
Set `DB_MIGRATION_USER` / `DB_MIGRATION_PASSWORD` (the Neon owner, e.g.
`neondb_owner`) in the service environment. The web process itself keeps
`DB_USER` / `DB_PASSWORD` = the runtime role (step b). Revision
`a9b8c7d6e5f4` adds email-verification columns, `users.role`, admin MFA/session/
audit tables, `ON DELETE CASCADE` on refresh tokens and NULL-safe RLS policies;
it is backward compatible (existing accounts keep `email_verified` as stored and
get `role='user'`).

**b. Least-privilege runtime role.** Create `tripora_runtime` with **SQL** in
the Neon SQL editor (database `tripora`, as the owner) — **not** via Console →
Roles: console/API roles become members of `neon_superuser`, which has
`BYPASSRLS` and would silently disable Row-Level Security again.
```
CREATE ROLE tripora_runtime LOGIN PASSWORD '<long random value>';
```
Then, as the owner:
```
psql "$OWNER_URL" -v migrator=neondb_owner -f backend/db/roles.sql
```
Switch the web service's `DB_USER`/`DB_PASSWORD` to `tripora_runtime`. The
runtime role has DML only, no DDL, no `BYPASSRLS`, and is subject to every RLS
policy; it cannot touch `alembic_version` or rewrite `admin_audit_log`.
Expected result (rehearsed on a Neon branch on 2026-11-10): `tripora_runtime`
has no superuser/createdb/createrole/replication/bypassrls and no role
memberships. Note that `neondb_owner` itself has `BYPASSRLS`, so until the web
service runs as `tripora_runtime`, RLS is not enforced at all in production.
Rollback: point `DB_USER`/`DB_PASSWORD` back at the owner.

**c. Redis for rate limits.** Create a Render *Key Value* instance in the same
region, copy its **internal** URL into `REDIS_URL`. Keep
`RATE_LIMIT_FAILURE_MODE=fallback` unless you prefer auth/admin/AI to return
503 during a Redis outage (`closed`). Without `REDIS_URL` the app logs an
error on Render and limits are per worker.

**d. Email verification.** New accounts must confirm a 6-digit emailed code
before using trips/AI/expenses/travel/weather. Email delivery (SMTP or
`RESEND_API_KEY`) is therefore **required** for sign-up. Existing accounts are
unaffected.

**e. Administrators (replaces the shared `ADMIN_API_TOKEN`).**

Administration is **backend-only**. The Flutter app has no admin screens; old
app versions' stored `admin_token` is deleted from the browser at app start.
Admins use the API (below) and the `flask admin` CLI. Never put the shared
token or an admin session token in the Flutter app or browser storage.

Provisioning the first administrator:
1. Set `MFA_ENCRYPTION_KEY` (Fernet key; see `backend/.env.example`). Keep it
   in a password manager: losing it forces every admin to re-enroll.
2. The future admin signs up normally in the app and verifies their email.
3. Operator, in Render → Shell: `flask --app wsgi admin grant <email>`
   (sets `role=admin`, opens a 24 h TOTP enrollment window; prints no
   secrets). Check with `flask --app wsgi admin list`.
4. The admin enrolls TOTP from their own machine. Keep the password out of
   shell history by putting the request body in a file that only they can read,
   and delete it afterwards:
   ```
   # login.json: {"email": "<email>", "password": "<password>"}
   curl -s -X POST https://<api>/api/admin/auth/login \
        -H "Content-Type: application/json" -d @login.json
   #  -> {"pendingToken": "...", "mfaEnrolled": false}
   curl -s -X POST https://<api>/api/admin/auth/mfa/setup \
        -H "Content-Type: application/json" -d '{"pendingToken":"<pending>"}'
   #  -> {"secret": "...", "otpauthUri": "otpauth://..."}  add to an authenticator app
   curl -s -X POST https://<api>/api/admin/auth/mfa/activate \
        -H "Content-Type: application/json" \
        -d '{"pendingToken":"<pending>","code":"<6 digits>"}'
   #  -> {"sessionToken": "...", "recoveryCodes": [10 codes]}  store the codes offline
   ```
   Clear the terminal afterwards: the setup secret and recovery codes are
   shown once.
5. Later sign-ins: `/login`, then `/mfa/verify` with `{"pendingToken", "code"}`
   (or `"recoveryCode"`). Use the returned session token as
   `Authorization: Bearer <session>` on `/api/admin/*`; end it with
   `POST /api/admin/auth/logout`.
6. Verify: `GET /api/admin/auth/me` returns the admin, and `admin_audit_log`
   shows `access` rows with that admin's `user_id`.
7. Only after step 6 succeeds: set `ADMIN_LEGACY_TOKEN_ENABLED=false`, then
   remove `ADMIN_API_TOKEN`. Until then the legacy token keeps working (every
   use is logged as a warning and audited as `legacy_token_access`).

Other commands: `admin list`, `admin reset-mfa <email>` (lost device),
`admin revoke <email>`, `admin revoke-sessions <email>`.

**f. Content Security Policy.** `frontend/vercel.json` ships the policy as
`Content-Security-Policy-Report-Only`, reporting to `/api/csp-report`
(violations appear as `CSP violation:` warnings in the Render log). It was
verified locally in Chrome in **enforcing** mode (see
`SECURITY_HARDENING_REPORT.md`). After a week of clean production reports,
rename the header to `Content-Security-Policy`. If the API domain changes,
update the API origin in both `connect-src` and `report-uri`.

**g. Bot protection: Cloudflare Turnstile + honeypot** (`POST /api/auth/register`,
`POST /api/auth/forgot-password`).

*Protection is ON by default in every deployed environment.* Once this code is
deployed without the keys below, those two endpoints answer **503** until the
keys exist, or until you explicitly set `TURNSTILE_ENABLED=false`. That
setting is logged as a warning at every start-up.

1. Cloudflare dashboard → Turnstile → *Add widget* (owner action):
   - widget mode **Managed**;
   - hostnames: **exactly** `tripora-iota.vercel.app` (web app) and
     `tripora-4mt3.onrender.com` (API; it serves the Android challenge page).
     Do not add `localhost` to this production widget.
   - Vercel preview URLs and any future custom domain are **not** covered:
     the widget will not render there, and the backend rejects their tokens
     (`hostname_mismatch`) until the host is added in Cloudflare and in
     `TURNSTILE_ALLOWED_HOSTNAMES`.
2. Render (web service). Set:

   | Variable | Value | Notes |
   |---|---|---|
   | `TURNSTILE_SITE_KEY` | the widget's site key | Public; served by `/api/turnstile/config`. |
   | `TURNSTILE_SECRET_KEY` | the widget's secret key | Server-only. Never in Vercel, the app, or chat. |
   | `TURNSTILE_ALLOWED_HOSTNAMES` | `tripora-iota.vercel.app,tripora-4mt3.onrender.com` | Without it the backend skips its hostname check (start-up warning). |
   | `TURNSTILE_ENABLED` | leave **unset** | `false` is an explicit, logged off-switch, used only during rollout or rollback (below). |
   | `TURNSTILE_TIMEOUT_SECONDS` | leave unset (5) | Range 1–10. |
   | `TRIPORA_ENV` | leave **unset** | `development`/`test` turn Turnstile off by default and simulate e-mail. |
   | `CORS_ORIGINS` | must include `https://tripora-iota.vercel.app` | Only if this variable is set; the built-in default already includes it. |

3. Vercel: nothing to set. The app reads the public site key from
   `GET /api/turnstile/config`. `frontend/vercel.json` already allows
   `https://challenges.cloudflare.com` in `script-src`, `frame-src` and
   `connect-src` (the CSP is still report-only).
4. Coordinated rollout. An app build without Turnstile sends no token, so the
   backend will reject its sign-ups and password resets once enforcement is on.
   The Turnstile code ships with the rest of the uncommitted security work in a
   single commit. It slots into the deployment sequence in
   `SECURITY_HARDENING_REPORT.md` §P6.5:
   - step 1 below belongs to step A;
   - step 2 belongs to steps B and C. Pushing `main` deploys the backend. Vercel
     redeploys too, but only if it is un-paused;
   - step 3 belongs to step D;
   - step 4 is a new step after step E, once E passes with Turnstile still off;
   - the runtime-role cutover (step F) is independent and comes after.

   Steps:
   1. Create the widget (step 1). Set the Render variables from step 2, **plus**
      `TURNSTILE_ENABLED=false` for the transition. This is today's behaviour:
      production currently has no Turnstile at all.
   2. Deploy the backend. Check that `GET /api/turnstile/config` answers
      `{"enabled": false, ...}` and that the log shows the
      `TURNSTILE_ENABLED=false` warning.
   3. Deploy the web app (Vercel) and build or publish the Android app from
      the same commit.
   4. Delete `TURNSTILE_ENABLED` on Render, which redeploys the service.
      `GET /api/turnstile/config` must now return `"enabled": true` and the
      site key. The start-up log must show no Turnstile error or warning.
   5. Smoke test (below). Installed Android builds older than this release
      cannot sign up or reset passwords any more; they must update.
5. Smoke test after enforcement (use your own test addresses):
   - Web and Android: sign up, and request a password reset. Both must succeed.
     Successful checks are not logged. Every failure is logged as
     `Turnstile verification failed: reason=<reason> action=<action> codes=<codes>`
     (never the token).
   - Expected log for a broken setup:
     - `action_mismatch`: a test key, or a client sending the wrong action;
     - `hostname_mismatch`: a host missing from `TURNSTILE_ALLOWED_HOSTNAMES`;
     - `unavailable` with `invalid-input-secret`: a wrong secret key.
   - A request without a token must fail with 400 `turnstile_failed`, e.g.
     `curl -s -X POST https://tripora-4mt3.onrender.com/api/auth/forgot-password -H "Content-Type: application/json" -d '{"email":"<your test address>"}'`.
     This is safe: no code is issued.
   - **E-mail limitation:** while `RESEND_FROM_EMAIL` is Resend's testing sender
     (`onboarding@resend.dev`), Resend delivers **only to the Resend account
     owner**. Sign-up verification codes and password-reset codes do **not**
     reach other people, so public sign-up and password reset are not usable,
     whatever the Turnstile status. Verify a sending domain in Resend and set
     `RESEND_FROM_EMAIL` to an address on it before opening sign-up to the
     public.
6. Rollback (fastest first):
   - Sign-ups or resets fail because of Turnstile (log reasons above):
     1. fix the key or hostname variable;
     2. if that is not possible quickly, set `TURNSTILE_ENABLED=false` on
        Render. This removes the bot check (rate limits and the honeypot
        stay), is logged at every start-up, and must be removed again once
        fixed.
   - Code problem: redeploy the previous Render deploy. A backend without
     Turnstile ignores the extra `turnstileToken`/`website` fields, so the new
     web app keeps working, minus the protection. Roll the web app back in
     Vercel only if the web build itself is at fault. Keep `LOG_LEVEL=INFO`:
     the older backend's DEBUG request log does not redact `turnstileToken`.
   - No database migration is involved, so no database rollback is needed.
7. Local end-to-end testing needs a **separate development widget**. Cloudflare's
   dummy keys do not return `action` (and report the hostname `example.com`),
   so this backend correctly rejects them with `action_mismatch`. Create a
   second Managed widget whose hostnames include `localhost`, and use its keys
   only in your local environment.

How it works:
- **Web:** Cloudflare's widget is rendered in the form. Next to it is a hidden
  `website` input: a honeypot that is off-screen through a CSS rule in
  `web/index.html` and out of the tab and accessibility order.
- **Android:** a WebView opens the backend page
  `GET /api/turnstile/challenge?action=…`. It has a strict nonce-based CSP,
  only that page may load as the top-level page, and file and content access
  are off. The page hands the token back through a JavaScript channel.
- **Backend** (`services/bot_protection.py`, `services/turnstile.py`):
  - the rate limit runs first;
  - a filled honeypot gets the normal generic success response and nothing
    happens;
  - the token is checked with Siteverify (success, action, hostname, 5 s
    timeout);
  - a failed check returns 400 `turnstile_failed`; Cloudflare unreachable or
    keys missing returns 503 `turnstile_unavailable`;
  - no account is created and no reset code is issued unless the checks pass.

### Runbook: switching production to `tripora_runtime`

Each step needs the owner's go-ahead. Do them in this order, verifying each step before starting the next.

**Current state (2026-11-12)**
- Production schema is at `d5e6f7a8b9c0` (step 1 done on 2026-11-12). RLS is enabled on all 10 application tables (31 policies).
- `tripora_runtime` exists and its password has been set by the owner (step 2 done). The role is still unused.
- The app still connects as `neondb_owner`, which has BYPASSRLS, so RLS is not enforced yet.
- Runtime-role cutover (steps 3–5) is pending.
- Backup branches: `backup-before-security-migration-2026-11-10` (before `a9b8c7d6e5f4`) and `backup-before-rls-d5e6f7a8b9c0-2026-11-12` (before `d5e6f7a8b9c0`).

#### Environment variables (Render web service)

| Variable | During steps 1–3 | From step 4 on |
|---|---|---|
| `DB_USER` | `neondb_owner` (unchanged) | `tripora_runtime` |
| `DB_PASSWORD` | owner password (unchanged) | runtime password (set in step 2) |
| `DB_HOST` | unchanged: production endpoint, pooled host `ep-…-pooler.…neon.tech` | unchanged |
| `DB_PORT` / `DB_NAME` | `5432` / `tripora` | unchanged |
| `DB_SSLMODE` | `require` (default for remote hosts) | unchanged |
| `DB_MIGRATION_USER` / `DB_MIGRATION_PASSWORD` | not needed yet | `neondb_owner` / owner password, used **only** by the pre-deploy command |

The app builds this connection string from the parts above (`config/settings.py`); there is no `DATABASE_URL`:

```
postgresql+psycopg://<DB_USER>:<url-encoded DB_PASSWORD>@<DB_HOST>:<DB_PORT>/<DB_NAME>?sslmode=require
```

#### Step 1. Apply migration `d5e6f7a8b9c0` (RLS on the remaining tables)

- It is safe while the app still runs as the owner, because the owner bypasses RLS.
- Review the SQL first: `backend/db/upgrade_a9b8c7d6e5f4_to_d5e6f7a8b9c0.sql`.
- Run it as the owner, either:
  - `flask --app wsgi db upgrade` with owner credentials, or
  - the SQL file in one transaction.
- Then check `SELECT version_num FROM alembic_version` returns `d5e6f7a8b9c0`.
- Then confirm these 10 tables show `relrowsecurity = true`:
  ```
  SELECT relname, relrowsecurity, relforcerowsecurity
  FROM pg_class WHERE relrowsecurity ORDER BY 1;
  ```
- Rollback: `backend/db/rollback_d5e6f7a8b9c0_to_a9b8c7d6e5f4.sql`.

#### Step 2. Set the runtime password (you, in the Neon SQL editor, database `tripora`)

- Run:
  ```
  ALTER ROLE tripora_runtime PASSWORD '<long random value>';
  ```
- Generate the value in a password manager (32+ random characters). Do not put it in files, chat or tickets.
- Store it only in the password manager and in Render's `DB_PASSWORD` (step 4).
- Re-check the role:
  ```
  SELECT rolbypassrls, rolsuper FROM pg_roles WHERE rolname = 'tripora_runtime';
  ```
  Both must be `false`.

#### Step 3. Deploy the new code, still on the owner credentials

1. Commit and merge the `security-hardening` branch, then let Render deploy.
2. Set the other new variables (`MFA_ENCRYPTION_KEY`, `REDIS_URL`, …; see "Security architecture (phase 2)" above).
3. Do **not** change `DB_USER` yet.
4. Verify:
   - `/api/health` returns 200;
   - sign-up, verification and login work;
   - trips and expenses work.

   The new code works under both roles; under the owner, RLS is simply not enforced yet.

#### Step 4. Switch to the runtime role

1. In Render → Settings, check **all three** commands: Build, Pre-Deploy and Start. Remove `flask db upgrade` from the Build and Start commands if it appears there. Expected afterwards:
   - Build: `pip install -r requirements.txt`
   - Start: `gunicorn --bind 0.0.0.0:5000 --workers 2 --timeout 120 wsgi:app`

   `tripora_runtime` has no access to `alembic_version` and cannot run DDL. Any migration command that runs with the web credentials fails after this switch, and the deploy fails with it.
2. Set `DB_MIGRATION_USER` / `DB_MIGRATION_PASSWORD` to the owner credentials.
3. Set the Pre-Deploy command (the only place migrations run, always as the owner):
   `DB_USER=$DB_MIGRATION_USER DB_PASSWORD=$DB_MIGRATION_PASSWORD flask --app wsgi db upgrade`
4. In Render, set `DB_USER=tripora_runtime` and `DB_PASSWORD=<runtime password>`.
5. Save. Render redeploys: the pre-deploy step runs as the owner (a no-op at the current head), then the web process starts as `tripora_runtime`.

#### Step 5. Post-switch verification (within 15 minutes)

1. `curl https://<api>/api/health` → `{"database":"connected"}`.
2. Confirm the app really connects as the runtime role:
   ```
   SELECT usename, count(*) FROM pg_stat_activity WHERE datname = 'tripora' GROUP BY 1;
   ```
   Expect `tripora_runtime`.
3. In the app, as a test account:
   - register, verify the email, log in;
   - create a trip, add an expense, open weather;
   - log out, log back in;
   - delete a throwaway account.
4. Admin: sign in with MFA; stats show all users (via the admin-read policy).
5. Watch the Render logs for `InsufficientPrivilege` / `row-level security` errors. There should be none.

#### Rollback (any time after step 4)

- **Immediate:** set `DB_USER` / `DB_PASSWORD` back to the owner in Render. The app resumes without RLS. No data change is needed.
- **Schema:**
  - `backend/db/rollback_d5e6f7a8b9c0_to_a9b8c7d6e5f4.sql` undoes step 1;
  - `backend/db/rollback_a9b8c7d6e5f4_to_0922f2fc8de9.sql` undoes the 2026-11-10 migration. Only use it together with redeploying the old code.
- **Data:** restore from branch `backup-before-rls-d5e6f7a8b9c0-2026-11-12` (state just before `d5e6f7a8b9c0`), `backup-before-security-migration-2026-11-10` (before `a9b8c7d6e5f4`), or Neon point-in-time restore.
- **Code:** set `DB_USER` / `DB_PASSWORD` back to the owner first. Then roll back only to a commit that **contains every migration file up to the production revision** (`d5e6f7a8b9c0` today). Any older commit fails to deploy whenever Render runs `flask db upgrade` (build, pre-deploy or start command) with `Can't locate revision identified by '<prod revision>'`, because Alembic cannot find the database's current revision in that commit's `migrations/versions`. On 2026-11-12 this was every commit up to and including `c543a43`; the first safe rollback target is the commit that adds `b7c1d2e3f4a5`, `c8d2e3f4a5b6`, `e1f2a3b4c5d6`, `a9b8c7d6e5f4` and `d5e6f7a8b9c0`. No schema change is needed for such a rollback: application code from `8b6974f` onward runs on schema `d5e6f7a8b9c0` as the owner.
- **Never** fix a "Can't locate revision" error by stamping or downgrading production. Commit the missing migration files instead.

#### Notes on pooling

- `DB_HOST` uses Neon's PgBouncer pooler in transaction mode. This is safe with the RLS design: identity is set with `set_config(..., true)`, which is transaction-local, and it is re-applied at the start of every transaction (`services/db_context.py`).
- Nothing is set at session level, so nothing can survive on a pooled server connection.
- `tripora_runtime` is limited to 40 connections. Two Gunicorn workers × SQLAlchemy's default pool (5 + 10 overflow) = at most 30.

### Backend notes
- Uses `wsgi.py` as the WSGI entrypoint (the `python app.py` dev server is only for local dev).
- In-memory rate limiter is single-instance; keep `--workers 2` on one free instance (fine for a hobby app). For horizontal scaling you'd back it with Redis.
- Health check: `GET /api/health` and `GET /`.
- Row-Level Security: a migration (`f0e9d8c7b6a5`) enables Postgres RLS with
  per-user ownership policies on `trips` (forced) and a per-user policy on
  `users` (not forced, so unauthenticated flows still work). The feature
  migration (`3e2d1c0b9a87`) adds the Expense tracker (`trip_expenses`,
  RLS-owned), the password-reset columns on `users`, and `trips.budget_amount`.
  The app sets the authenticated user id into the `request.jwt.claims.sub` GUC
  per request (`SET LOCAL`) so the database enforces ownership too. RLS fails
  closed whenever the GUC is unset. Applying the migrations via
  `flask db upgrade` is required for the constraints to take effect.

### Email + password reset (server-side only)

Verification **and password-reset** emails are sent over **SMTP** using the
Python standard library (`services/email_service.py`) — no extra dependency.
When no provider is configured, delivery fails closed: the code is **not**
sent and is **never** written to the log (a logged code would let anyone with
log access reset that account).

The forgot-password flow (`/api/auth/forgot-password` → code → verify → reset)
uses a **6-digit code** (15 min, max 5 attempts with lockout) followed by a
one-time `resetToken` (30 min). Codes and tokens are stored **hashed**; the API
always answers with the same generic message so it cannot be used to probe
which accounts exist. The flow depends on a working email provider (SMTP or
Resend); without one, password reset is unavailable.

| Env var | Example | Notes |
|---------|---------|-------|
| `MAIL_HOST` | `smtp-relay.brevo.com` | SMTP server (Brevo-ready; any SMTP provider works) |
| `MAIL_PORT` | `587` | `587` = STARTTLS, `465` = implicit SSL |
| `MAIL_USER` | your SMTP login / key | e.g. Brevo SMTP key |
| `MAIL_PASSWORD` | your SMTP key/secret | |
| `MAIL_FROM` | `gotripora@gmail.com` | Sender address — must be **confirmed** in the provider. Use a personal email during testing, a domain sender later. |
| `MAIL_FROM_NAME` | `Tripora` | Optional display name |
| `MAIL_USE_TLS` | `tls` | `tls` (587) or `ssl` (465); defaults infer from port |

> Brevo is the recommended provider to start because it lets you send from a
> **confirmed personal email** without owning a custom domain. To use another
> provider, only change `MAIL_HOST`/`MAIL_PORT`/`MAIL_USER`/`MAIL_PASSWORD`/
> `MAIL_FROM` — no code changes needed.

### Expense tracker

`Trip.budget_amount` and the user's `preferred_currency` drive the in-app
Expense tracker. No server config is required. Expense rows are RLS-protected
and owned by the trip's owner.

---

## 3. Frontend — Vercel (free)

1. Push the `frontend/` folder to Git.
2. In Vercel: **Add New → Project**, connect the repo, Root Directory = `frontend`.
3. The `frontend/vercel.json` handles everything — Vercel's build container has
   **no Flutter SDK**, so the **install command** clones the Flutter stable SDK
   and the **build command** uses it:
   - Install: `git clone --branch stable --depth 1 .../flutter.git && flutter/bin/flutter config --enable-web`
   - Build: `flutter/bin/flutter build web --release --dart-define=...`
   - Output dir: `build/web` (already set), plus SPA rewrites to `index.html`.
4. **Build Environment Variables** (used by the `--dart-define` in the build
   command; if unset they fall back to the same defaults as the code):
   - `API_BASE_URL` → your Render backend URL, e.g. `https://tripora-api.onrender.com`
   - (Optional) Google web OAuth ID for Google sign-in on web: `GOOGLE_WEB_CLIENT_ID`

   > Note: `--dart-define` values are baked in at build time, so set these in the
   > Vercel project's **build** environment variables **before** deploying.

5. Deploy. Your site is live at `https://<project>.vercel.app`.
   Adding a custom domain later is supported (Vercel → Settings → Domains); no
   rebuild is required unless you also change `API_BASE_URL`.

---

## 4. Connect frontend ↔ backend

- The web app calls `API_BASE_URL`.
- The backend must allow your web origin via `CORS_ORIGINS` (Render env var).
- If you add a custom domain later, update `CORS_ORIGINS` and rebuild the web
  app with the new `API_BASE_URL`.

---

## Local development

The backend `.env` still contains MySQL-era defaults (e.g. `DB_PORT=3306`). For
local Postgres dev, update `.env` to `DB_PORT=5432` and point the DB host at a
local Postgres (or your Neon/Supabase instance). The driver is `psycopg` v3
(`psycopg[binary]==3.3.4`), already installed in `backend/venv`.

Run the backend locally:

```
cd backend
venv\Scripts\python -m flask db upgrade
venv\Scripts\python app.py
```

---

## Mobile (App Store / Google Play)

Web uses Vercel + Render + Neon. Mobile is a separate release tracked in the
audit: Android keystore → `frontend/android/key.properties`, iOS Apple Team ID,
and real Google OAuth client IDs. Those are out of scope of this runbook.
