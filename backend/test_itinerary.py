import pytest

from services.itinerary_service import generate_itinerary


@pytest.mark.integration
def test_generate_itinerary():
    """Verify that Gemini can generate a structured travel itinerary."""
    result = generate_itinerary(
        destination="Cotonou, Benin",
        start_date="2026-08-22",
        end_date="2026-08-29",
        travelers=1,
        budget="Moderate",
        travel_style="Balanced",
        interests=["Food", "Culture"],
    )

    assert isinstance(result, dict)
    assert isinstance(result.get("itinerary"), list)
    assert result["itinerary"], "The generated itinerary is empty."

    for day in result["itinerary"]:
        assert "day" in day
        assert "date" in day
        assert "title" in day
        assert isinstance(day.get("activities"), list)
