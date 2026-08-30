# Tripora Backend — SQL Injection Audit

**Scope:** Local Tripora backend (authorized for testing). Static source review of every database operation, tracing all user-controlled values from API request fields into SQL execution.
**Method:** Manual code trace of `backend/routes/*.py`, `backend/app.py`, `backend/config/*.py`, and `backend/models/*.py`. All query construction, parameterization, ordering, and raw SQL usage was reviewed.
**Result:** **No exploitable SQL injection was found.** The application uses the SQLAlchemy ORM exclusively and parameterized query construction; the sole raw SQL statement is a constant-string health check with no user input.

---

## 1. Inventory of Every Database Operation

All database access in the application code (`backend/`, excluding `venv/`):

| File:Line | Operation | User input? | Safely parameterized? |
|-----------|-----------|-------------|------------------------|
| `app.py:117-119` | `db.session.execute(text("SELECT 1"))` | No (constant) | Yes (no bind params needed; constant) |
| `routes/auth.py:134` | `User.query.filter_by(email=email)` | Yes (`email`) | Yes — SQLAlchemy binds value |
| `routes/auth.py:165-166` | `db.session.add(user)` + `commit()` | Yes (ORM attrs) | Yes — ORM insert binds values |
| `routes/auth.py:228` | `User.query.filter_by(verification_token=token)` | Yes (`token`) | Yes — SQLAlchemy binds value |
| `routes/auth.py:236-238` | mutate + `commit()` | — | Yes — ORM update binds values |
| `routes/auth.py:265` | `User.query.filter_by(email=email)` | Yes (`email`) | Yes — SQLAlchemy binds value |
| `routes/auth.py:349-351` | `User.query.filter_by(email=email)` | Yes (`email`) | Yes — SQLAlchemy binds value |
| `routes/auth.py:449-452` | `db.session.get(User, int(user_id))` | Yes (`user_id` from JWT) | Yes — PK lookup, bound |
| `routes/auth.py:504` | `db.session.get(User, int(user_id))` | Yes (`user_id` from JWT) | Yes — PK lookup, bound |
| `routes/auth.py:545` | `User.query.filter_by(email=clean_email)` | Yes (`email`) | Yes — SQLAlchemy binds value |
| `routes/trips.py:269-271` | `db.session.add(trip)` + `commit()` | Yes (ORM attrs) | Yes — ORM insert binds values |
| `routes/trips.py:317-321` | `Trip.query.filter_by(user_id=...).order_by(Trip.created_at.desc())` | Yes (`user_id`) | Yes — bound; ordering column is hardcoded |
| `routes/trips.py:364-367` | `Trip.query.filter_by(id=..., user_id=...)` | Yes (`id`, `user_id`) | Yes — bound |
| `routes/trips.py:411-414` | `Trip.query.filter_by(id=..., user_id=...)` + `delete()` | Yes (`id`, `user_id`) | Yes — bound; delete is ORM cascade |
| `routes/trips.py:486-489` | `Trip.query.filter_by(id=..., user_id=...)` + mutate | Yes (`id`, `user_id`) | Yes — bound |
| `routes/trips.py:544-547` | `Trip.query.filter_by(id=..., user_id=...)` | Yes (`id`, `user_id`) | Yes — bound |

---

## 2. Trace of User-Controlled Values

Every request that eventually touches the database feeds user data into **ORM column values or SQLAlchemy filter keyword arguments** — never into a raw SQL string. Specifically:

### Auth endpoints
- **POST `/api/auth/register`** — `email` → `filter_by(email=email)` (`auth.py:134`) and `name/email/password/language/currency` → `User(...)` ORM attributes (`auth.py:157-163`) → bound INSERT.
- **POST `/api/auth/verify-email`** — `token` → `filter_by(verification_token=token)` (`auth.py:228`).
- **POST `/api/auth/resend-verification`** — `email` → `filter_by(email=email)` (`auth.py:265`).
- **POST `/api/auth/login`** — `email` → `filter_by(email=email)` (`auth.py:349`).
- **GET/PATCH `/api/auth/me`** — `user_id` from JWT → `db.session.get(User, int(user_id))` (`auth.py:449,504`); PATCH writes `name/email/password` as ORM attributes; `clean_email` → `filter_by(email=clean_email)` (`auth.py:545`).

### Trip endpoints
- **POST `/api/trips/generate`** — `destination/startDate/endDate/travelers/budget/travelStyle/interests` parsed by `_parse_trip_payload` (`trips.py:34-77`), cost/itinerary computed in Python, then stored as `Trip(...)` ORM attributes (`trips.py:245-267`) → bound INSERT.
- **GET `/api/trips`** — `user_id` → `filter_by(user_id=...)` (`trips.py:317`), ordered by the **hardcoded** `Trip.created_at.desc()` (`trips.py:319`) — no user-supplied sort column/order.
- **GET/DELETE/PATCH `/api/trips/<trip_id>`** — `trip_id` (routed as `<int:trip_id>`) and `user_id` → `filter_by(id=..., user_id=...)`.
- **POST `/api/trips/<trip_id>/regenerate`** — `trip_id` → `filter_by(id=..., user_id=...)`.

### Health
- **GET `/api/health`** — `text("SELECT 1")` → constant, no input (`app.py:117-119`).

**Not used anywhere in app code:** `request.args` / query-string parameters (no dynamic filtering or sorting from the URL), raw `WHERE` string building, `.filter(text(...))`, or f-string/`.format()` interpolation of user input into any SQL.

---

## 3. Why the Code Is Not Vulnerable

1. **ORM-only querying.** Every user-influenced predicate uses SQLAlchemy's `Query.filter_by(**kwargs)` or `db.session.get(Model, pk)`, which compiles to parameterized SQL (`?` / `%s` placeholders). User values are passed as bind parameters, never spliced into the statement text.
2. **No raw SQL with input.** The only `text()` is the constant `"SELECT 1"` health probe.
3. **Fixed ordering.** `.order_by()` is always `Trip.created_at.desc()`, a hardcoded column — there is no user-controlled sort key that could be injected into an `ORDER BY` (a common secondary SQLi vector).
4. **Typed route params.** `trip_id` is constrained by `<int:trip_id>` at the route level, so it is always an integer.
5. **Value-level validation in Python.** `_parse_trip_payload` validates types/ranges before values reach the engine layer, and `auth.py` coerces/whitelists language and currency.

---

## 4. Safe Parameterized / ORM Alternatives (Reference)

Even though no vulnerable site exists, the recommended pattern (already used here) is:

```python
# SAFE — ORM filter with bound value
user = User.query.filter_by(email=email).first()

# SAFE — dictionary-based dynamic AND of filters (still parameterized)
filters = {}
if status:
    filters["status"] = status
rows = Trip.query.filter_by(**filters).all()

# If you must use raw SQL, ALWAYS use :named params bound via execute
from sqlalchemy import text
db.session.execute(
    text("SELECT * FROM trips WHERE destination = :dest"),
    {"dest": destination},
)
```

**Avoid** the following (none present in this codebase today):
```python
# UNSAFE — f-string / format interpolation of user input
db.session.execute(text(f"SELECT * FROM trips WHERE destination = '{destination}'"))

# UNSAFE — user-controlled ORDER BY / column/identifier interpolation
text(f"SELECT * FROM trips ORDER BY {user_sort_column}")
```

Identifiers (column/table names) can never be bound parameters; if user input must influence them, pin them against a server-side allowlist.

---

## 5. Regression Tests

Automated, benign injection-resistance tests were added in
`security/tests/test_sql_injection_audit.py`. They drive every user-controlled
query field (register name/email, login email, verify-email token,
resend-verification email, PATCH-me email conflict, trip destination/interests)
with benign SQL-injection-style payloads and assert that:

- No request returns a `500` with SQL internals (`"syntax"` / `"SQL"` / traceback text).
- Payloads are treated as literal data (stored/compared literally, or cleanly rejected by application validation).
- No payload causes unintended row enumeration, duplication, or deletion.

Run with:
```
pytest -q security/tests/test_sql_injection_audit.py
```

---

## 6. Conclusion

**SQL Injection risk: LOW.** No vulnerable code was identified. All database
operations use the SQLAlchemy ORM with parameterized filters; the only raw SQL
is a constant-string health check; ordering is fixed and not user-controlled.
The regression suite (existing `test_sql_injection.py` plus the new audit module)
guards against future regressions.
