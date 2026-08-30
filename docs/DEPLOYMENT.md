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
