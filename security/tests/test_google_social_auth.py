"""Google Sign-In backend flow: verification, account linking, JWT issuance.

Covers the contract of ``POST /api/auth/google`` (and the shared
``/api/auth/social`` pipeline it reuses):

* New Google identity -> Tripora account is created and a session JWT issued.
* Returning Google identity -> the existing account is reused (no duplicates).
* Existing email/password account with the same verified email -> the Google
  identity is linked to it (the Google ID token proves control of the email),
  and the user can keep signing in with their password too.
* Provider conflict -> 409, never a silent duplicate/hijack.
* Invalid / missing / malformed tokens -> safe 400/401 responses.
* The email used comes from the *verified token claims*, never from the client.

The Google ID token verification is stubbed (``routes.auth.verify_identity_token``
is monkeypatched) exactly like the Gemini stub in conftest — verification
itself is covered by the real ``google-auth`` library and is out of scope here.
"""

import pytest

import routes.auth as auth_module
from models.user import User
from config.database import db
from services.social_auth_service import SocialAuthError


# ----------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------

def _google_claims(sub="google-user-123", email="traveler@gmail.com",
                   name="Google Traveler", email_verified=True, **overrides):
    """Claims in the exact shape returned by ``verify_google``."""
    claims = {
        "provider": "google",
        "provider_id": sub,
        "email": email,
        "name": name,
        "email_verified": email_verified,
        "aud": "tripora-web-client.apps.googleusercontent.com",
    }
    claims.update(overrides)
    return claims


@pytest.fixture
def stub_google(monkeypatch):
    """Make ``verify_identity_token`` return the passed-in Google claims."""

    def _install(claims):
        def _fake(provider, id_token_value, nonce=None):
            assert provider == "google"
            return claims
        monkeypatch.setattr(auth_module, "verify_identity_token", _fake)
        return claims

    return _install


@pytest.fixture
def reject_google(monkeypatch):
    """Make verification raise a SocialAuthError for the passed-in token."""

    def _install(raise_error):
        def _fake(provider, id_token_value, nonce=None):
            raise raise_error
        monkeypatch.setattr(auth_module, "verify_identity_token", _fake)

    return _install


def google_login(client, id_token="fa-ke-id-token"):
    """POST /api/auth/google with a bare ID token."""
    return client.post("/api/auth/google", json={"idToken": id_token})


def get_user_by_email(email):
    return User.query.filter_by(email=email).first()


# ----------------------------------------------------------------------
# POST /api/auth/google — new user
# ----------------------------------------------------------------------

class TestNewGoogleUser:
    def test_creates_account_and_returns_jwt(self, client, stub_google):
        stub_google(_google_claims(email="newbie@gmail.com", sub="sub-newbie"))

        resp = google_login(client)

        assert resp.status_code == 200
        body = resp.get_json()
        assert body["success"] is True
        assert body["accessToken"]

        user = get_user_by_email("newbie@gmail.com")
        assert user is not None
        assert user.auth_provider == "google"
        assert user.provider_id == "sub-newbie"
        assert user.email_verified is True
        assert user.password_hash is None  # never stores a password
        assert body["user"]["id"] == user.id
        assert body["user"]["authProvider"] == "google"

    def test_name_from_verified_claims(self, client, stub_google):
        stub_google(_google_claims(name="Ada Lovelace"))

        resp = google_login(client)

        assert resp.status_code == 200
        assert get_user_by_email("traveler@gmail.com").name == "Ada Lovelace"

    def test_google_only_account_cannot_login_with_password(self, client, stub_google):
        stub_google(_google_claims(email="socialonly@gmail.com"))
        google_login(client)

        resp = client.post(
            "/api/auth/login",
            json={"email": "socialonly@gmail.com", "password": "whatever-pass"},
        )

        assert resp.status_code == 401
        assert "social sign-in" in resp.get_json()["message"].lower()


# ----------------------------------------------------------------------
# Returning Google identity
# ----------------------------------------------------------------------

class TestReturningGoogleUser:
    def test_reuses_existing_account(self, client, stub_google):
        stub_google(_google_claims(email="again@gmail.com", sub="sub-again"))

        first = google_login(client)
        second = google_login(client)

        assert first.status_code == 200
        assert second.status_code == 200
        assert first.get_json()["user"]["id"] == second.get_json()["user"]["id"]
        # Exactly one account row exists for the identity.
        rows = User.query.filter_by(
            auth_provider="google", provider_id="sub-again"
        ).all()
        assert len(rows) == 1


# ----------------------------------------------------------------------
# Safe account linking with an existing email/password account
# ----------------------------------------------------------------------

class TestAccountLinking:
    def test_links_existing_password_account_to_google(self, client, stub_google):
        # The user first registers with email/password...
        reg = client.post("/api/auth/register", json={
            "name": "Pat",
            "email": "pat@gmail.com",
            "password": "patsecret1",
        })
        assert reg.status_code == 201

        # ...then signs in with Google using the same verified email.
        stub_google(_google_claims(email="pat@gmail.com", sub="sub-pat"))

        resp = google_login(client)

        assert resp.status_code == 200
        users = User.query.filter_by(email="pat@gmail.com").all()
        assert len(users) == 1  # no duplicate account created
        pat = users[0]
        assert pat.auth_provider == "google"
        assert pat.provider_id == "sub-pat"
        assert pat.password_hash is not None  # password is kept

        # The password login still works on the same account.
        login = client.post(
            "/api/auth/login",
            json={"email": "pat@gmail.com", "password": "patsecret1"},
        )
        assert login.status_code == 200

    def test_email_comes_from_claims_not_payload(self, client, stub_google):
        # Only the token matters: the client cannot steer which account the
        # backend resolves by spoofing the payload.
        stub_google(_google_claims(email="verified@gmail.com", sub="sub-ver"))

        resp = client.post(
            "/api/auth/google",
            json={"idToken": "something", "email": "evil@example.com"},
        )

        assert resp.status_code == 200
        assert resp.get_json()["user"]["email"] == "verified@gmail.com"
        assert get_user_by_email("evil@example.com") is None

    def test_provider_conflict_is_rejected(self, client, stub_google):
        # An account already bound to another provider must reject the Google
        # identity instead of creating a duplicate or hijacking the account.
        existing = User(
            name="Apple User",
            email="conflict@gmail.com",
            password_hash=None,
            email_verified=True,
            auth_provider="apple",
            provider_id="apple-sub-1",
        )
        db.session.add(existing)
        db.session.commit()

        stub_google(_google_claims(email="conflict@gmail.com", sub="g-sub"))

        resp = google_login(client)

        assert resp.status_code == 409
        assert "different" in resp.get_json()["message"].lower()

    def test_unverified_email_is_not_marked_verified(self, client, stub_google):
        stub_google(_google_claims(email="unverified@gmail.com", email_verified=False))

        resp = google_login(client)

        assert resp.status_code == 200
        assert get_user_by_email("unverified@gmail.com").email_verified is False


# ----------------------------------------------------------------------
# Invalid / missing / malformed inputs
# ----------------------------------------------------------------------

class TestRejectedInputs:
    def test_missing_id_token_is_400(self, client, stub_google):
        resp = client.post("/api/auth/google", json={})
        assert resp.status_code == 400
        assert "identity token" in resp.get_json()["message"].lower()

    def test_non_json_body_is_400(self, client, stub_google):
        resp = client.post(
            "/api/auth/google",
            data="not json",
            content_type="application/json",
        )
        assert resp.status_code == 400

    def test_invalid_token_is_401(self, client, reject_google):
        reject_google(SocialAuthError("Invalid Google ID token."))

        resp = google_login(client, id_token="forged-token")

        assert resp.status_code == 401
        assert "invalid" in resp.get_json()["message"].lower()

    def test_unexpected_verification_failure_is_401(self, client, reject_google):
        reject_google(RuntimeError("boom"))

        resp = google_login(client)

        assert resp.status_code == 401
        assert not resp.get_json()["success"]

    def test_unverified_claims_with_no_email_is_400(self, client, stub_google):
        stub_google(_google_claims(email=None))

        resp = google_login(client)

        assert resp.status_code == 400

    def test_missing_provider_id_is_400(self, client, stub_google):
        stub_google(_google_claims(provider_id=""))

        resp = google_login(client)

        assert resp.status_code == 400
        assert "provider id" in resp.get_json()["message"].lower()


# ----------------------------------------------------------------------
# Generic /api/auth/social remains functional (provider-agnostic path)
# ----------------------------------------------------------------------

class TestGenericSocialEndpoint:
    def test_google_via_generic_endpoint(self, client, stub_google):
        stub_google(_google_claims(email="generic@gmail.com", sub="sub-gen"))

        resp = client.post(
            "/api/auth/social",
            json={"provider": "google", "idToken": "tok"},
        )

        assert resp.status_code == 200
        assert resp.get_json()["user"]["authProvider"] == "google"

    def test_missing_provider_is_400(self, client):
        resp = client.post("/api/auth/social", json={"idToken": "tok"})
        assert resp.status_code == 400
        assert "provider" in resp.get_json()["message"].lower()

    def test_unsupported_provider_is_400(self, client):
        resp = client.post(
            "/api/auth/social",
            json={"provider": "facebook", "idToken": "tok"},
        )
        assert resp.status_code == 400
        assert "unsupported" in resp.get_json()["message"].lower()


# ----------------------------------------------------------------------
# Duplicate protection at the schema level
# ----------------------------------------------------------------------

class TestSchemaEnforcement:
    def test_partial_unique_index_exists_in_models(self, app):
        from sqlalchemy import inspect

        inspector = inspect(db.engine)
        indexes = {
            ix["name"]: ix["column_names"]
            for ix in inspector.get_indexes("users")
        }
        assert "ix_users_social_identity" in indexes
        assert indexes["ix_users_social_identity"] == ["auth_provider", "provider_id"]