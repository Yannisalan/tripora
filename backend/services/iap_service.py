"""Server-side verification of Apple App Store and Google Play receipts.

Both providers are verified against their official verification endpoints so
the client's purchase can never be trusted blindly. Each function FAILS
CLOSED: if the required credentials/config are not present (which is the case
before the user provides them), verification raises ``IAPError`` and no
entitlement is granted. This keeps the backend safe/inert by default, exactly
like social auth.

Per-external-provider notes:
  * Google: a service-account JSON key path should be provided in
    ``GOOGLE_PLAY_SERVICE_ACCOUNT_PATH``. The service account's email becomes
    the issuer; the signed JWT is exchanged for an OAuth token which calls
    the Play Developer API ``purchases.subscriptions.get``.
  * Apple: ``APPLE_APPSTORE_SHARED_SECRET`` must be set; receipts are posted
    to the (production) verifyReceipt endpoint.

Timezone aware: store expiry fields are ms-epoch (Apple) or RFC3339 (Google)
and are converted to an aware UTC ``datetime``.
"""

import logging
import os
import time
from datetime import datetime, timezone

import jwt
import requests

logger = logging.getLogger(__name__)

# https://developer.apple.com/documentation/appstorereceipts/verifyreceipt
APPLE_VERIFY_URL = "https://buy.itunes.apple.com/verifyReceipt"
APPLE_SANDBOX_VERIFY_URL = "https://sandbox.itunes.apple.com/verifyReceipt"

# Google OAuth + Play API endpoints
GOOGLE_TOKEN_URL = "https://oauth2.googleapis.com/token"
GOOGLE_PURCHASES_URL = (
    "https://androidpublisher.googleapis.com/androidpublisher/v3/applications/"
    "{package}/purchases/subscriptions/{product}/{token}"
)

# Used when the app hasn't been configured yet.
IAP_NOT_CONFIGURED_MESSAGE = "In-app purchase verification is not configured."


class IAPError(Exception):
    """Raised when a purchase cannot be verified (fail closed)."""


def _ms_to_datetime(ms):
    if not ms:
        return None
    try:
        return datetime.fromtimestamp(int(ms) / 1000.0, tz=timezone.utc)
    except (TypeError, ValueError, OSError):
        return None


def _iso_to_datetime(value):
    if not value:
        return None
    try:
        # Play returns RFC3339 with 'Z' suffix and possibly fractional seconds.
        # datetime.fromisoformat handles '2026-08-30T12:34:56.789Z' on Py3.11+,
        # but normalize older behaviour by stripping a trailing 'Z'.
        normalized = value.replace("Z", "+00:00")
        return datetime.fromisoformat(normalized)
    except (TypeError, ValueError):
        return None


# ============================================================
# APPLE APP STORE
# ============================================================

def verify_app_store_receipt(receipt_data):
    """Verify an App Store receipt and return normalized entitlement info.

    Returns ``{"product_id", "transaction_id", "active_until", "store":
    "appstore"}``. Raises ``IAPError`` on any failure (fail closed).
    """
    shared_secret = os.getenv("APPLE_APPSTORE_SHARED_SECRET", "")
    if not shared_secret:
        raise IAPError(IAP_NOT_CONFIGURED_MESSAGE)

    payload = {
        "receipt-data": receipt_data,
        "password": shared_secret,
        "exclude-old-transactions": True,
    }

    for url in (APPLE_VERIFY_URL, APPLE_SANDBOX_VERIFY_URL):
        try:
            response = requests.post(url, json=payload, timeout=15)
            response.raise_for_status()
            body = response.json()
        except requests.RequestException as error:
            logger.warning("App Store verifyReceipt request failed: %s", error)
            raise IAPError("Could not contact the App Store.")

        # status 21007 = production receipt in sandbox (or vice versa);
        # retry the other environment.
        status = body.get("status")
        if status == 21007:
            continue
        if status != 0:
            logger.warning("App Store verifyReceipt returned status %s", status)
            raise IAPError("The App Store did not validate this receipt.")

        receipt_info = body.get("latest_receipt_info") or []

        # Pick the most recent subscription entry (highest expires_date_ms).
        best = None
        for entry in receipt_info:
            if not entry.get("expires_date_ms"):
                continue
            active_until = _ms_to_datetime(entry["expires_date_ms"])
            if (
                best is None
                or best["expires_date_ms"] < int(entry["expires_date_ms"])
            ):
                best = {
                    "expires_date_ms": int(entry["expires_date_ms"]),
                    "product_id": entry.get("product_id"),
                    "transaction_id": entry.get("original_transaction_id")
                    or entry.get("transaction_id"),
                    "active_until": active_until,
                }

        if best is None:
            raise IAPError("No active subscription was found in the receipt.")

        # A non-renewed/cancelled but still-current plan is still active until
        # its expiry; a past-expiry entry grants nothing.
        if best["active_until"] < datetime.now(timezone.utc):
            raise IAPError("The subscription has expired.")

        return {
            "product_id": best["product_id"],
            "transaction_id": best["transaction_id"],
            "active_until": best["active_until"],
            "store": "appstore",
        }

    raise IAPError("Could not validate the receipt in either store environment.")


# ============================================================
# GOOGLE PLAY
# ============================================================

def _google_service_account_path():
    return os.getenv("GOOGLE_PLAY_SERVICE_ACCOUNT_PATH", "") or None


def _google_package_name():
    return os.getenv("GOOGLE_PLAY_PACKAGE_NAME", "") or None


def _google_access_token():
    """Build a signed service-account JWT and exchange it for an OAuth token."""
    path = _google_service_account_path()
    if not path or not os.path.exists(path):
        raise IAPError(IAP_NOT_CONFIGURED_MESSAGE)

    import json

    with open(path, "r", encoding="utf-8") as handle:
        creds = json.load(handle)

    client_email = creds.get("client_email")
    private_key = creds.get("private_key")
    token_uri = creds.get("token_uri") or GOOGLE_TOKEN_URL
    if not client_email or not private_key:
        raise IAPError("Invalid Google service-account key.")

    now = int(time.time())
    assertion = jwt.encode(
        {
            "iss": client_email,
            "scope": "https://www.googleapis.com/auth/androidpublisher",
            "aud": token_uri,
            "iat": now,
            "exp": now + 3600,
        },
        private_key,
        algorithm="RS256",
    )

    try:
        response = requests.post(
            token_uri,
            data={
                "grant_type": (
                    "urn:ietf:params:oauth:grant-type:jwt-bearer"
                ),
                "assertion": assertion,
            },
            timeout=15,
        )
        response.raise_for_status()
        return response.json()["access_token"]
    except (requests.RequestException, KeyError, ValueError) as error:
        logger.warning("Google OAuth token exchange failed: %s", error)
        raise IAPError("Could not authenticate with Google Play.")


def verify_google_subscription(subscription_id, purchase_token):
    """Verify a Play subscription purchase and return normalized entitlement.

    Raises ``IAPError`` on any failure (fail closed).
    """
    package_name = _google_package_name()
    token = _google_access_token()

    if not package_name:
        raise IAPError(IAP_NOT_CONFIGURED_MESSAGE)

    url = GOOGLE_PURCHASES_URL.format(
        package=package_name,
        product=subscription_id,
        token=purchase_token,
    )

    try:
        response = requests.get(
            url,
            headers={"Authorization": "Bearer " + token},
            timeout=15,
        )
        if response.status_code == 404:
            raise IAPError("The Google Play purchase was not found.")
        response.raise_for_status()
        body = response.json()
    except requests.RequestException as error:
        logger.warning("Google Play subscription check failed: %s", error)
        raise IAPError("Could not contact Google Play.")

    payment_state = body.get("paymentState")
    # 0 = payment pending, 1 = payment received, 2 = free trial
    if payment_state is not None and int(payment_state) != 1 and int(payment_state) != 2:
        raise IAPError("The Google Play purchase has not been paid.")

    active_until = _iso_to_datetime(body.get("expiryTimeMillis"))
    if active_until is None:
        raise IAPError("Google Play did not report an expiry date.")

    now = datetime.now(timezone.utc)
    if active_until < now:
        raise IAPError("The subscription has expired.")

    return {
        "product_id": subscription_id,
        "transaction_id": body.get("orderId") or purchase_token,
        "active_until": active_until,
        "store": "googleplay",
    }
