# Security Policy

## Reporting a vulnerability

Please **do not** open a public GitHub issue for security problems.

Email **security@tripora.example** *(maintainer: replace with a monitored address before publishing)* with the subject `SECURITY: <short title>`. Include:
- the affected endpoint, screen or file,
- steps to reproduce (synthetic accounts only),
- the impact you observed.

We acknowledge reports within 3 business days and aim to fix confirmed HIGH/CRITICAL issues within 14 days. Test only against your own local copy or accounts you own. Do not access other users' data, degrade the service or run automated scans against production.

## Supported versions

Only the latest `main` deployment (Render backend, Vercel web app, current store build) receives security fixes.

## Security architecture (summary)

| Control | Implementation |
|---|---|
| Password storage | Werkzeug scrypt (salted, memory-hard); policy 8–128 chars, common-password block list |
| Access tokens | HS256 JWT, 15 min, `ver` claim tied to `users.token_version` (revoked on password change/reset/deletion) |
| Refresh tokens | Opaque 512-bit random, SHA-256 hashed at rest, rotated on every use, whole family revoked on reuse |
| Authorization | Every user-owned query filters on the JWT user id; cross-user access returns 404; Postgres RLS on `trips` |
| Email verification | New accounts are unverified until a 6-digit emailed code (hashed, 30 min, 5 attempts, single use) is confirmed from a signed-in session; trips/AI/expenses/travel/weather return `403 email_unverified` until then. Registration answers identically for new and existing addresses |
| Sensitive changes | Current password required to change the password or login email; account deletion requires the password (or a fresh provider sign-in for social-only accounts) |
| Social sign-in | Server-side token verification; provider email must be verified; never auto-linked to an existing account; Apple requires a nonce |
| Administrators | Individual accounts with server-side `role=admin` (granted only by operator CLI), mandatory TOTP (RFC 6238, secrets Fernet-encrypted at rest, replay-protected), single-use recovery codes, opaque server-side sessions (30 min idle / 8 h max, revocable, ended by password change), every access written to `admin_audit_log`. Admin session token is kept in memory only in the client |
| Database | App is meant to run as `tripora_runtime` (DML only, no DDL, no BYPASSRLS; switch pending, see DEPLOYMENT runbook); migrations run as the owner in a pre-deploy step; RLS with table-specific policies on all 10 user-associated tables, identity from the verified access token only, transaction-local and re-applied per transaction; TLS required for remote hosts |
| Rate limiting | Per-endpoint buckets in Redis (shared across workers, atomic, survives restarts); per user or per real client IP (IPv6 by /64); unknown endpoints get default limits; platform-wide AI ceiling; documented Redis-failure mode |
| Transport | HSTS on API and web; CSP on the web app (report-only until production reports are clean) |
| Secrets | Server-side env vars only; none in the Flutter app; `.env` git-ignored |
| AI | Gemini key server-side only; schema-constrained JSON output validated server-side; user input fenced as data; per-user and platform-wide generation limits |

## Security-related environment variables

All of these live in the Render dashboard (backend) or Vercel project settings (web build). The template is `backend/.env.example`.

| Variable | Required | Purpose / guidance |
|---|---|---|
| `JWT_SECRET_KEY` | yes | HMAC key for access tokens. ≥ 32 random chars (a startup warning is logged if shorter). Rotating it signs every user out within 15 min (refresh tokens keep working). |
| `MFA_ENCRYPTION_KEY` | for admin | Fernet key encrypting admin TOTP secrets. Without it admin sign-in returns 503. Rotating/losing it requires every admin to re-enroll (`flask admin reset-mfa`). |
| `ADMIN_SESSION_IDLE_MINUTES` / `ADMIN_SESSION_MAX_HOURS` | no | Admin session idle timeout (default 30) and absolute lifetime (default 8). |
| `ADMIN_API_TOKEN` | legacy | Transitional shared admin secret. ≥ 32 random chars while used; remove after MFA admins exist. |
| `ADMIN_LEGACY_TOKEN_ENABLED` | legacy | `true` (default) accepts `ADMIN_API_TOKEN` (audited). Set `false` after migration. |
| `DB_USER` / `DB_PASSWORD` / `DB_HOST` / `DB_PORT` / `DB_NAME` | yes | Postgres connection for the **web process** = `tripora_runtime` (`backend/db/roles.sql`). |
| `DB_MIGRATION_USER` / `DB_MIGRATION_PASSWORD` | deploy | Owner credentials used **only** by the pre-deploy `flask db upgrade`. |
| `REDIS_URL` | yes (prod) | Shared rate-limit store (Render Key Value internal URL or `rediss://`). |
| `RATE_LIMIT_FAILURE_MODE` | no | `fallback` (default: per-process limits while Redis is down) or `closed` (503 for auth/admin/AI while Redis is down). |
| `RATE_LIMIT_AI_GLOBAL_LIMIT` / `_WINDOW` | no | Platform-wide Gemini ceiling (default 300 per hour). |
| `DB_SSLMODE` | recommended | `require` by default for non-local hosts; set `verify-full` when the CA is available. |
| `CORS_ORIGINS` | yes (prod) | Exact web origin(s), comma-separated. Unset = localhost defaults. |
| `TRUSTED_PROXY_HOPS` | auto | Proxy hops trusted for `X-Forwarded-For`/`-Proto`. Default 1 on Render (`RENDER=true`), else 0. Too high = clients can spoof their IP. |
| `JWT_ACCESS_TOKEN_MINUTES` | no | Default 15. Keep short. |
| `REFRESH_TOKEN_DAYS` | no | Default 30. |
| `GOOGLE_CLIENT_ID_*`, `APPLE_CLIENT_ID` | if social login | Accepted token audiences. |
| `GEMINI_API_KEY`, `TRAVELPAYOUTS_API_KEY`, `DUFFEL_API_TOKEN` | per feature | Provider keys. Server-side only. Set a spend cap in each provider console. |
| `MAIL_*` / `RESEND_API_KEY` | for password reset | Email delivery. Without it, reset is unavailable (codes are never logged). |
| `RATE_LIMIT_*` | no | Override bucket sizes (`RATE_LIMIT_ENABLED=false` only in tests). |
| `REQUEST_LOGGING_ENABLED` | no | Stores path, status, user id and IP per request in `activity_logs`. |
| `LOG_LEVEL` | no | `INFO` in production. `DEBUG` logs raw AI output (contains trip data). |
| `FLASK_DEBUG` | never in prod | Werkzeug debugger allows remote code execution. Dev server only. |

## Incident response

**1. Triage (first hour)**
- Record what was observed, when, and by whom. Keep raw logs (Render log stream, Neon query logs) before they rotate.
- Classify the incident: credential leak, account takeover, data exposure, abuse/cost spike, or dependency CVE.

**2. Contain**

| Situation | Action |
|---|---|
| `JWT_SECRET_KEY` leaked | Rotate in Render, then redeploy. All access tokens die within 15 min. Also revoke refresh tokens: `UPDATE user_refresh_tokens SET revoked_at = now() WHERE revoked_at IS NULL;` |
| One account compromised | `UPDATE users SET token_version = token_version + 1 WHERE id = :id;` plus revoke that user's refresh tokens. Ask the user to reset their password. |
| `ADMIN_API_TOKEN` leaked | Set `ADMIN_LEGACY_TOKEN_ENABLED=false` and clear it. Review `admin_audit_log` for `legacy_token_access`. |
| Admin account or authenticator compromised | `flask admin revoke <email>` (role, MFA and sessions removed immediately) or `flask admin revoke-sessions <email>` + `reset-mfa`. Review `admin_audit_log` for that user. |
| `MFA_ENCRYPTION_KEY` leaked | Generate a new key, deploy it, run `flask admin reset-mfa` for every admin. The old key alone does not grant access (password still required). |
| Redis down / flushed | Limits fall back to per-process (`fallback`) or auth/admin/AI return 503 (`closed`). Flushing only resets counters; no security state lives in Redis. |
| Gemini / Travelpayouts / Duffel key leaked or cost spike | Revoke the key in the provider console, issue a new one, set it in Render. Lower `RATE_LIMIT_GENERATE_LIMIT` / `RATE_LIMIT_AI_SWAP_LIMIT` if the spike is abuse. |
| DB credentials leaked | Rotate the role password in Neon, update `DB_PASSWORD`. Check Neon's connection history. |
| Vulnerable dependency | Bump the pin in `backend/requirements.txt` or `frontend/pubspec.yaml`. CI pip-audit must pass before deploy. |

**3. Eradicate and recover**
- Fix the root cause. Add a regression test in `security/tests/` that fails on the old code.
- Deploy, then verify with the test and a manual check.

**4. Notify**
- If personal data was or may have been accessed, assess GDPR Art. 33/34 duties: notify the supervisory authority within 72 hours, and notify affected users when the risk to them is high.
- Tell affected users what happened, what data was involved and what they should do.

**5. Review (within 2 weeks)**
- Write a blameless post-mortem: timeline, root cause, what detected it, and what would have detected it sooner.
- Track follow-up actions to completion.
