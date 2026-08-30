import json
import logging
import os
from datetime import date, timedelta

from dotenv import load_dotenv
from google import genai
from google.genai import types


logger = logging.getLogger(__name__)


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
):
    """
    Strictly validate the itinerary returned by Gemini.

    Requirements:
    - day -> title -> date -> activities.
    - One entry for every calendar day.
    - Correct dates.
    - Exactly 3 activities per day.
    - Exactly Morning, Afternoon and Evening.
    - Activities contain time/title/description/category.
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

    return True


# ============================================================
# GENERATE ITINERARY
# ============================================================

def generate_itinerary(
    destination,
    start_date,
    end_date,
    travelers,
    budget,
    travel_style,
    interests,
):

    # ========================================================
    # NUMBER OF GENERATION ATTEMPTS
    # ========================================================

    max_attempts = 3

    last_error = None

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
    each other on the same day.

12. Avoid unrealistic travel between locations.

13. The final day should take departure into consideration
    when appropriate.

14. Do not invent exact opening hours, prices, reservations,
    availability, or transportation schedules.

15. Use real and relevant attractions, neighborhoods,
    experiences, restaurants, landmarks, or types of activities
    when possible.

16. Keep descriptions concise and useful.

17. Do not include markdown.

18. Do not include explanations.

19. Do not include comments.

20. Return ONLY valid JSON matching the requested schema.

21. Internally verify the complete response before returning it:

    - Correct number of calendar days.
    - Correct date for every day.
    - No duplicate dates.
    - No missing dates.
    - Exactly 3 activities per day.
    - Exactly one Morning activity per day.
    - Exactly one Afternoon activity per day.
    - Exactly one Evening activity per day.
    - Every activity contains all required fields.

{correction_message}
"""

        # ====================================================
        # CALL GEMINI
        # ====================================================

        try:

            response = client.models.generate_content(
                model="gemini-3.6-flash",
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
                                                        "type": "string"
                                                    },
                                                },
                                                "required": [
                                                    "time",
                                                    "title",
                                                    "description",
                                                    "category",
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
                "GEMINI API ERROR (attempt %s/%s): %s",
                attempt,
                max_attempts,
                error,
            )

            last_error = str(error)

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
