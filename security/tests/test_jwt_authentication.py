"""JWT authentication tests (P1 Authentication bypass / P3 JWT security).

Covers, for protected endpoints:
- request with no token
- empty token
- malformed token
- expired token
- invalid signature
- modified (tampered) token payload
- token belonging to another test user
- access to protected endpoints without authentication

For every case the expected SECURE behaviour is documented in the test
docstring. A test FAILS (signals a vulnerability) only if the server grants
access or misbehaves when it should have rejected the request with 401.

These tests use only synthetic test users and tokens forged with the TEST
secret set in conftest. They never attempt to obtain or guess real users'
credentials or tokens.
"""

import time

import jwt

from .helpers import (
    auth_headers,
    create_logged_in_user,
    forge_algorithm_confusion_token,
    forge_expired_token,
    forge_none_alg_token,
    forge_valid_access_token,
    login,
    register,
)

# The test-only secret used to sign/verify tokens. MUST match the dummy
# JWT_SECRET_KEY set in conftest (Flask app uses Config -> env var).
TEST_SECRET = "tripora-security-test-secret-key-not-for-production"
# Wrong secret (e.g. if the server used a different key, or an attacker
# signed with another secret entirely).
WRONG_SECRET = "some-other-attacker-secret"
# Raw RSA public-key bytes (base64 body, no PEM framing) used only for the
# RS256->HS256 algorithm-confusion check. Represents a victim's public key
# that an attacker would use as the HMAC secret in the confusion attack.
_PUBLIC_KEY = (
    "MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAyX6v39Q1oTR9FxvG3nJrq"
    "khQ5s+WXCsK/yH1VElhWsiFYsz23bywVc7L7QZRyY+TQzU5QrWYI4pR4nVRZMgYqGm"
    "ZQmF7vjDbcdEL6QzcrS6Gd3iTvZQ1fG7I2Z2uNKtVJg+ScsQ5kEICJ+5qvAZ7uMyfQm2"
    "Rj3dC8bW9t6Yk8Vk1yYxVQmYbD5kmC7h0aHXpJ9YLP0QyQzU5QrWYI4pR4nVRZMgYqGm"
    "ZQmF7vjDbcdEL6QzcrS6Gd3iTvZQ1fG7I2Z2uNKtVJg+ScsQ5kEICJ+5qvAZ7uMyfQm"
    "2Rj3dC8bW9t6Yk8Vk1yYxVQmYbD5kmC7h0aHXpJ9YLP0QyQzU5QIDAQAB"
)


class TestNoToken:
    """Requests with no Authorization header at all."""

    def test_me_without_token(self, client):
        """GET /api/auth/me with no token -> 401, no user data."""
        resp = client.get("/api/auth/me")
        body = resp.get_json(silent=True) or {}
        assert resp.status_code == 401
        assert body.get("success") is False

    def test_trips_list_without_token(self, client):
        """GET /api/trips with no token -> 401, no trip data."""
        resp = client.get("/api/trips")
        assert resp.status_code == 401
        assert (resp.get_json(silent=True) or {}).get("success") is False

    def test_generate_without_token(self, client):
        """POST /api/trips/generate with no token -> 401, no trip created."""
        resp = client.post("/api/trips/generate", json={"destination": "Paris"})
        assert resp.status_code == 401
        assert (resp.get_json(silent=True) or {}).get("success") is False


class TestEmptyToken:
    """Authorization header present but empty / no credential."""

    def test_empty_bearer_value(self, client):
        """'Authorization: Bearer ' (no token text) -> 401."""
        resp = client.get("/api/trips", headers={"Authorization": "Bearer "})
        assert resp.status_code == 401
        assert (resp.get_json(silent=True) or {}).get("success") is False

    def test_bare_header_no_scheme(self, client):
        """'Authorization: <empty>' with no Bearer scheme -> 401."""
        resp = client.get("/api/trips", headers={"Authorization": ""})
        assert resp.status_code == 401


class TestMalformedToken:
    """Tokens that are not structurally valid JWTs."""

    def test_garbage_string(self, client):
        """Random non-JWT string -> 401, no data returned."""
        resp = client.get("/api/trips", headers=auth_headers("this-is-not-a-jwt"))
        assert resp.status_code == 401
        assert (resp.get_json(silent=True) or {}).get("success") is False

    def test_base64_none_header(self, client):
        """Header decoding to 'null' (alg none with malformed body) -> 401."""
        token = "eyJhbGciOiJub25lIn0."  # {"alg":"none"} + empty payload + empty sig
        resp = client.get("/api/trips", headers=auth_headers(token))
        assert resp.status_code == 401

    def test_jwt_with_tampered_structure(self, client):
        """A token that decodes but has invalid claim types -> 401."""
        # Header claims sub is a list (wrong type); this must not be accepted.
        malformed = jwt.encode(
            {"sub": ["1"], "iat": int(time.time()), "type": "access"},
            TEST_SECRET,
            algorithm="HS256",
        )
        resp = client.get("/api/trips", headers=auth_headers(malformed))
        # The identity cannot be cast to an int -> must be rejected (401 or 404),
        # never 200.
        assert resp.status_code in (401, 404)
        assert (resp.get_json(silent=True) or {}).get("success") is False


class TestExpiredToken:
    """Tokens whose exp is in the past."""

    def test_expired_token_rejected(self, client):
        """An already-expired access token -> 401 expired-session, no data."""
        expired = forge_expired_token("99999", TEST_SECRET)
        resp = client.get("/api/trips", headers=auth_headers(expired))
        body = resp.get_json(silent=True) or {}
        assert resp.status_code == 401
        assert body.get("success") is False


class TestInvalidSignature:
    """Tokens signed with the wrong secret."""

    def test_wrong_signature_rejected(self, client):
        """A token signed with an unknown secret -> 401 invalid session."""
        forged = forge_valid_access_token("99999", WRONG_SECRET)
        resp = client.get("/api/trips", headers=auth_headers(forged))
        assert resp.status_code == 401
        assert (resp.get_json(silent=True) or {}).get("success") is False

    def test_none_alg_rejected(self, client):
        """A token with alg 'none' (unsigned) -> 401."""
        token = forge_none_alg_token("99999")
        resp = client.get("/api/trips", headers=auth_headers(token))
        assert resp.status_code == 401

    def test_algorithm_confusion_rejected(self, client):
        """RS256->HS256 algorithm-confusion token -> 401.

        An attacker who knows the RSA public key signs an HS256 token using
        those public-key bytes as the HMAC secret. If the server verified it,
        that would be algorithm confusion. The server only verifies HS256 with
        its own secret, so this must be rejected.
        """
        token = forge_algorithm_confusion_token("99999", _PUBLIC_KEY)
        resp = client.get("/api/trips", headers=auth_headers(token))
        assert resp.status_code == 401


class TestModifiedPayload:
    """Tokens whose claims were altered after signing (signature mismatch)."""

    def test_tampered_sub_rejected(self, client):
        """Change 'sub' (user id) of a valid token without re-signing -> 401."""
        valid = forge_valid_access_token("1", TEST_SECRET)
        parts = valid.split(".")
        # Decode payload, change sub to a different victim id, re-encode
        # WITHOUT a fresh signature (keep original signature).
        import json as _json
        import base64

        def b64url_decode(s):
            pad = "=" * (-len(s) % 4)
            return base64.urlsafe_b64decode(s + pad)

        payload = _json.loads(b64url_decode(parts[1]))
        payload["sub"] = "99999"  # try to impersonate another user
        raw = _json.dumps(payload, separators=(",", ":")).encode()
        new_payload = base64.urlsafe_b64encode(raw).rstrip(b"=").decode()
        tampered = parts[0] + "." + new_payload + "." + parts[2]  # keep old sig
        resp = client.get("/api/trips", headers=auth_headers(tampered))
        # Signature no longer matches -> rejected.
        assert resp.status_code == 401
        assert (resp.get_json(silent=True) or {}).get("success") is False

    def test_tampered_iat_rejected(self, client):
        """Alter 'iat' without re-signing -> 401 (signature mismatch)."""
        import json as _json
        import base64

        valid = forge_valid_access_token("1", TEST_SECRET)
        parts = valid.split(".")

        def b64url_decode(s):
            pad = "=" * (-len(s) % 4)
            return base64.urlsafe_b64decode(s + pad)

        payload = _json.loads(b64url_decode(parts[1]))
        payload["iat"] = int(time.time()) - 999999
        raw = _json.dumps(payload, separators=(",", ":")).encode()
        new_payload = base64.urlsafe_b64encode(raw).rstrip(b"=").decode()
        tampered = parts[0] + "." + new_payload + "." + parts[2]
        resp = client.get("/api/trips", headers=auth_headers(tampered))
        assert resp.status_code == 401


class TestOtherUsersToken:
    """A token for a different (real, but test) user cannot be used alone."""

    def test_token_identity_scoped_to_that_user(self, client):
        """A valid token for user B is accepted as *that* user, not privileged.

        Secure behaviour: the token grants access to the user specified in the
        token only; it does not grant access to any other account's data.
        """
        token_b = create_logged_in_user(client, name="Bob")
        # /api/auth/me must return Bob, not some default/other user.
        resp = client.get("/api/auth/me", headers=auth_headers(token_b))
        assert resp.status_code == 200
        assert resp.get_json()["user"]["email"] == "bob@example.com"

    def test_token_of_user_a_cannot_access_user_b_data(self, client):
        """User A's token must not enumerate User B's trips.

        Covered in detail by the IDOR tests; here we assert the JWT itself
        does not leak another session's data through /api/auth/me.
        """
        token_a = create_logged_in_user(client, name="Alice")
        create_logged_in_user(client, name="Charlie")  # creates a second user
        resp = client.get("/api/auth/me", headers=auth_headers(token_a))
        assert resp.status_code == 200
        assert resp.get_json()["user"]["email"] == "alice@example.com"


class TestProtectionOfSensitiveRoutes:
    """Explicit checks that all protected endpoints require auth."""

    PROTECTED = [
        ("GET", "/api/auth/me"),
        ("PATCH", "/api/auth/me"),
        ("POST", "/api/trips/generate"),
        ("GET", "/api/trips"),
        ("GET", "/api/trips/1"),
        ("PATCH", "/api/trips/1"),
        ("DELETE", "/api/trips/1"),
        ("POST", "/api/trips/1/regenerate"),
    ]

    def test_all_protected_endpoints_reject_unauthenticated(self, client):
        """Every JWT-protected endpoint -> 401 without a token."""
        for method, path in self.PROTECTED:
            resp = client.open(path, method=method, json={} if method in (
                "POST", "PATCH",
            ) else None)
            assert resp.status_code == 401, (
                "{} {} was not protected (got {})".format(method, path, resp.status_code)
            )

    def test_public_endpoints_still_work(self, client):
        """Health and home remain public (confirmed reachable/introspected)."""
        assert client.get("/api/health").status_code == 200


class TestAuthenticationFlow:
    """Sanity checks that the auth flow itself functions (control group)."""

    def test_valid_login_returns_token_and_me_works(self, client):
        """A properly registered + logged-in user reaches /me."""
        register(client, name="Dana", email="dana@example.com")
        resp = login(client, "dana@example.com", "supersecret1")
        assert resp.status_code == 200
        token = resp.get_json()["accessToken"]
        me = client.get("/api/auth/me", headers=auth_headers(token))
        assert me.status_code == 200
        assert me.get_json()["user"]["email"] == "dana@example.com"
