# Tripora Audit & Feature Report

Status: **verification green** — backend 254/254 tests passing, Flutter analyze
clean (0 new issues), `flutter test` passing, `flutter build web --release`
succeeds, Alembic migration chain renders valid SQL.

---

## A. Summary

This engagement audited the Tripora codebase and fixed security/UX gaps, then
shipped three user-facing features end to end:

1. **Forgot password** — full email -> code -> reset flow (hashed codes/tokens).
2. **Expense Tracker** — per-trip budget + categorized expenses, RLS-protected.

Plus: removed **Packing** entirely, enabled system theme + fixed a broken logo
path, and wired the global auth guard's `navigatorKey` so session expiry always
redirects to login.

Later, the **Trip Vault** and all **monetization/subscription** features were
removed from the product; this codebase is free-only.

---

## B. Backend — password reset

`routes/auth.py`:

- `POST /api/auth/forgot-password` — validates the email, then always returns
  `GENERIC_RESET_MESSAGE`. Unknown emails, social-only accounts and existing
  accounts are indistinguishable on purpose (no account enumeration).
- `POST /api/auth/forgot-password/verify` — checks the 6-digit code, returns a
  one-time `resetToken`.
- `POST /api/auth/reset-password` — consumes the token and sets a new password
  (min 8 chars, vs 6 for registration).

Stored values are **SHA-256 hashed** (never raw codes/tokens). Code: 15-min
expiry, max 5 attempts then hard lockout that force-clears the fields. Token:
30-min expiry, single-use, cleared after success. `_redact_sensitive` masks
`code`/`resetToken` everywhere including error paths.

Rate buckets: `auth.forgot_password`, `forgot_password_verify`,
`reset_password` (5 per 15 min).

`services/email_service.py` — provider-agnostic sender: **SMTP** (stdlib) if
`MAIL_HOST`+`MAIL_USER`+`MAIL_PASSWORD` are set, else **Resend** if
`RESEND_API_KEY` is set, else **log-only** (returns success, logs the body).
Never logs credentials, codes or tokens. Default sender `gotripora@gmail.com`.

Migrated via `3e2d1c0b9a87` (`reset_code_hash`, `reset_code_expires_at`,
`reset_attempts`, `reset_token_hash` + index, `reset_token_expires_at`).

---

## C. Backend — Expense Tracker

`models/expense.py` — `trip_expenses` table; category/payment/currency
vocabularies; camelCase `to_dict()`.

`routes/expenses.py` (RLS-protected, ownership enforced in every query):

- `GET|POST /api/trips/<trip_id>/expenses` — list (with `budgetAmount`,
  `budgetCurrency` from `user.preferred_currency`, `tripTitle`) / create.
- `GET|PATCH|DELETE /api/expenses/<id>` — single-row ops scoped to the owner.

Validation: positive amount (None to 0.01), known currency (default USD),
known category, description <= 255 chars, date not in the future, payment
method default `other`. Non-USD, non-list currencies preserved as entered
(no conversion — documented limitation).

`models/trip.py` — `budget_amount` (Numeric(12,2)); accepted through trip
create + PATCH; unset keeps the existing value. Serialized as `budgetAmount`.

Rate buckets: `expenses.read` (60/60s), `expenses.write` (30/600s).

---

## E. Frontend — auth & theme fixes

- `main.dart` — `MaterialApp` now attaches `navigatorKey: AuthGuard.navigatorKey`
  (was missing; `AuthGuard.handleUnauthorized` could never navigate) and
  `themeMode` defaults to `ThemeMode.system` (was hard-light, ignoring dark
  mode).
- Login/register logo paths corrected to `assets/images/logo_new.png` (asset
  moved in a previous refactor).
- `forgot_password_screen.dart` — single screen, three steps (request code, verify
  code, set new password), resilient to app restart; pushes to login on success.
  Wired via `AppRoutes.forgotPassword` and a "Forgot password?" link on login.
- `auth_service.dart` — `forgotPassword`, `verifyResetCode`, `resetPassword`.

---

## F. Frontend — Expense Tracker UI

`models/expense_model.dart` (mirrors backend vocab), `services/expense_service.dart`,
`screens/expenses/expense_tracker_screen.dart`:

- Summary card: budget / spent / remaining with colour-coded progress bar.
- Category breakdown chips.
- Flat expense list (sorted date-desc), tap to edit, icon button to delete.
- Add / edit bottom sheet with amount, currency, category, description, date
  picker, payment method.
- Edit budget bottom sheet (PATCHes the trip via `TripService.updateTrip` with
  the full payload including the new `budgetAmount`).
- `trip_model.dart` updated with `budgetAmount` field, parsed in `fromJson`,
  serialized in `toJson` and `toDetailMap`.

---

## H. Deck edits

`screens/trip_details.dart`:

- Removed Hotels, Packing and Vault tiles from the deck (3 tiles:
  Activities, Expenses).
- Expenses -> `ExpenseTrackerScreen(trip: _trip)`.
- Removed orphaned `_showComingSoon` and `_showExpensesSheet` methods (unused
  after deck edits).

---

## I. Deps & cleanup

- `pubspec.yaml`: removed `provider`.
- Deleted 4 empty files: `widgets/feature_card.dart`, `footer.dart`,
  `hero_section.dart`, `tripora_navbar.dart`.

---

## J. Migration

`3e2d1c0b9a87_expenses_places_password_reset_budget.py` (down_revision
`a0dd384f0147` after the Vault migration was removed from the chain):

- `users`: `reset_code_hash`, `reset_code_expires_at`, `reset_attempts`,
  `reset_token_hash` (indexed), `reset_token_expires_at`.
- `trips`: `budget_amount` Numeric(12,2).
- `trip_expenses`: FKs CASCADE, indexes, RLS ENABLE/FORCE + 4 owner policies.
- Downgrade drops all of the above.
- Verified: `flask db upgrade --sql` renders valid Postgres DDL.

---

## M. Rate limiter

Added buckets in `config/settings.py` + `services/rate_limiter.py`:
`auth.forgot_password/forgot_password_verify/reset_password` (5/900),
`expenses.read` (60/60), `expenses.write` (30/600). All scoped per-user ID; no
auth default to `"none"`.

---

## L. Test results

| Suite | Pass | Notes |
|-------|------|-------|
| `pytest -q` (security/tests) | 254 | All green |
| `flutter test` | 1 | Widget test (premium tests removed) |
| `flutter analyze` | 0 new | 4 pre-existing infos (not from this work) |
| `flutter build web --release` | OK | Compiled in ~120s |

`backend/test_travel_routes.py` (35 tests, outside configured testpaths) has
a pre-existing failure in `test_flight_prices_success` (asserts a `provider`
key the route handler omits) — unrelated to this work and not part of the
security suite.

---

## M. Known limitations

- **Expense currency**: non-standard currencies are stored as-is with no
  conversion; budget/spent totals are in the user's `preferred_currency` only.
- **Rate limiter**: in-memory; resets on redeploy; suitable for single-instance
  free-tier deployments. Needs Redis for horizontal scale.

---

## N. Env vars added / relevant

| Env var | Default | Purpose |
|---------|---------|---------|
| `RESEND_API_KEY` | unset | Optional fallback email provider |

All other new functionality (expenses, reset) requires no new env vars
beyond what was already in `DEPLOYMENT.md`.

---

## O. Security notes

- Codes/tokens hashed before storage; raw values never logged.
- Generic reset message prevents account enumeration.
- Reset code has max 5 attempts then lockout; token is single-use.

---

## P. Files created (new)

| File | Purpose |
|------|---------|
| `backend/services/email_service.py` | SMTP / Resend / log-only email sender |
| `backend/models/expense.py` | Expense model + constants |
| `backend/routes/expenses.py` | Expense CRUD blueprint |
| `backend/migrations/versions/3e2d1c0b9a87_*.py` | Alembic migration |
| `security/tests/test_password_reset.py` | Reset flow tests |
| `security/tests/test_expenses.py` | Expense API tests |
| `frontend/lib/models/expense_model.dart` | Expense client model |
| `frontend/lib/services/expense_service.dart` | Expense API client |
| `frontend/lib/screens/auth/forgot_password_screen.dart` | Forgot password UI |
| `frontend/lib/screens/expenses/expense_tracker_screen.dart` | Expense tracker UI |

---

## Q. Files modified (key)

| File | Change |
|------|--------|
| `backend/models/user.py` | Reset columns |
| `backend/models/trip.py` | `budget_amount` + expenses relationship |
| `backend/models/__init__.py` | Added new model exports |
| `backend/routes/auth.py` | Forgot/reset endpoints + redact |
| `backend/routes/trips.py` | `budgetAmount` in parse/serialize |
| `backend/app.py` | Registered `expenses_bp` |
| `backend/config/settings.py` | Rate limit reset defaults |
| `backend/services/rate_limiter.py` | Reset + expense buckets |
| `frontend/lib/main.dart` | `navigatorKey` + `ThemeMode.system` |
| `frontend/lib/models/trip_model.dart` | `budgetAmount` field |
| `frontend/lib/routes/app_routes.dart` | `forgotPassword` route |
| `frontend/lib/screens/auth/login_screen.dart` | Logo path + forgot-password link |
| `frontend/lib/screens/auth/register_screen.dart` | Logo path fix |
| `frontend/lib/core/config/app_config.dart` | Deck/feature flags |
| `frontend/lib/services/auth_service.dart` | Reset methods |
| `frontend/pubspec.yaml` | Deps cleanup |
| `docs/DEPLOYMENT.md` | Env docs for new features |

---

## R. Files removed

| File | Reason |
|------|--------|
| `frontend/lib/widgets/feature_card.dart` | Empty, unused |
| `frontend/lib/widgets/footer.dart` | Empty, unused |
| `frontend/lib/widgets/hero_section.dart` | Empty, unused |
| `frontend/lib/widgets/tripora_navbar.dart` | Empty, unused |

---

## S. Next steps

1. **Expense currency conversion**: add a rates API (e.g. exchangerate.host)
   for real-time totals across mixed currencies.
2. **Redis rate limiter**: needed when scaling beyond a single Render instance.
3. **PWA offline caching**: service worker for expense data.
