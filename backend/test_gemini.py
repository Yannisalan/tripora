import os
from dotenv import load_dotenv
from google import genai

# Load .env
load_dotenv()

# Get API key
api_key = os.getenv("GEMINI_API_KEY")

if not api_key:
    raise ValueError("GEMINI_API_KEY was not found.")

# Create Gemini client
client = genai.Client(api_key=api_key)

print("Gemini client created successfully.")
print("Sending test request...")

response = client.models.generate_content(
    model="gemini-3.6-flash",
    contents="""
You are Tripora, an AI travel planner.

Create a very short travel plan for:

Destination: Cotonou, Benin
Travelers: 1
Budget: Moderate
Travel style: Balanced
Interests: Food and Culture

Give me exactly 3 suggested activities.
"""
)

print("\n========== GEMINI RESPONSE ==========\n")
print(response.text)
print("\n======================================")