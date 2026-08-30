from datetime import date


# Approximate daily costs per person in USD.
# These are planning estimates, not live prices.
DESTINATION_COSTS = {
    "paris": {
        "budget": 90,
        "moderate": 170,
        "luxury": 350,
    },
    "tokyo": {
        "budget": 80,
        "moderate": 160,
        "luxury": 330,
    },
    "dubai": {
        "budget": 100,
        "moderate": 200,
        "luxury": 450,
    },
    "bali": {
        "budget": 55,
        "moderate": 110,
        "luxury": 250,
    },
}


DEFAULT_COSTS = {
    "budget": 70,
    "moderate": 140,
    "luxury": 300,
}


def calculate_trip_cost(
    destination,
    start_date,
    end_date,
    travelers,
    budget,
):
    """
    Calculate an approximate trip cost.

    Returns costs in USD.
    """

    start = date.fromisoformat(start_date.split("T")[0])
    end = date.fromisoformat(end_date.split("T")[0])

    nights = (end - start).days

    if nights <= 0:
        raise ValueError(
            "End date must be after start date."
        )

    budget_key = budget.lower()

    destination_key = destination.lower().strip()

    destination_prices = DESTINATION_COSTS.get(
        destination_key,
        DEFAULT_COSTS,
    )

    daily_cost = destination_prices.get(
        budget_key,
        DEFAULT_COSTS["moderate"],
    )

    total_cost = daily_cost * nights * travelers

    accommodation = total_cost * 0.40
    food = total_cost * 0.25
    transportation = total_cost * 0.15
    activities = total_cost * 0.20

    return {
        "currency": "USD",
        "nights": nights,
        "travelers": travelers,
        "estimatedTotal": round(total_cost, 2),
        "breakdown": {
            "accommodation": round(accommodation, 2),
            "food": round(food, 2),
            "transportation": round(transportation, 2),
            "activities": round(activities, 2),
        },
        "note": (
            "This is an approximate planning estimate. "
            "Actual prices may vary."
        ),
    }