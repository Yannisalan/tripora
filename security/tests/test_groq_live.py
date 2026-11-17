"""LIVE Groq integration tests (marked ``integration``; skipped by default).

These call the real Groq API through the real Flask routes, against the
suite's in-memory SQLite database (never Neon). They run only when BOTH:

* ``TRIPORA_LOCAL_ONLY=1`` (the local safety guard), and
* ``TRIPORA_LIVE_GROQ_API_KEY`` holds a Groq key (development key preferred).

The conftest pins ``GROQ_API_KEY`` to a dummy for every other test, so the
live key is injected here only, into the service's client, per test.

Run from the repository root:

    TRIPORA_LOCAL_ONLY=1 FLASK_SKIP_DOTENV=1 TRIPORA_LIVE_GROQ_API_KEY=... \\
        backend/venv/Scripts/python.exe -m pytest security/tests/test_groq_live.py -m integration -v
"""

import os
import time
from datetime import date, timedelta

import groq
import pytest

import routes.trips as trips_module
import services.itinerary_service as itinerary_service

from .helpers import auth_headers, create_logged_in_user, create_trip


LIVE_KEY = os.getenv("TRIPORA_LIVE_GROQ_API_KEY", "")

pytestmark = [
    pytest.mark.integration,
    pytest.mark.skipif(
        os.getenv("TRIPORA_LOCAL_ONLY") != "1",
        reason="Live AI tests run only with TRIPORA_LOCAL_ONLY=1.",
    ),
    pytest.mark.skipif(
        not LIVE_KEY, reason="TRIPORA_LIVE_GROQ_API_KEY is not set."
    ),
]

SLOTS = ["Morning", "Afternoon", "Evening"]

# A few very common French function words; an English itinerary contains
# almost none of them, a French one is full of them.
FRENCH_MARKERS = (" le ", " la ", " les ", " des ", " et ", " du ", " une ")


@pytest.fixture
def live_ai(monkeypatch):
    monkeypatch.setattr(
        itinerary_service,
        "client",
        groq.Groq(api_key=LIVE_KEY, max_retries=0),
    )
    monkeypatch.setattr(
        trips_module, "generate_itinerary", itinerary_service.generate_itinerary
    )
    monkeypatch.setattr(
        trips_module,
        "generate_activity_swap",
        itinerary_service.generate_activity_swap,
    )


def _start():
    return date.today() + timedelta(days=60)


def _assert_flutter_shape(itinerary, days, start):
    """The contract the Flutter itinerary screen renders."""

    assert isinstance(itinerary, list)
    assert len(itinerary) == days
    for i, day in enumerate(itinerary):
        assert day["day"] == i + 1
        assert day["date"] == (start + timedelta(days=i)).isoformat()
        assert isinstance(day["title"], str) and day["title"].strip()
        assert [a["time"] for a in day["activities"]] == SLOTS
        for activity in day["activities"]:
            for key in ("time", "title", "description", "category", "location"):
                assert isinstance(activity[key], str) and activity[key].strip()
            assert activity["category"] in itinerary_service.ACTIVITY_CATEGORIES


def _generate(client, token, days, language="en"):
    start = _start()
    end = start + timedelta(days=days - 1)
    began = time.monotonic()
    resp = create_trip(
        client,
        token,
        destination="Lisbon, Portugal",
        startDate=start.isoformat(),
        endDate=end.isoformat(),
        preferredLanguage=language,
        interests=["food", "culture"],
    )
    elapsed = time.monotonic() - began
    return resp, start, elapsed


def test_live_generate_one_day_service_level(live_ai):
    # The trip routes reject end == start ("End date must be after start
    # date"), so a 1-day itinerary is exercised at the service level, with
    # the same server-side validation the routes apply.
    start = _start()
    began = time.monotonic()
    result = itinerary_service.generate_itinerary(
        destination="Lisbon, Portugal",
        start_date=start.isoformat(),
        end_date=start.isoformat(),
        travelers=2,
        budget="moderate",
        travel_style="balanced",
        interests=["food", "culture"],
        language="en",
    )
    elapsed = time.monotonic() - began
    _assert_flutter_shape(result["itinerary"], 1, start)
    itinerary_service._validate_itinerary(
        result, start.isoformat(), start.isoformat(), ["food", "culture"]
    )
    print("\n[live] 1-day EN generated in {:.1f}s".format(elapsed))


@pytest.mark.parametrize("days", [3, 8])
def test_live_generate_english(client, live_ai, days):
    token = create_logged_in_user(
        client, name="Live{}".format(days), email="live{}@example.com".format(days)
    )

    resp, start, elapsed = _generate(client, token, days)

    assert resp.status_code == 200, resp.get_json()
    _assert_flutter_shape(resp.get_json()["trip"]["itinerary"], days, start)
    assert elapsed < itinerary_service.GENERATION_BUDGET_SECONDS + 5
    print("\n[live] {}-day EN generated in {:.1f}s".format(days, elapsed))


def test_live_generate_french(client, live_ai):
    token = create_logged_in_user(
        client, name="LiveFr", email="livefr@example.com", language="fr"
    )

    resp, start, elapsed = _generate(client, token, 3, language="fr")

    assert resp.status_code == 200, resp.get_json()
    itinerary = resp.get_json()["trip"]["itinerary"]
    _assert_flutter_shape(itinerary, 3, start)
    text = " " + " ".join(
        a["description"].lower() for d in itinerary for a in d["activities"]
    ) + " "
    assert sum(text.count(m) for m in FRENCH_MARKERS) >= 5, text[:300]
    print("\n[live] 3-day FR generated in {:.1f}s".format(elapsed))


def test_live_regenerate_and_swap(client, live_ai):
    token = create_logged_in_user(
        client, name="LiveRegen", email="liveregen@example.com"
    )
    resp, start, _ = _generate(client, token, 3)
    assert resp.status_code == 200, resp.get_json()
    trip = resp.get_json()["trip"]

    began = time.monotonic()
    resp = client.post(
        "/api/trips/{}/regenerate".format(trip["id"]),
        headers=auth_headers(token),
    )
    regen_s = time.monotonic() - began
    assert resp.status_code == 200, resp.get_json()
    itinerary = resp.get_json()["trip"]["itinerary"]
    _assert_flutter_shape(itinerary, 3, start)

    old_morning = itinerary[1]["activities"][0]["title"]
    began = time.monotonic()
    resp = client.post(
        "/api/trips/{}/swap-activity".format(trip["id"]),
        json={"day": 2, "time": "Morning"},
        headers=auth_headers(token),
    )
    swap_s = time.monotonic() - began
    assert resp.status_code == 200, resp.get_json()
    swapped = resp.get_json()["trip"]["itinerary"]
    _assert_flutter_shape(swapped, 3, start)
    new_morning = swapped[1]["activities"][0]
    assert new_morning["title"] != old_morning
    titles = [a["title"] for d in swapped for a in d["activities"]]
    assert len(titles) == len(set(titles))
    assert swap_s < itinerary_service.SWAP_BUDGET_SECONDS + 5
    print("\n[live] regenerate {:.1f}s, swap {:.1f}s".format(regen_s, swap_s))


def test_live_edit_dates_rebuilds(client, live_ai):
    token = create_logged_in_user(
        client, name="LiveEdit", email="liveedit@example.com"
    )
    resp, start, _ = _generate(client, token, 3)
    assert resp.status_code == 200, resp.get_json()
    trip_id = resp.get_json()["trip"]["id"]

    resp = client.patch(
        "/api/trips/{}".format(trip_id),
        json={
            "destination": "Lisbon, Portugal",
            "startDate": start.isoformat(),
            "endDate": (start + timedelta(days=1)).isoformat(),
            "travelers": 2,
            "budget": "moderate",
            "travelStyle": "balanced",
            "interests": ["food", "culture"],
        },
        headers=auth_headers(token),
    )

    assert resp.status_code == 200, resp.get_json()
    _assert_flutter_shape(resp.get_json()["trip"]["itinerary"], 2, start)


# ----------------------------------------------------------------------
# Multilingual: es / de / it / pt through the real Tripora routes
# ----------------------------------------------------------------------

# Distinctive function words per supported language. The detected language
# is the one whose stopwords make up the largest share of the words.
STOPWORDS = {
    "en": {"the", "and", "with", "of", "to", "for", "a", "an", "is", "on", "at"},
    "es": {"el", "los", "las", "y", "del", "con", "para", "una", "por", "un", "es", "al"},
    "fr": {"le", "les", "et", "des", "du", "une", "avec", "pour", "dans", "au", "aux", "est"},
    "de": {"der", "die", "das", "und", "mit", "ein", "eine", "im", "zum", "zur", "den", "dem", "von", "ist"},
    "it": {"il", "e", "di", "della", "del", "con", "per", "una", "nel", "gli", "dei", "delle", "un", "è"},
    "pt": {"o", "os", "e", "do", "da", "com", "para", "uma", "em", "no", "na", "um", "dos", "das"},
}


def _language_scores(texts):
    words = []
    for text in texts:
        for raw in text.lower().split():
            word = raw.strip(".,;:!?()\"'«»—–-")
            if word:
                words.append(word)
    total = max(1, len(words))
    return {
        code: sum(1 for w in words if w in stop) / total
        for code, stop in STOPWORDS.items()
    }


def _assert_language(texts, language):
    scores = _language_scores(texts)
    detected = max(scores, key=scores.get)
    assert detected == language, scores
    if language != "en":
        # English must not dominate any non-English itinerary.
        assert scores["en"] < scores[language] / 2, scores


def _generated_texts(itinerary):
    texts = []
    for day in itinerary:
        texts.append(day["title"])
        for activity in day["activities"]:
            texts.append(activity["title"])
            texts.append(activity["description"])
    return texts


@pytest.mark.parametrize("language", ["fr", "es", "de", "it", "pt"])
def test_live_language_generate_regenerate_swap(client, live_ai, language):
    token = create_logged_in_user(
        client,
        name="Live{}".format(language),
        email="live-{}@example.com".format(language),
        language=language,
    )

    # Generate (2 days keeps each language inside the free-tier budget).
    resp, start, gen_s = _generate(client, token, 2, language=language)
    assert resp.status_code == 200, resp.get_json()
    trip = resp.get_json()["trip"]
    _assert_flutter_shape(trip["itinerary"], 2, start)
    _assert_language(_generated_texts(trip["itinerary"]), language)

    # Regenerate (language comes from the user's saved preference).
    resp = client.post(
        "/api/trips/{}/regenerate".format(trip["id"]),
        headers=auth_headers(token),
    )
    assert resp.status_code == 200, resp.get_json()
    regenerated = resp.get_json()["trip"]["itinerary"]
    _assert_flutter_shape(regenerated, 2, start)
    _assert_language(_generated_texts(regenerated), language)

    # Swap one activity.
    old_title = regenerated[0]["activities"][1]["title"]
    resp = client.post(
        "/api/trips/{}/swap-activity".format(trip["id"]),
        json={"day": 1, "time": "Afternoon"},
        headers=auth_headers(token),
    )
    assert resp.status_code == 200, resp.get_json()
    swapped = resp.get_json()["trip"]["itinerary"]
    _assert_flutter_shape(swapped, 2, start)
    new_activity = swapped[0]["activities"][1]
    assert new_activity["time"] == "Afternoon"
    assert new_activity["title"] != old_title
    _assert_language(
        [new_activity["title"], new_activity["description"]], language
    )
    print("\n[live] {} generate {:.1f}s + regenerate + swap OK".format(
        language, gen_s
    ))
