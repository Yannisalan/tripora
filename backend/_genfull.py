import os, logging
logging.basicConfig(level=logging.INFO)
from dotenv import load_dotenv
load_dotenv("C:/Users/odjoy/tripora/backend/.env")
from services.itinerary_service import generate_itinerary
try:
    r = generate_itinerary(
        destination="Paris, France",
        start_date="2026-10-05",
        end_date="2026-10-08",
        travelers=2,
        budget="Moderate",
        travel_style="Relaxed",
        interests=["Art", "Food", "Museums"],
    )
    days = r.get("itinerary", [])
    print("SUCCESS days:", len(days))
    print("day[0]:", days[0] if days else None)
except Exception as e:
    print("FAILED:", type(e).__name__, e)
