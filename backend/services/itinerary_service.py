import json
import logging
import os
import time
from datetime import date, timedelta

from dotenv import load_dotenv
from google import genai
from google.genai import types


logger = logging.getLogger(__name__)


# Gemini models used for itinerary generation, in priority order. The primary
# model can intermittently return 503 UNAVAILABLE ("experiencing high
# demand"); if it stays down we fall back to the next capable model so a
# transient capacity spike never fails the user's request. All ids here were
# verified against the Gemini API (2026-09): `gemini-3.6-flash` and
# `gemini-3.5-flash-lite` respond; `gemini-3.6-flash-lite` does NOT exist
# anymore (404) and must not be used as a fallback.
GEMINI_MODELS = [
    "gemini-3.6-flash",
    "gemini-3.5-flash",
    "gemini-3.5-flash-lite",
]

# Categories every activity must fall into. Kept in sync with the interest
# taxonomy used on the Flutter side (Planner's interest chips) plus two
# general-purpose categories for activities that don't map to a specific
# interest (arrival/departure logistics, generic sightseeing).
ACTIVITY_CATEGORIES = [
    "Culture",
    "Food",
    "Nature",
    "Adventure",
    "Shopping",
    "Nightlife",
    "Relaxation",
    "Sightseeing",
]

# Maps a user's preferred language code to a human-readable name used to
# instruct Gemini which language the itinerary content should be written in.
# Kept in sync with VALID_LANGUAGES in routes/auth.py.
LANGUAGES_BY_CODE = {
    "en": "English",
    "es": "Spanish",
    "fr": "French",
    "de": "German",
    "it": "Italian",
    "pt": "Portuguese",
}


load_dotenv()

api_key = os.getenv("GEMINI_API_KEY")

if not api_key:
    raise ValueError("GEMINI_API_KEY is not configured.")


client = genai.Client(api_key=api_key)


# ============================================================
# VALIDATE ITINERARY
# ============================================================

def _validate_itinerary(
    result,
    start_date,
    end_date,
    interests,
):
    """
    Strictly validate the itinerary returned by Gemini.

    Requirements:
    - day -> title -> date -> activities.
    - One entry for every calendar day.
    - Correct dates.
    - Exactly 3 activities per day.
    - Exactly Morning, Afternoon and Evening.
    - Activities contain time/title/description/category/location.
    - category is one of ACTIVITY_CATEGORIES.
    - No two activities across the whole trip share the same title
      (prevents Gemini repeating the same restaurant/landmark).
    - Every selected interest is covered by at least one activity,
      when interests were provided.
    """

    # --------------------------------------------------------
    # Basic response validation
    # --------------------------------------------------------

    if not isinstance(result, dict):
        raise ValueError(
            "Gemini response must be a JSON object."
        )

    if "itinerary" not in result:
        raise ValueError(
            "Gemini response does not contain an itinerary."
        )

    itinerary = result["itinerary"]

    if not isinstance(itinerary, list):
        raise ValueError(
            "Gemini itinerary must be a list."
        )

    # --------------------------------------------------------
    # Convert dates to date objects
    # --------------------------------------------------------

    try:
        start = date.fromisoformat(str(start_date))
        end = date.fromisoformat(str(end_date))
    except ValueError as error:
        raise ValueError(
            f"Invalid trip dates: {error}"
        ) from error

    if end < start:
        raise ValueError(
            "End date cannot be before start date."
        )

    expected_days = (end - start).days + 1

    # --------------------------------------------------------
    # Validate number of days
    # --------------------------------------------------------

    if len(itinerary) != expected_days:
        raise ValueError(
            f"Expected exactly {expected_days} itinerary days "
            f"but Gemini returned {len(itinerary)}."
        )

    # --------------------------------------------------------
    # Expected dates
    # --------------------------------------------------------

    expected_dates = [
        (start + timedelta(days=i)).isoformat()
        for i in range(expected_days)
    ]

    # --------------------------------------------------------
    # Track state across the whole trip (not just per-day)
    # --------------------------------------------------------

    seen_activity_titles = set()
    seen_locations_by_day = {}
    categories_used = set()

    # --------------------------------------------------------
    # Validate every day
    # --------------------------------------------------------

    for index, day in enumerate(itinerary):

        if not isinstance(day, dict):
            raise ValueError(
                f"Itinerary day {index + 1} must be an object."
            )

        # ----------------------------------------------------
        # Required day fields
        # ----------------------------------------------------

        required_day_fields = [
            "day",
            "title",
            "date",
            "activities",
        ]

        for field in required_day_fields:
            if field not in day:
                raise ValueError(
                    f"Itinerary day {index + 1} "
                    f"is missing '{field}'."
                )

        # ----------------------------------------------------
        # Validate day number
        # ----------------------------------------------------

        expected_day_number = index + 1

        if day["day"] != expected_day_number:
            raise ValueError(
                f"Expected day {expected_day_number}, "
                f"but received day {day['day']}."
            )

        # ----------------------------------------------------
        # Validate date
        # ----------------------------------------------------

        if day["date"] != expected_dates[index]:
            raise ValueError(
                f"Day {expected_day_number} has incorrect date. "
                f"Expected {expected_dates[index]}, "
                f"received {day['date']}."
            )

        # ----------------------------------------------------
        # Validate activities
        # ----------------------------------------------------

        activities = day["activities"]

        if not isinstance(activities, list):
            raise ValueError(
                f"Day {expected_day_number} activities "
                f"must be a list."
            )

        if len(activities) != 3:
            raise ValueError(
                f"Day {expected_day_number} must contain "
                f"exactly 3 activities, but received "
                f"{len(activities)}."
            )

        # ----------------------------------------------------
        # Validate activity times
        # ----------------------------------------------------

        required_times = {
            "Morning",
            "Afternoon",
            "Evening",
        }

        actual_times = set()

        # ----------------------------------------------------
        # Validate each activity
        # ----------------------------------------------------

        for activity_index, activity in enumerate(
            activities
        ):

            if not isinstance(activity, dict):
                raise ValueError(
                    f"Day {expected_day_number}, activity "
                    f"{activity_index + 1} must be an object."
                )

            required_activity_fields = [
                "time",
                "title",
                "description",
                "category",
                "location",
            ]

            for field in required_activity_fields:

                if field not in activity:
                    raise ValueError(
                        f"Day {expected_day_number}, activity "
                        f"{activity_index + 1} is missing "
                        f"'{field}'."
                    )

            activity_time = activity["time"]

            if activity_time not in required_times:
                raise ValueError(
                    f"Day {expected_day_number} contains "
                    f"invalid activity time: "
                    f"{activity_time}."
                )

            if activity_time in actual_times:
                raise ValueError(
                    f"Day {expected_day_number} contains "
                    f"duplicate {activity_time} activity."
                )

            actual_times.add(activity_time)

            # ------------------------------------------------
            # Validate category is from the allowed enum
            # ------------------------------------------------

            activity_category = activity["category"]

            if activity_category not in ACTIVITY_CATEGORIES:
                raise ValueError(
                    f"Day {expected_day_number}, activity "
                    f"'{activity.get('title', '?')}' has invalid "
                    f"category '{activity_category}'. Must be one "
                    f"of: {', '.join(ACTIVITY_CATEGORIES)}."
                )

            categories_used.add(activity_category)

            # ------------------------------------------------
            # Validate location is a non-empty, meaningful string
            # ------------------------------------------------

            activity_location = activity["location"]

            if (
                not isinstance(activity_location, str)
                or not activity_location.strip()
            ):
                raise ValueError(
                    f"Day {expected_day_number}, activity "
                    f"'{activity.get('title', '?')}' has an empty "
                    f"'location'. Every activity must name the "
                    f"neighborhood, district, or area it takes "
                    f"place in."
                )

            # ------------------------------------------------
            # Detect exact-title repetition across the whole trip
            # ------------------------------------------------

            activity_title = activity["title"]

            title_key = activity_title.strip().lower()

            if title_key in seen_activity_titles:
                raise ValueError(
                    f"Activity '{activity_title}' is repeated more "
                    f"than once across the itinerary. Every "
                    f"activity must be unique — do not reuse the "
                    f"same restaurant, landmark, or experience on "
                    f"a different day."
                )

            seen_activity_titles.add(title_key)

            seen_locations_by_day.setdefault(
                expected_day_number, []
            ).append(activity_location)

        # ----------------------------------------------------
        # Make sure all three periods exist
        # ----------------------------------------------------

        if actual_times != required_times:
            missing_times = required_times - actual_times

            raise ValueError(
                f"Day {expected_day_number} is missing "
                f"activity period(s): "
                f"{', '.join(sorted(missing_times))}."
            )

    # --------------------------------------------------------
    # Validate interest coverage across the whole trip
    # --------------------------------------------------------

    if interests:
        normalized_interests = {
            str(interest).strip().lower()
            for interest in interests
            if str(interest).strip()
        }

        normalized_categories_used = {
            category.lower() for category in categories_used
        }

        uncovered = [
            interest
            for interest in normalized_interests
            if interest not in normalized_categories_used
        ]

        if uncovered:
            raise ValueError(
                "The itinerary does not include any activity for "
                f"the following selected interest(s): "
                f"{', '.join(sorted(uncovered))}. Include at least "
                f"one activity per selected interest somewhere in "
                f"the trip."
            )

    return True


# ============================================================
# GENERATE ITINERARY
# ============================================================

def _is_transient_error(error):
    """Best-effort check for a transient, retry-friendly Gemini API error.

    The google-genai SDK wraps HTTP failures in exceptions whose ``__str__``
    includes the status code (e.g. ``503 UNAVAILABLE``). We also honour
    ``google.api_core.exceptions`` statuses when the rich error object is
    available. Anything else (auth, invalid argument) is treated as permanent.
    """
    message = str(error).upper()
    if any(code in message for code in ("429", "503", "500", "502", "504")):
        return True
    try:
        from google.api_core import exceptions as gax
        return isinstance(
            error,
            (
                gax.ResourceExhausted,
                gax.ServiceUnavailable,
                gax.DeadlineExceeded,
                gax.InternalServerError,
                gax.TooManyRequests,
            ),
        )
    except Exception:
        return False


def _is_permanent_model_error(error):
    """True when the model id itself is unusable and will never recover.

    These are permanent failures — retrying burns attempts without any
    chance of success, so the caller should advance to the next model
    immediately instead of waiting on transient-error thresholds.
    """
    message = str(error).upper()
    if "404" in message or "NOT_FOUND" in message:
        return True
    if "NO LONGER AVAILABLE" in message or "NOT SUPPORTED" in message:
        return True
    return False


def generate_itinerary(
    destination,
    start_date,
    end_date,
    travelers,
    budget,
    travel_style,
    interests,
    language="en",
):

    # ========================================================
    # NUMBER OF GENERATION ATTEMPTS
    # ========================================================

    # Budget must cover the worst realistic case: every fallback model
    # transiently failing twice before swapping to the next one.
    # (3 models * 2 transient errors + slack for a final try = 8.)
    max_attempts = 8

    last_error = None

    # Track which Gemini model we are on and how many consecutive times it has
    # failed with a transient/unavailable error, so we can fall back to the
    # next model instead of retrying an overloaded one forever.
    model_index = 0
    model = GEMINI_MODELS[model_index]
    model_transient_errors = 0

    categories_list = ", ".join(ACTIVITY_CATEGORIES)

    language_name = LANGUAGES_BY_CODE.get(
        (language or "en").lower(),
        "English",
    )

    language_requirement = ""
    if language_name != "English":
        language_requirement = f"""

LANGUAGE REQUIREMENT:

Write ALL itinerary content — every day title, activity title,
description, and location — in {language_name}.

Keep the JSON keys, the 'time' values (e.g. "Morning"), and the
'category' values in English. Everything a traveler would read
(mainly the description fields) must be in {language_name}.
"""

    # ========================================================
    # GENERATION LOOP
    # ========================================================

    for attempt in range(1, max_attempts + 1):

        # ----------------------------------------------------
        # First attempt uses the normal prompt.
        #
        # If Gemini returns invalid data, subsequent attempts
        # explicitly tell Gemini what went wrong.
        # ----------------------------------------------------

        correction_message = ""

        if last_error is not None:
            correction_message = f"""

IMPORTANT CORRECTION FROM PREVIOUS ATTEMPT:

The previous itinerary was invalid because:

{last_error}

You MUST correct this problem in this attempt.

Before returning the JSON, verify every day contains:
1. Exactly one Morning activity.
2. Exactly one Afternoon activity.
3. Exactly one Evening activity.
4. Every activity has a non-empty 'location' (neighborhood/area).
5. Every activity's 'category' is one of: {categories_list}.
6. No activity title is repeated anywhere else in the trip.
7. Every selected interest appears in at least one activity.

Do not return the previous invalid structure.
"""

        prompt = f"""
You are Tripora, an AI travel planning assistant.

Create a realistic day-by-day itinerary for the following trip.

TRIP DETAILS:
Destination: {destination}
Start date: {start_date}
End date: {end_date}
Travelers: {travelers}
Budget: {budget}
Travel style: {travel_style}
Interests: {interests}
{language_requirement}
REQUIREMENTS:

1. Create EXACTLY ONE itinerary entry for EVERY calendar day
   from the provided start date through the provided end date,
   inclusive.

2. Use the EXACT dates provided.

3. Do not skip, merge, duplicate, or invent dates.

4. EVERY itinerary day MUST contain EXACTLY 3 activities.

5. The 3 activities MUST be:

   Activity 1:
   time = "Morning"

   Activity 2:
   time = "Afternoon"

   Activity 3:
   time = "Evening"

6. Every day MUST contain exactly:
   - one Morning activity
   - one Afternoon activity
   - one Evening activity

7. NEVER return fewer than 3 activities for any day.

8. NEVER return more than 3 activities for any day.

9. Activities should match the traveler's:
   - budget
   - travel style
   - interests

10. Keep the schedule realistic and geographically practical.

11. Prefer activities that are geographically close to
    each other on the same day. Use the 'location' field
    (the specific neighborhood, district, or area) to make this
    verifiable — activities on the same day should generally
    share the same or an adjacent location.

12. Avoid unrealistic travel between locations.

13. The final day should take departure into consideration
    when appropriate.

14. Do not invent exact opening hours, prices, reservations,
    availability, or transportation schedules.

15. Use real and relevant attractions, neighborhoods,
    experiences, restaurants, landmarks, or types of activities
    when possible.

16. Keep descriptions concise, specific, and useful. Prefer a
    named place ("Tsukiji Outer Market") over a generic
    description ("a local market").

17. Do not include markdown.

18. Do not include explanations.

19. Do not include comments.

20. Every activity MUST include a 'category' field, and its
    value MUST be exactly one of: {categories_list}. Choose the
    category that best matches the activity, favoring the
    traveler's selected interests where relevant.

21. Every activity MUST include a 'location' field: the specific
    neighborhood, district, or named area where it takes place
    (not the whole city name, and not empty).

22. NEVER repeat the exact same activity (same restaurant,
    landmark, or experience) on more than one day of the trip.
    Every activity across the entire itinerary must be unique.

23. If the traveler selected one or more interests, the finished
    itinerary MUST include at least one activity whose category
    matches each selected interest, somewhere across the trip.

24. Return ONLY valid JSON matching the requested schema.

25. Internally verify the complete response before returning it:

    - Correct number of calendar days.
    - Correct date for every day.
    - No duplicate dates.
    - No missing dates.
    - Exactly 3 activities per day.
    - Exactly one Morning activity per day.
    - Exactly one Afternoon activity per day.
    - Exactly one Evening activity per day.
    - Every activity contains all required fields, including
      'category' (from the allowed list) and a non-empty
      'location'.
    - No activity title repeated anywhere in the trip.
    - Every selected interest is represented at least once.

{correction_message}
"""

        # ====================================================
        # CALL GEMINI
        # ====================================================

        try:

            response = client.models.generate_content(
                model=model,
                contents=prompt,
                config=types.GenerateContentConfig(
                    response_mime_type="application/json",
                    response_schema={
                        "type": "object",
                        "properties": {
                            "itinerary": {
                                "type": "array",
                                "items": {
                                    "type": "object",
                                    "properties": {
                                        "day": {
                                            "type": "integer"
                                        },
                                        "date": {
                                            "type": "string"
                                        },
                                        "title": {
                                            "type": "string"
                                        },
                                        "activities": {
                                            "type": "array",
                                            "minItems": 3,
                                            "maxItems": 3,
                                            "items": {
                                                "type": "object",
                                                "properties": {
                                                    "time": {
                                                        "type": "string"
                                                    },
                                                    "title": {
                                                        "type": "string"
                                                    },
                                                    "description": {
                                                        "type": "string"
                                                    },
                                                    "category": {
                                                        "type": "string",
                                                        "enum": ACTIVITY_CATEGORIES,
                                                    },
                                                    "location": {
                                                        "type": "string"
                                                    },
                                                },
                                                "required": [
                                                    "time",
                                                    "title",
                                                    "description",
                                                    "category",
                                                    "location",
                                                ],
                                            },
                                        },
                                    },
                                    "required": [
                                        "day",
                                        "title",
                                        "date",
                                        "activities",
                                    ],
                                },
                            }
                        },
                        "required": [
                            "itinerary"
                        ],
                    },
                ),
            )

        except Exception as error:

            logger.error(
                "GEMINI API ERROR (attempt %s/%s, model %s): %s",
                attempt,
                max_attempts,
                model,
                error,
            )

            last_error = str(error)

            # A model id that no longer exists (404 NOT_FOUND, "no longer
            # available") will never succeed — skip straight to the next
            # model instead of consuming the retry budget on it.
            if (
                _is_permanent_model_error(error)
                and model_index < len(GEMINI_MODELS) - 1
            ):
                model_index += 1
                model = GEMINI_MODELS[model_index]
                model_transient_errors = 0
                logger.warning(
                    "Skipping permanently unavailable Gemini model, "
                    "falling back to %s.",
                    model,
                )
                continue

            # The Gemini client surfaces HTTP status codes in the message.
            # A 429/5xx (notably 503 UNAVAILABLE under high demand) is
            # transient, so back off briefly and, if the model stays down,
            # fall back to the next capable model.
            transient = _is_transient_error(error)
            if transient:
                model_transient_errors += 1
                if (
                    model_transient_errors >= 2
                    and model_index < len(GEMINI_MODELS) - 1
                ):
                    model_index += 1
                    model = GEMINI_MODELS[model_index]
                    model_transient_errors = 0
                    logger.warning(
                        "Falling back to Gemini model %s after transient error.",
                        model,
                    )
                time.sleep(2 * model_transient_errors)

            continue

        # ====================================================
        # PARSE JSON
        # ====================================================

        try:

            result = json.loads(response.text)

        except (json.JSONDecodeError, TypeError) as error:

            logger.error(
                "GEMINI JSON ERROR (attempt %s/%s): %s",
                attempt,
                max_attempts,
                error,
            )

            logger.error(
                "GEMINI RESPONSE: %s",
                response.text,
            )

            last_error = (
                f"Gemini returned invalid JSON: {error}"
            )

            continue

        # ====================================================
        # VALIDATE
        # ====================================================

        try:

            _validate_itinerary(
                result,
                start_date,
                end_date,
                interests,
            )

        except ValueError as error:

            logger.error(
                "ITINERARY VALIDATION ERROR "
                "(attempt %s/%s): %s",
                attempt,
                max_attempts,
                error,
            )

            logger.error(
                "INVALID ITINERARY: %s",
                json.dumps(
                    result,
                    indent=2,
                    ensure_ascii=False,
                ),
            )

            last_error = str(error)

            continue

        # ====================================================
        # SUCCESS
        # ====================================================

        logger.info(
            "AI ITINERARY GENERATED SUCCESSFULLY ON ATTEMPT %s",
            attempt,
        )

        return result

    # ========================================================
    # ALL ATTEMPTS FAILED
    # ========================================================

    raise RuntimeError(
        "Failed to generate a valid itinerary after "
        f"{max_attempts} attempts. "
        f"Last error: {last_error}"
    )