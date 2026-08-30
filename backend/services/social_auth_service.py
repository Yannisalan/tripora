"""Server-side verification of Google and Apple identity tokens.

The mobile app obtains an ID/identity token from the native login flow
(Google Sign-In / Sign in with Apple) and sends it to the backend. This
module verifies the token's signature and claims before the backend
issues its own session JWT.

Google tokens are verified with the ``google-auth`` library (which
checks signature, expiry, issuer and audience against Google's keys).
Apple identity tokens are verified with ``PyJWT`` against Apple's public
keys published at ``appleid.apple.com/auth/keys``.
"""

import json
import hashlib
import logging

import jwt as pyjwt
from google.oauth2 import id_token
from google.auth.transport import requests as google_requests

from config.settings import Config

logger = logging.getLogger(__name__)

APPLE_JWKS_URL = "https://appleid.apple.com/auth/keys"
APPLE_ISSUER = "https://appleid.apple.com"

# Maximum number of seconds a token may be older than "now" and still be
# considered valid (skew tolerance).
CLOCK_SKEW_SECONDS = 30


class SocialAuthError(Exception):
    """Raised when a social identity token cannot be verified."""


def _normalise_email(value):
    if not value:
        return None
    return str(value).strip().lower()


def _normalise_provider(provider):
    normalized = str(provider or "").strip().lower()
    if normalized not in {"google", "apple"}:
        raise SocialAuthError("Unsupported social provider.")
    return normalized


# ============================================================
# GOOGLE
# ============================================================

def verify_google(id_token_value):
    """Verify a Google ID token and return its claims.

    The token's ``aud`` must match one of the configured Google OAuth
    client IDs (Android / iOS / Web).
    """
    if not id_token_value or not str(id_token_value).strip():
        raise SocialAuthError("Google ID token is required.")

    accepted_audiences = [
        aud
        for aud in Config.google_client_ids()
        if aud
    ]

    if not accepted_audiences:
        raise SocialAuthError(
            "Google sign-in is not configured on the server."
        )

    request = google_requests.Request()

    last_error = None

    for audience in accepted_audiences:
        try:
            claims = id_token.verify_oauth2_token(
                str(id_token_value).strip(),
                request,
                audience=audience,
                clock_skew_in_seconds=CLOCK_SKEW_SECONDS,
            )
            return _normalise_google_claims(claims, audience)
        except Exception as error:  # noqa: BLE001 - try next audience
            last_error = error
            logger.debug("Google token rejected for audience %s: %s", audience, error)

    raise SocialAuthError(f"Invalid Google ID token. {last_error or ''}")


def _normalise_google_claims(claims, audience):
    email = _normalise_email(claims.get("email"))
    if not email:
        raise SocialAuthError("Google account has no email address.")

    return {
        "provider": "google",
        "provider_id": str(claims.get("sub", "")),
        "email": email,
        "name": str(claims.get("name") or "").strip(),
        "email_verified": bool(claims.get("email_verified")),
        "aud": audience,
    }


# ============================================================
# APPLE
# ============================================================

def verify_apple(identity_token, nonce=None):
    """Verify an Apple identity token and return its claims."""
    if not identity_token or not str(identity_token).strip():
        raise SocialAuthError("Apple identity token is required.")

    client_id = Config.apple_client_id()

    if not client_id:
        raise SocialAuthError("Apple sign-in is not configured on the server.")

    key_id = _extract_kid(str(identity_token).strip())

    if not key_id:
        raise SocialAuthError("Apple identity token is missing its key id.")

    jwks_client = pyjwt.PyJWKClient(APPLE_JWKS_URL)

    try:
        signing_key = jwks_client.get_signing_key(key_id)
    except pyjwt.exceptions.PyJWKClientError as error:
        raise SocialAuthError("Could not resolve Apple signing key.") from error

    try:
        claims = pyjwt.decode(
            str(identity_token).strip(),
            signing_key.key,
            algorithms=["RS256"],
            issuer=APPLE_ISSUER,
            audience=client_id,
            leeway=CLOCK_SKEW_SECONDS,
        )
    except pyjwt.exceptions.InvalidTokenError as error:
        raise SocialAuthError(f"Invalid Apple identity token. {error}") from error

    if nonce:
        expected = hashlib.sha256(str(nonce).encode("utf-8")).hexdigest()
        if claims.get("nonce") != expected:
            raise SocialAuthError("Apple identity token nonce mismatch.")

    return _normalise_apple_claims(claims)


def _extract_kid(identity_token):
    """Extract the ``kid`` from a JWT's unverified header."""
    try:
        import base64

        header_b64 = identity_token.split(".")[0]
        header = json.loads(
            base64.urlsafe_b64decode(header_b64 + "==" * (-len(header_b64) % 4))
        )
        return header.get("kid")
    except Exception:  # noqa: BLE001
        return None


def _normalise_apple_claims(claims):
    email = _normalise_email(claims.get("email"))
    if not email:
        raise SocialAuthError("Apple account has no email address.")

    return {
        "provider": "apple",
        "provider_id": str(claims.get("sub", "")),
        "email": email,
        "name": str(
            (claims.get("name") or {}).get("firstName", "")
            if isinstance(claims.get("name"), dict)
            else claims.get("name") or ""
        ).strip(),
        "email_verified": True,
        "nonce": claims.get("nonce"),
    }


# ============================================================
# DISPATCH
# ============================================================

def verify_identity_token(provider, id_token_value, nonce=None):
    """Verify a provider ID/identity token and return its claims.

    Returns a dict with ``provider``, ``provider_id``, ``email``,
    ``name`` and ``email_verified``.
    """
    provider = _normalise_provider(provider)

    if provider == "google":
        return verify_google(id_token_value)

    if provider == "apple":
        return verify_apple(id_token_value, nonce=nonce)

    raise SocialAuthError("Unsupported social provider.")
