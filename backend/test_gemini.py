import os

import pytest
from dotenv import load_dotenv
from google import genai


@pytest.mark.integration
def test_gemini_connection():
    """Verify that Gemini can generate content using the configured API key."""
    load_dotenv()

    api_key = os.getenv("GEMINI_API_KEY")
    if not api_key:
        pytest.skip("GEMINI_API_KEY is not configured.")

    client = genai.Client(api_key=api_key)

    try:
        response = client.models.generate_content(
            model="gemini-3.6-flash",
            contents=(
                "You are Tripora, an AI travel planner. "
                "Suggest exactly 3 activities for a traveler visiting "
                "Cotonou, Benin, interested in food and culture. "
                "Keep the response short."
            ),
        )

        assert response.text, "Gemini returned an empty response."
        print(response.text)
    finally:
        client.close()
