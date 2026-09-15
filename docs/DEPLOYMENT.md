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
   - `JWT_SECRET_KEY` = a long random string
   - `CORS_ORIGINS` = `https://<your-vercel-app>.vercel.app` (your frontend origin; comma-separate multiple)
   - `GOOGLE_CLIENT_ID_WEB`, `GOOGLE_CLIENT_ID_ANDROID`, `GOOGLE_CLIENT_ID_IOS`, `APPLE_CLIENT_ID` as needed
   - `RATE_LIMIT_ENABLED` = `true`
   - `FLASK_APP` = `app` — needed for the `flask db` migration CLI
   - (`DUFFEL_API_TOKEN` — leave **unset** for the free-only v1; the premium travel
     search is disabled behind a build flag and this token is only read server-side.)

### Trip Vault document storage (S3-compatible object store)

Trip documents are stored in an S3-compatible object store, **not** on Render's
local filesystem (that resets on every redeploy). Create a private bucket (e.g.
on **Cloudflare R2**, **Backblaze B2**, or **AWS S3**), then add:

| Env var | Example | Notes |
|---------|---------|-------|
| `STORAGE_BACKEND` | `s3` | Explicit; also auto-selected when `S3_BUCKET`+`S3_ACCESS_KEY`+`S3_SECRET_KEY` are set. |
| `S3_BUCKET` | `tripora-vault` | Private bucket name |
| `S3_REGION` | `auto` | Region; for B2/R2 use the provider's value (R2: `auto`) |
| `S3_ACCESS_KEY` | `…` | Access key ID (R2/B2 API token) |
| `S3_SECRET_KEY` | `…` | Secret access key |
| `S3_ENDPOINT_URL` | `https://<accountid>.r2.cloudflarestorage.com` | **Required** for R2/B2/MinIO; omit for AWS S3 |

`STORAGE_LOCAL_DIR` is only used when `STORAGE_BACKEND=local` (local dev/tests).

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
   - Note: `gunicorn` is pinned in `backend/requirements.txt`, so it installs
     automatically during the Render build. The start command is in `Procfile`.

### Backend notes
- Uses `wsgi.py` as the WSGI entrypoint (the `python app.py` dev server is only for local dev).
- In-memory rate limiter is single-instance; keep `--workers 2` on one free instance (fine for a hobby app). For horizontal scaling you'd back it with Redis.
- Health check: `GET /api/health` and `GET /`.
- Row-Level Security: a migration (`f0e9d8c7b6a5`) enables Postgres RLS with
  per-user ownership policies on `trips` and `subscriptions` (forced) and a
  per-user policy on `users` (not forced, so unauthenticated flows still work).
  The Vault migration (`b2c3d4e5f6a7`) extends the same protection to
  `trip_documents`. The feature migration (`3e2d1c0b9a87`) adds the Expense
  tracker (`trip_expenses`, RLS-owned), the password-reset columns on `users`,
  and `trips.budget_amount`. The app sets the authenticated user id into the
  `request.jwt.claims.sub` GUC per request (`SET LOCAL`) so the database
  enforces ownership too. RLS fails closed whenever the GUC is unset. Applying
  the migrations via `flask db upgrade` is required for the constraints to take
  effect.

### Email + password reset (server-side only)

Verification **and password-reset** emails are sent over **SMTP** using the
Python standard library (`services/email_service.py`) — no extra dependency.
When the SMTP env vars are unset, the app logs the code instead of sending
(fine for local dev/tests).

The forgot-password flow (`/api/auth/forgot-password` → code → verify → reset)
uses a **6-digit code** (15 min, max 5 attempts with lockout) followed by a
one-time `resetToken` (30 min). Codes and tokens are stored **hashed**; the API
always answers with the same generic message so it cannot be used to probe
which accounts exist. The flow depends on working SMTP — if you leave it in
log-only mode, reset codes never leave the server log.

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
   - `PREMIUM_ENABLED` → leave unset / `false` for the free-only **v1**
     (defaults to `false`). A future freemium build sets it to `true`.
   - `HOTEL_FEATURE_ENABLED` → leave unset / `false` (default). Hotels shipping
     is **hidden** (removed from the trip deck) until a build explicitly sets
     `--dart-define=HOTEL_FEATURE_ENABLED=true`. The backend hotel routes stay
     intact; the frontend entry points are simply gated. **Packing was removed
     entirely.**
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
real Google OAuth client IDs, and a store IAP flow (e.g. RevenueCat). Those are
out of scope of this runbook.
