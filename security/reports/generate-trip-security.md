# Tripora Backend — Security Report: `POST /api/trips/generate` Input Handling

**Scope:** Local Tripora backend (authorized for testing). Dynamic black-box input-validation testing of the `POST /api/trips/generate` endpoint via the Flask test client.
**Method:** 42 test cases across the input categories below, executing against an in-memory SQLite test DB with dummy credentials (see `security/tests/conftest.py`). The Gemini itinerary service is stubbed (no external calls). No application code was modified; no live/authenticated real data was touched.
**Artifacts:** Tests in `security/tests/test_generate_trip_input.py`; raw evidence in `security/reports/_generate_trip_evidence.json`.

---

## 1. Summary

| Metric | Value |
|--------|-------|
| Total test cases | 42 |
| Passed | 42 |
| Failed | 0 |
| Endpoint | `POST /api/trips/generate` (JWT-protected) |
| New finding | 1 (A-12) |

The endpoint validates most input well (destination required, ISO dates, positive-integer travelers, list-typed interests, end-after-start ordering, JWT required) and is resistant to the simple SQL-injection payloads tried. One **information-disclosure + unhandled-type crash** finding was confirmed: a numeric (integer) `startDate` bypasses ISO validation and triggers a `500` that discloses an internal exception string.

---

## 2. Test-Case Results by Input Category

Legend: **expl** = whether an internal exception string was exposed in the response body. All responses use the `{"success": ..., "message": ...}` / `{"error": ...}` envelope; bodies below quote the relevant message.

| # | Category | Case | Status | Exception exposed | Response message |
|---|----------|------|--------|-------------------|------------------|
| 1 | Missing destination | `destination` key absent | 400 | no | `Destination is required.` |
| 2 | Empty destination | `destination = ''` | 400 | no | `Destination is required.` |
| 3 | Empty destination | `destination = '   '` | 400 | no | `Destination is required.` |
| 4 | Null values | `destination = null` | 400 | no | `Destination is required.` |
| 5 | Extremely long destination | 100,000 chars | 200 | no | Trip generated and saved (no truncation/DOS guard) |
| 6 | Invalid start date | `startDate = 'not-a-date'` | 400 | no | `Invalid date format.` |
| 7 | Invalid end date | `endDate = '2026-13-45'` | 400 | no | `Invalid date format.` |
| 8 | End date before start date | `end 09-01 < start 09-10` | 400 | no | `End date cannot be before start date.` |
| **9** | **Invalid start date** | **`startDate = 20260901` (int)** | **500** | **yes** | **`Failed to calculate trip cost.` (real error string suppressed from table, see Finding A-12)** |
| 10 | Invalid traveler count | `travelers = '2'` (str) | 400 | no | `Travelers must be a positive number.` |
| 11 | Invalid traveler count | `travelers = 2.5` (float) | 400 | no | `Travelers must be a positive number.` |
| 12 | Negative traveler count | `travelers = -1` | 400 | no | `Travelers must be a positive number.` |
| 13 | Invalid traveler count | `travelers = 0` | 400 | no | `Travelers must be a positive number.` |
| 14 | Extremely large traveler count | `travelers = 1e9` | 200 | no | Trip generated and saved (no upper bound) |
| 15 | Negative budget | `budget = '-100'` (str) | 200 | no | Trip generated and saved (sign accepted) |
| **16** | **Negative budget** | **`budget = -100` (int)** | **500** | **yes** | **`Failed to calculate trip cost.`** |
| 17 | Extremely large budget | 100-digit string | 200 | no | Trip generated and saved |
| **18** | **Invalid budget type** | **`budget = 123` (int)** | **500** | **yes** | **`Failed to calculate trip cost.`** |
| **19** | **Invalid budget type** | **`budget = ['moderate']` (list)** | **500** | **yes** | **`Failed to calculate trip cost.`** |
| 20 | Invalid travel style | `travelStyle = 12345` (int) | 200 | no | Trip generated and saved |
| 21 | Invalid interests | `interests = 'str'` | 400 | no | `Interests must be a list.` |
| 22 | Invalid interests | `interests = object` | 400 | no | `Interests must be a list.` |
| 23 | Unexpected JSON fields | extra keys (`admin`, `role`, …) | 200 | no | Ignored (no privilege escalation observed) |
| 24 | Null values | null `start/end/travelers` | 400 | no | `Start date and end date are required.` |
| **25** | **Arrays where strings expected** | `destination` / `budget` as arrays | **500** | **yes** | **`Failed to calculate trip cost.`** |
| 26 | Objects where primitives expected | `destination`/`travelers` as objects | 400 | no | `Travelers must be a positive number.` |
| 27 | Malformed JSON | truncated body | 400 | no | `No trip data provided.` |
| 28 | Missing authentication | no `Authorization` header | 401 | no | `Authentication is required.` |
| 29–35 | SQL injection (destination) | `' OR '1'='1`, `' OR 1=1 --`, `x' UNION SELECT NULL--`, `'; --`, `\'"`, `1; SELECT 1`, `Paris' AND '1'='1` | 200 | no | All treated as literal data; no error, no injection |
| 36–42 | SQL injection (interests) | same 7 payloads inside list | 200 | no | All treated as literal data; no injection |

---

## 3. Findings

### A-12 — Integer/typed `startDate` (and other strongly-typed fields) bypass date validation and leak an exception string in a 500

**Severity:** Low to Medium (information disclosure; no data loss; abusive-but-valid input causes noisy 500s).

**Source:** `backend/routes/trips.py` parser + cost handler; `backend/services/cost_service.py`.

**Description:** In `_parse_trip_payload` (`trips.py:58-62`), dates are normalized with `date.fromisoformat(str(start_date)[:10])`. An integer value such as `20260901` passes this check because `str(20260901)[:10]` is `"20260901"`, which `date.fromisoformat` parses as the valid date `2026-09-01`. However, the raw (un-normalized) `start_date` int is forwarded to `_build_cost` → `calculate_trip_cost` (`trips.py:80-87`), where `cost_service.py:50` calls `start_date.split("T")`. On an `int`, `.split` raises `AttributeError: 'int' object has no attribute 'split'`. The route's cost exception handler (`trips.py:211`-area) catches it and returns HTTP `500` with `"error": str(error)` — disclosing the internal exception text instead of a generic message. Related strongly-typed inputs hit the same `500`: `budget = -100` (int), `budget = 123` (int), `budget = ['moderate']` (list), and `destination` as an array.

**Reproduction (test client):**
```python
r = client.post('/api/trips/generate', json={
    "destination": "Paris", "startDate": 20260901,
    "endDate": "2026-09-10", "travelers": 2,
    "budget": "moderate", "travelStyle": "leisure", "interests": []},
    headers={"Authorization": f"Bearer {token}"})
assert r.status_code == 500
assert "error" in r.get_json()   # contains 'int' object has no attribute 'split'
```

**Affected code (for documentation only — NOT modified):**
- `backend/routes/trips.py:59` — `date.fromisoformat(str(start_date)[:10])` accepts an int that formats as a parseable date.
- `backend/routes/trips.py:80-87` — `_build_cost` forwards the raw typed `start_date`/`budget`/`destination` to the cost service.
- `backend/services/cost_service.py:50` — `start_date.split("T")` crashes on an int (`AttributeError`).
- Route-level `except Exception` returning `"error": str(error)` on the cost path (see §9/A-8 of `attack-surface.md`).

**Recommended (not applied):**
- Coerce/normalize date fields to strings (`str(start_date)[:10]`) before the ISO parse, and reject non-string typed dates explicitly.
- Validate `budget` as a positive numeric string at the parser boundary.
- Return a generic `"error": "Invalid request."` / log the real exception server-side instead of echoing `str(error)` (extends existing A-8 recommendation).

**Related note:** A-8 (`str(error)` leakage) — previously documented — is the root enabler; A-12 is the confirmed dynamically-observed case on `generate`.

---

## 4. Additional Observations (not raised to findings)

- **Extremely long destination (100k chars) accepted (200)** and **extremely large traveler count (`1e9`) accepted (200)** — consistent with the DoS concern A-11 (unbounded trip workload). No length/upper-bound guard on `destination`/`travelers`/`budget`.
- **`budget = '-100'` (string, negative) accepted as a valid trip (200)** — negative sign is accepted and propagated into the AI/cost prompt (data-integrity / prompt-injection surface, related to A-10).
- SQL-injection payloads returned **200 with literal handling** — no injection observed (consistent with A-surface: ORM parameterization, no SQLi).
- **Unexpected JSON fields are ignored (200)**; no privilege-escalation vector observed via extra fields.

---

## 5. Fitness Summary vs Attack-Surface

The endpoint's parser is largely defensive: required-field presence, ISO-date checks, positive-integer travelers, list-typed interests, ordering check, and a `401` when unauthenticated. The single exploitable gap confirmed dynamically is the **typed-date/budget type-coercion hole leading to exception-string disclosure (A-12)**. Recommend addressing A-12 plus the pre-existing error-leakage pattern (A-8) and the unbounded-size/negative-input handling (A-11/A-10).
