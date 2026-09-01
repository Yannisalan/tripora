"""Reusable helpers for Tripora security tests.

Encapsulates the common flows (register, verify email, login, create trip)
and request building so the test modules stay focused on security assertions.
All operations use only synthetic test users and test data.
"""

import time

import jwt


# ----------------------------------------------------------------------
# Registration / verification / login
# ----------------------------------------------------------------------


def register(
    client,
    name="Alice",
    email=None,
    password="supersecret1",
    language="en",
    currency="USD",
    **overrides
):
    """POST /api/auth/register. Returns the Flask response."""
    email = email or "{}@example.com".format(
        name.lower().replace(" ", "").replace("'", "")
    )
    payload = {
        "name": name,
        "email": email,
        "password": password,
        "preferredLanguage": language,
        "preferredCurrency": currency,
    }
    payload.update(overrides)
    return client.post("/api/auth/register", json=payload)


def get_user_by_email(email):
    """Return the User ORM row (via the app DB) or None."""
    from models.user import User

    return User.query.filter_by(email=email).first()


def login(client, email, password):
    """POST /api/auth/login. Returns the Flask response."""
    return client.post("/api/auth/login", json={"email": email, "password": password})


def create_logged_in_user(
    client,
    name="Alice",
    email=None,
    password="supersecret1",
    language="en",
    currency="USD",
):
    """Register and log in a fresh test user.

    Returns the JWT access token string.
    """
    email = email or "{}@example.com".format(
        name.lower().replace(" ", "").replace("'", "")
    )
    reg = register(
        client,
        name=name,
        email=email,
        password=password,
        language=language,
        currency=currency,
    )
    assert reg.status_code == 201, reg.get_json()
    resp = login(client, email, password)
    assert resp.status_code == 200, resp.get_json()
    return resp.get_json()["accessToken"]


# ----------------------------------------------------------------------
# Request building
# ----------------------------------------------------------------------


def auth_headers(token):
    """HTTP headers carrying a Bearer JWT."""
    return {"Authorization": "Bearer {}".format(token)}


def create_trip(client, token, **overrides):
    """POST /api/trips/generate with a valid trip payload."""
    payload = {
        "destination": "Paris",
        "startDate": "2026-09-01",
        "endDate": "2026-09-04",
        "travelers": 2,
        "budget": "moderate",
        "travelStyle": "balanced",
        "interests": ["food", "culture"],
    }
    payload.update(overrides)
    return client.post(
        "/api/trips/generate", json=payload, headers=auth_headers(token)
    )


def create_trip_and_get_id(client, token, **overrides):
    """Create a trip and return its integer id."""
    resp = create_trip(client, token, **overrides)
    assert resp.status_code == 200, resp.get_json()
    return resp.get_json()["trip"]["id"]


# ----------------------------------------------------------------------
# JWT crafting (for forged / malformed token tests)
# ----------------------------------------------------------------------


def _access_claims(sub, now=None, exp_delta=None):
    """Build a Flask-JWT-Extended access-token claim set."""
    now = int(now if now is not None else time.time())
    claims = {
        "sub": str(sub),
        "iat": now,
        "type": "access",
    }
    if exp_delta is not None:
        claims["exp"] = now + exp_delta
    return claims


def forge_valid_access_token(sub, secret, exp_delta=3600):
    """Sign an access token with the given secret (HS256)."""
    return jwt.encode(
        _access_claims(sub, exp_delta=exp_delta), secret, algorithm="HS256"
    )


def forge_expired_token(sub, secret):
    """Sign an already-expired access token (HS256)."""
    claims = _access_claims(sub, exp_delta=-3600)
    return jwt.encode(claims, secret, algorithm="HS256")


def forge_none_alg_token(sub):
    """Forge a token with ``alg: none`` (no signature)."""
    return jwt.encode(_access_claims(sub), key=None, algorithm="none")


def forge_algorithm_confusion_token(sub, public_key):
    """Build an RS256->HS256 algorithm-confusion token.

    Signs the token with HMAC-SHA256 using the victim's RSA *public key*
    bytes as the HMAC secret (the classic algorithm-confusion vector). This
    is assembled manually because recent PyJWT releases refuse to use an
    asymmetric key as an HMAC secret, which would otherwise mask the test.

    The ``public_key`` should be the raw DER/modulus bytes (not a PEM blob).
    """
    import base64
    import hashlib
    import hmac
    import json
    import time

    header = {"alg": "HS256", "typ": "JWT"}
    payload = _access_claims(sub)

    def b64url(data):
        if isinstance(data, str):
            data = data.encode()
        return base64.urlsafe_b64encode(data).rstrip(b"=").decode()

    signing_input = ".".join(
        [b64url(json.dumps(header, separators=(",", ":"))),
         b64url(json.dumps(payload, separators=(",", ":")))]
    )
    if isinstance(public_key, str):
        public_key = public_key.encode()
    sig = hmac.new(public_key, signing_input.encode(), hashlib.sha256).digest()
    return "{}.{}".format(signing_input, b64url(sig))
