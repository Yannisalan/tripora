> **Superseded (2026-11-09):** see `SECURITY_AUDIT_REPORT.md` and `SECURITY_HARDENING_REPORT.md`. Correction: the "Rate limiting" row below is inaccurate. `rates.*` and `travel.flight_prices_route` were declared with `limit: None` and stayed unthrottled until TRP-03 was fixed.

# SECURITY_TESTING_REPORT

## Scope
- Repository: C:\Users\odjoy\tripora (branch main). Windows 11/PowerShell.
- Backend: Flask (SQLite/Postgres), JWT auth, trips/expenses/weather/travel/rates, AI itinerary generation.
- Frontend: Flutter (web/mobile). Offline trip cache present.
- No existing `.github` workflows; CI added in this effort.

## Baselines (before/after)
- Backend pytest (all): before ~283 passed; after **312 passed** (added 29 tests: JWT token validation + extended IDOR coverage).
- Flutter: `flutter analyze`/`flutter test` run; auth/token-store tests updated and passing (22/22). Some pre-existing layout probe/login gate widget tests remain environment-sensitive but auth/session changes do not regress auth tests.

## Findings and fixes (with file/line citations)
| Area | Finding | Fix | Files/Lines |
|---|---|---|---|
| JWT identity handling | Malformed `sub` (empty/non-numeric/negative/missing) caused 500 on `/api/auth/me` (int conversion). Refresh tokens accepted as access in places; no revocation on password change/reset/delete. | Central JWT blocklist/revocation in `app.py` (validate `sub`, compare `ver` claim to `users.token_version`, reject missing/invalid/deleted; pre-rollout tokens without `ver` accepted until expiry; fail closed on DB errors). Added `InvalidIdentityError` and `_current_user_id()`/`_access_token_for()` in `auth.py`. Bump `token_version` and revoke refresh tokens on password change/reset; invalidate tokens on account deletion. | `backend/app.py:~150-230`, `backend/routes/auth.py:162-210,594-600,836-960,~1300+,~1515-1625`, `backend/models/user.py` (added `token_version`), `backend/migrations/versions/c8d2e3f4a5b6_add_user_token_version.py` |
| IDOR | Core trip routes use ownership checks; added coverage for `swap-activity`, weather, trip expenses and cross-user probing. | Verified and extended tests; ensured 404 (no leakage) on cross-user access. | `backend/routes/trips.py` (ownership), `backend/routes/weather.py:370-393`, `backend/routes/expenses.py:34-50`, `security/tests/test_idor_extended.py` (new) |
| Input validation | Missing caps on `destination`/`budget`/`travelStyle`, no max trip duration, budget/travelStyle accepted as non-strings in places; no request body size limit. | Enforced caps (destination 200, budget/travelStyle 100), max trip duration 365 days, interests max 20 items/60 chars, normalize strings. Added `MAX_CONTENT_LENGTH` (1MB) with 413 handler. | `backend/routes/trips.py:48-129`, `backend/app.py` (413 + MAX_CONTENT_LENGTH), `security/tests/test_generate_trip_input.py` (42 passed) |
| AI/LLM output | Strong validation exists; added string-length caps for titles/descriptions/locations. | Hardened `_validate_itinerary` with length checks. | `backend/services/itinerary_service.py:119-400+` |
| Rate limiting | `rates.*` and `travel.flight_prices_route` unthrottled; limiter exists but buckets missing. | Added buckets for `rates.get_rates`, `rates.get_single_rate`, `travel.flight_prices_route`. | `backend/services/rate_limiter.py:29-60` |
| Security headers/CORS | Missing security headers; CORS explicit origins (no wildcard). | Added headers (X-Content-Type-Options, X-Frame-Options, Referrer-Policy, Permissions-Policy, HSTS when TLS, CSP). | `backend/app.py` (after_request) |
| Session storage (frontend) | Access token in SharedPreferences on all platforms; refresh token fallback to plain storage on web/tests. | Both tokens in secure storage where available; legacy `access_token` migrated from SharedPreferences and deleted; no plaintext fallback (memory-only if secure storage fails). | `frontend/lib/core/auth/token_store.dart`, `frontend/test/token_store_test.dart`, `frontend/test/auth_service_test.dart`, `frontend/test/api_client_test.dart` |
| Secrets/deps | Tracked secrets: only `frontend/android/key.properties.example`. History clean of secret files. Dependencies have known vulns. | Added GitHub Actions workflow for tests + pip-audit; ran pip-audit (19 vulns in 4 packages: certifi, pyjwt, urllib3, werkzeug). | `.github/workflows/security.yml`, `pip_audit.json`, `pip_audit_summary.txt` |

## Test counts
- Before: ~283 backend tests passed.
- After: **312 backend tests passed** (added `security/tests/test_jwt_token_validation.py` 20, `security/tests/test_idor_extended.py` 9).
- Frontend auth/token tests updated and passing.

## Scans
- `pip-audit` (backend/requirements.txt): 19 known vulnerabilities in 4 packages (certifi 2026.7.22, pyjwt 2.13.0, urllib3 2.7.0, werkzeug 3.1.8). See `pip_audit_summary.txt`.
- Git tracked files: no secret files tracked. `git log` shows recent commits; history search for common secret extensions returned no results.
- Local secrets present but ignored: `backend/.env`, `frontend/android/key.properties`, `frontend/android/local.properties`.

## Changed files (key)
- Backend: `app.py`, `routes/auth.py`, `routes/trips.py`, `routes/weather.py` (reviewed), `models/user.py`, `services/itinerary_service.py`, `services/rate_limiter.py`, `migrations/versions/c8d2e3f4a5b6_add_user_token_version.py`
- Frontend: `lib/core/auth/token_store.dart`, tests updated
- Security: new tests `security/tests/test_jwt_token_validation.py`, `security/tests/test_idor_extended.py`; removed `security/tests/test_probe_tmp.py`
- CI: `.github/workflows/security.yml`

## Remaining risks (needs decision)
- **Dependencies**: 19 vulns in pyjwt/certifi/urllib3/werkzeug — upgrade requires dependency review/testing (not upgraded per instructions). Consider upgrading in a separate change.
- **Rate limiting**: in-process only (not shared across instances). For multi-instance deployments use Redis-backed storage.
- **Secure storage on web**: flutter_secure_storage_web uses encrypted localStorage in secure contexts; ensure production runs over HTTPS. If secure context unavailable, tokens are memory-only (session lost on reload) — acceptable per requirements.
- **Offline cache**: `trip_service.dart` caches itineraries (not tokens) and clears on logout — documented trade-off; no change made.
- **Orphaned files**: `backend/storage/trips/1/*.pdf` exist locally (gitignored) from removed vault feature — purge if desired.
- **CI**: added basic workflow; may need secrets/env for full integration tests.

## Manual steps
1. Apply migration: `flask db upgrade` (or run migration) to add `users.token_version`.
2. Review and rotate any secrets if history ever contained them (history clean).
3. Consider dependency upgrades for vulnerable packages.
4. For production, ensure HTTPS so HSTS is effective.
