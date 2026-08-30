"""Subscription pricing tiers and country -> tier mapping.

The freemium model uses a small number of FIXED price tiers. Each ISO
3166-1 alpha-2 country code maps to one tier. Store-provided prices (Apple /
Google) are ultimately currency-localized per store region; the tier price
below is the display/reference price (in the tier's currency) shown in the
app's paywall before a real store purchase is charged.

Tier lookup is case-insensitive and tolerates empty/unknown codes (defaults
to the least expensive tier). Extend ``TIER_PRICES`` / ``COUNTRY_TIER`` as
needed.
"""

# Base currency/label per tier. The real per-currency amount is resolved by
# the app store for the user's store region; this is the reference price.
TIER_PRICES = {
    "tier_1": {"label": "Starter", "price": 4.99, "currency": "USD"},
    "tier_2": {"label": "Standard", "price": 6.99, "currency": "USD"},
    "tier_3": {"label": "Premium", "price": 9.99, "currency": "USD"},
}

# Country code -> tier. Unknown/empty countries fall back to tier_1.
COUNTRY_TIER = {
    # Low-purchase-power / emerging markets -> tier_1
    "IN": "tier_1",
    "NG": "tier_1",
    "PK": "tier_1",
    "BD": "tier_1",
    "VN": "tier_1",
    "PH": "tier_1",
    "ID": "tier_1",
    "BR": "tier_1",
    "MX": "tier_1",
    "CO": "tier_1",
    "AR": "tier_1",
    "EG": "tier_1",
    "TR": "tier_1",
    "UA": "tier_1",
    "TH": "tier_1",
    # Mid-market -> tier_2
    "US": "tier_2",
    "CA": "tier_2",
    "AU": "tier_2",
    "NZ": "tier_2",
    "GB": "tier_2",
    "ES": "tier_2",
    "PT": "tier_2",
    "IT": "tier_2",
    "FR": "tier_2",
    "DE": "tier_2",
    "NL": "tier_2",
    "BE": "tier_2",
    "AT": "tier_2",
    "IE": "tier_2",
    "SE": "tier_2",
    "NO": "tier_2",
    "DK": "tier_2",
    "FI": "tier_2",
    "PL": "tier_2",
    "CZ": "tier_2",
    "MY": "tier_2",
    "SG": "tier_2",
    "SA": "tier_2",
    "AE": "tier_2",
    "IL": "tier_2",
    # High-purchase-power / expensive markets -> tier_3
    "CH": "tier_3",
    "JP": "tier_3",
    "KR": "tier_3",
    "HK": "tier_3",
    "LU": "tier_3",
}

DEFAULT_TIER = "tier_1"


def normalize_country(country):
    """Normalize a raw country value to an uppercase 2-letter code or ''."""
    if not country:
        return ""
    code = str(country).strip().upper()
    return code if len(code) == 2 and code.isalpha() else ""


def tier_for_country(country):
    """Return the price tier key for a country code (falls back to tier_1)."""
    code = normalize_country(country)
    return COUNTRY_TIER.get(code, DEFAULT_TIER)


def tier_price(tier):
    """Return price dict for a tier key (falls back to tier_1)."""
    return TIER_PRICES.get(tier, TIER_PRICES[DEFAULT_TIER])
