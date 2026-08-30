from services.itinerary_service import generate_itinerary


result = generate_itinerary(
    destination="Cotonou, Benin",
    start_date="2026-08-22",
    end_date="2026-08-29",
    travelers=1,
    budget="Moderate",
    travel_style="Balanced",
    interests=["Food", "Culture"],
)

print("\n========== GENERATED ITINERARY ==========\n")

for day in result["itinerary"]:
    print(f"DAY {day['day']} - {day['date']}")
    print(day["title"])

    for activity in day["activities"]:
        print(
            f"  {activity['time']}: "
            f"{activity['title']}"
        )
        print(
            f"    {activity['description']}"
        )
        print(
            f"    Category: {activity['category']}"
        )

    print()