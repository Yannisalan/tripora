"""Phase-2 hardening tests (SECURITY_HARDENING_REPORT.md, phase 2).

Covers: email verification (TRP-15), re-authenticated account deletion
(TRP-16), admin accounts + mandatory TOTP (TRP-17), proxy/IP handling
(TRP-10), limiter semantics (TRP-18; the Redis backend itself is exercised in
test_redis_rate_limiter.py), refresh-token rotation race, reset-token storage
(TRP-22), Apple nonce (TRP-23), the platform-wide AI budget and the CSP
report endpoint. Synthetic data only; AI, weather and email are stubbed.
"""

from datetime import datetime, timedelta

import pytest
from sqlalchemy import text, update

import routes.auth as auth_module
from config.database import db
from models.activity_log import ActivityLog
from models.admin_security import (
    AdminAuditLog,
    AdminMfa,
    AdminRecoveryCode,
    AdminSession,
)
from models.expense import Expense
from models.trip import Trip
from models.user import User
from models.user_refresh_token import UserRefreshToken
from models.weather_cache import WeatherCache
from services import admin_auth

from .helpers import (
    auth_headers,
    create_logged_in_user,
    create_trip_and_get_id,
    delete_account,
    last_verification_code,
    login,
    register,
    verify_email,
)
from .test_audit_remediation import production_limits  # noqa: F401


def _user(email):
    db.session.expire_all()
    return User.query.filter_by(email=email).first()


def _signup_unverified(client, email="new@example.com", password="supersecret1"):
    assert register(client, name="New", email=email, password=password).status_code == 201
    resp = login(client, email, password)
    assert resp.status_code == 200, resp.get_json()
    return resp.get_json()


TRIP = {
    "destination": "Paris", "startDate": "2026-09-01", "endDate": "2026-09-03",
    "travelers": 1, "budget": "moderate",
}


# ======================================================================
# TRP-15  EMAIL VERIFICATION
# ======================================================================

class TestEmailVerification:

    def test_new_account_is_unverified_and_blocked_from_features(self, client):
        body = _signup_unverified(client)
        headers = auth_headers(body["accessToken"])

        assert body["user"]["emailVerified"] is False
        assert _user("new@example.com").email_verified is False

        for method, path, payload in [
            ("post", "/api/trips/generate", TRIP),
            ("get", "/api/trips", None),
            ("post", "/api/trips/1/expenses", {"amount": 1}),
            ("post", "/api/travel/flights/prices", {}),
            ("get", "/api/trips/1/weather", None),
        ]:
            resp = getattr(client, method)(path, json=payload, headers=headers)
            assert resp.status_code == 403, (path, resp.get_json())
            assert resp.get_json()["error"] == "email_unverified"

        # Account basics stay available.
        assert client.get("/api/auth/me", headers=headers).status_code == 200

    def test_correct_code_verifies_and_unlocks(self, client):
        body = _signup_unverified(client)
        verify_email(client, body["accessToken"], "new@example.com")
        assert _user("new@example.com").email_verified is True
        resp = client.post(
            "/api/trips/generate", json=TRIP,
            headers=auth_headers(body["accessToken"]),
        )
        assert resp.status_code == 200, resp.get_json()

    def test_code_is_stored_hashed_only(self, client):
        _signup_unverified(client)
        user = _user("new@example.com")
        code = last_verification_code("new@example.com")
        assert user.email_verification_code_hash
        assert code not in user.email_verification_code_hash

    def test_code_is_single_use(self, client):
        body = _signup_unverified(client)
        headers = auth_headers(body["accessToken"])
        code = last_verification_code("new@example.com")
        first = client.post("/api/auth/verify-email", json={"code": code}, headers=headers)
        assert first.status_code == 200
        user = _user("new@example.com")
        assert user.email_verification_code_hash is None
        again = client.post("/api/auth/verify-email", json={"code": code}, headers=headers)
        assert again.get_json().get("alreadyVerified") is True

    def test_wrong_codes_lock_out_after_five(self, client):
        body = _signup_unverified(client)
        headers = auth_headers(body["accessToken"])
        good = last_verification_code("new@example.com")
        wrong = "000000" if good != "000000" else "111111"
        for _ in range(5):
            resp = client.post("/api/auth/verify-email", json={"code": wrong}, headers=headers)
            assert resp.status_code == 400
        resp = client.post("/api/auth/verify-email", json={"code": good}, headers=headers)
        assert resp.status_code == 400
        assert resp.get_json()["error"] == "code_expired"
        assert _user("new@example.com").email_verified is False

    def test_expired_code_is_rejected(self, client):
        body = _signup_unverified(client)
        user = _user("new@example.com")
        user.email_verification_expires_at = datetime.utcnow() - timedelta(seconds=1)
        db.session.commit()
        resp = client.post(
            "/api/auth/verify-email",
            json={"code": last_verification_code("new@example.com")},
            headers=auth_headers(body["accessToken"]),
        )
        assert resp.status_code == 400
        assert resp.get_json()["error"] == "code_expired"

    def test_cannot_verify_with_someone_elses_code(self, client):
        a = _signup_unverified(client, email="a@example.com")
        _signup_unverified(client, email="b@example.com")
        resp = client.post(
            "/api/auth/verify-email",
            json={"code": last_verification_code("b@example.com")},
            headers=auth_headers(a["accessToken"]),
        )
        codes_differ = (
            last_verification_code("a@example.com")
            != last_verification_code("b@example.com")
        )
        if codes_differ:
            assert resp.status_code == 400
            assert _user("a@example.com").email_verified is False

    def test_verify_requires_authentication(self, client):
        assert client.post("/api/auth/verify-email", json={"code": "123456"}).status_code == 401
        assert client.post("/api/auth/verify-email/resend").status_code == 401

    def test_resend_cooldown_and_rotation(self, client):
        body = _signup_unverified(client)
        headers = auth_headers(body["accessToken"])
        first_code = last_verification_code("new@example.com")

        cooldown = client.post("/api/auth/verify-email/resend", headers=headers)
        assert cooldown.status_code == 429
        assert cooldown.headers.get("Retry-After")

        user = _user("new@example.com")
        user.email_verification_sent_at = datetime.utcnow() - timedelta(minutes=5)
        db.session.commit()

        resent = client.post("/api/auth/verify-email/resend", headers=headers)
        assert resent.status_code == 200
        new_code = last_verification_code("new@example.com")
        if new_code != first_code:
            old = client.post("/api/auth/verify-email", json={"code": first_code}, headers=headers)
            assert old.status_code == 400
        assert client.post(
            "/api/auth/verify-email", json={"code": new_code}, headers=headers
        ).status_code == 200

    def test_client_cannot_set_verified_flag(self, client):
        body = _signup_unverified(client)
        client.patch(
            "/api/auth/me",
            json={"emailVerified": True, "email_verified": True, "name": "X"},
            headers=auth_headers(body["accessToken"]),
        )
        assert _user("new@example.com").email_verified is False

    def test_register_existing_verified_account_is_indistinguishable(self, client):
        create_logged_in_user(client, name="Owner", email="owner@example.com")
        original_hash = _user("owner@example.com").password_hash

        fresh = register(client, name="X", email="fresh@example.com")
        dup = register(client, name="Mallory", email="owner@example.com",
                       password="attacker-pass-1")

        assert dup.status_code == fresh.status_code == 201
        assert dup.get_json() == fresh.get_json()
        owner = _user("owner@example.com")
        assert owner.password_hash == original_hash
        assert owner.name == "Owner"
        assert login(client, "owner@example.com", "attacker-pass-1").status_code == 401

    def test_unverified_squatter_is_evicted_by_reregistration(self, client):
        # Attacker pre-registers the victim's address (cannot verify it).
        squatter = _signup_unverified(client, email="victim@example.com",
                                      password="attacker-pass-1")
        # Victim registers for real and verifies with their own password.
        assert register(client, name="Victim", email="victim@example.com",
                        password="victim-pass-1").status_code == 201
        victim = login(client, "victim@example.com", "victim-pass-1").get_json()
        verify_email(client, victim["accessToken"], "victim@example.com")

        # Attacker's password and session no longer work.
        assert login(client, "victim@example.com", "attacker-pass-1").status_code == 401
        assert client.get(
            "/api/auth/me", headers=auth_headers(squatter["accessToken"])
        ).status_code == 401
        assert client.post("/api/auth/refresh", json={
            "refreshToken": squatter["refreshToken"]}).status_code == 401

    def test_unverified_user_cannot_change_email(self, client):
        body = _signup_unverified(client)
        resp = client.patch("/api/auth/me", json={
            "email": "elsewhere@example.com", "currentPassword": "supersecret1",
        }, headers=auth_headers(body["accessToken"]))
        assert resp.status_code == 403

    def test_password_reset_proves_inbox_and_verifies(self, client, monkeypatch):
        _signup_unverified(client)
        sent = {}
        monkeypatch.setattr(auth_module, "send_password_reset_code",
                            lambda to, code: sent.setdefault("code", code) or True)
        client.post("/api/auth/forgot-password", json={"email": "new@example.com"})
        token = client.post("/api/auth/forgot-password/verify", json={
            "email": "new@example.com", "code": sent["code"]}).get_json()["resetToken"]
        assert client.post("/api/auth/reset-password", json={
            "resetToken": token, "password": "brand-new-pass-1"}).status_code == 200
        assert _user("new@example.com").email_verified is True

    def test_social_login_requires_provider_verified_email(self, client, monkeypatch):
        def _claims(verified):
            def _fake(provider, token, nonce=None):
                return {"provider": "google", "provider_id": "g-1",
                        "email": "soc@example.com", "name": "S",
                        "email_verified": verified, "iat": 0}
            return _fake

        monkeypatch.setattr(auth_module, "verify_identity_token", _claims("true"))
        assert client.post("/api/auth/google", json={"idToken": "x"}).status_code == 403
        monkeypatch.setattr(auth_module, "verify_identity_token", _claims(True))
        ok = client.post("/api/auth/google", json={"idToken": "x"})
        assert ok.status_code == 200
        assert ok.get_json()["user"]["emailVerified"] is True

    def test_verification_endpoints_are_rate_limited(self, client, production_limits):  # noqa: F811
        body = _signup_unverified(client)
        headers = auth_headers(body["accessToken"])
        statuses = [
            client.post("/api/auth/verify-email", json={"code": "999999"},
                        headers=headers).status_code
            for _ in range(15)
        ]
        assert 429 in statuses


# ======================================================================
# TRP-16  ACCOUNT DELETION
# ======================================================================

class TestAccountDeletion:

    def test_requires_password(self, client):
        token = create_logged_in_user(client, name="Del")
        missing = client.delete("/api/auth/account", headers=auth_headers(token))
        assert missing.status_code == 400
        assert missing.get_json()["error"] == "reauth_required"
        wrong = delete_account(client, token, password="not-my-password")
        assert wrong.status_code == 401
        assert _user("del@example.com") is not None

    def test_deletes_everything_owned_with_fk_enforcement(self, app, client):
        engine = db.engine
        with engine.connect() as conn:
            conn.execute(text("PRAGMA foreign_keys=ON"))
            conn.commit()
        try:
            token = create_logged_in_user(client, name="Rich")
            other = create_logged_in_user(client, name="Other")
            uid = _user("rich@example.com").id
            trip_ids = [create_trip_and_get_id(client, token) for _ in range(3)]
            other_trip = create_trip_and_get_id(client, other)
            for trip_id in trip_ids:
                assert client.post(
                    "/api/trips/{}/expenses".format(trip_id),
                    json={"amount": 5, "category": "food", "date": "2026-01-01"},
                    headers=auth_headers(token),
                ).status_code == 201
                db.session.add(WeatherCache(
                    trip_id=trip_id, destination="Paris",
                    start_date=datetime(2026, 9, 1).date(),
                    end_date=datetime(2026, 9, 3).date(),
                    data={}, fetched_at=datetime.utcnow(),
                ))
            db.session.add(ActivityLog(event_type="page_view", path="/x", user_id=uid))
            login(client, "rich@example.com", "supersecret1")  # 2nd refresh token
            db.session.commit()

            assert delete_account(client, token).status_code == 200

            db.session.expire_all()
            assert db.session.get(User, uid) is None
            assert Trip.query.filter_by(user_id=uid).count() == 0
            assert Expense.query.filter_by(user_id=uid).count() == 0
            assert WeatherCache.query.filter(WeatherCache.trip_id.in_(trip_ids)).count() == 0
            assert UserRefreshToken.query.filter_by(user_id=uid).count() == 0
            assert ActivityLog.query.filter_by(user_id=uid).count() == 0
            # The other user's data is untouched.
            assert db.session.get(Trip, other_trip) is not None
            assert client.get("/api/auth/me", headers=auth_headers(other)).status_code == 200
        finally:
            with engine.connect() as conn:
                conn.execute(text("PRAGMA foreign_keys=OFF"))
                conn.commit()

    def test_account_with_no_trips(self, client):
        token = create_logged_in_user(client, name="Empty")
        assert delete_account(client, token).status_code == 200

    def test_admin_account_rows_are_removed(self, client):
        token = create_logged_in_user(client, name="Adm")
        uid = _user("adm@example.com").id
        db.session.add(AdminMfa(user_id=uid, secret_encrypted="x"))
        db.session.add(AdminRecoveryCode(user_id=uid, code_hash="h" * 64))
        db.session.add(AdminSession(user_id=uid, token_hash="t" * 64, state="active",
                                    expires_at=datetime.utcnow() + timedelta(hours=1)))
        db.session.commit()
        assert delete_account(client, token).status_code == 200
        db.session.expire_all()
        assert db.session.get(AdminMfa, uid) is None
        assert AdminSession.query.filter_by(user_id=uid).count() == 0

    def test_tokens_dead_after_deletion(self, client):
        token = create_logged_in_user(client, name="Gone")
        assert delete_account(client, token).status_code == 200
        assert client.get("/api/auth/me", headers=auth_headers(token)).status_code == 401
        assert delete_account(client, token).status_code == 401

    def test_social_only_requires_fresh_matching_provider_token(self, client, monkeypatch):
        now = datetime.utcnow().timestamp()
        state = {"sub": "g-77", "iat": now}

        def _fake(provider, token, nonce=None):
            return {"provider": "google", "provider_id": state["sub"],
                    "email": "s@example.com", "name": "S",
                    "email_verified": True, "iat": state["iat"]}

        monkeypatch.setattr(auth_module, "verify_identity_token", _fake)
        token = client.post("/api/auth/google", json={"idToken": "x"}).get_json()["accessToken"]
        h = auth_headers(token)

        assert client.delete("/api/auth/account", headers=h).status_code == 400
        state["sub"] = "someone-else"
        assert client.delete("/api/auth/account", json={"idToken": "y"}, headers=h).status_code == 401
        state["sub"], state["iat"] = "g-77", now - 3600
        assert client.delete("/api/auth/account", json={"idToken": "y"}, headers=h).status_code == 401
        state["iat"] = datetime.utcnow().timestamp()
        assert client.delete("/api/auth/account", json={"idToken": "y"}, headers=h).status_code == 200

    def test_repeated_attempts_are_rate_limited(self, client, production_limits):  # noqa: F811
        token = create_logged_in_user(client, name="Spam")
        statuses = [delete_account(client, token, password="wrong-pass-x").status_code
                    for _ in range(12)]
        assert 429 in statuses


# ======================================================================
# REFRESH-TOKEN ROTATION RACE
# ======================================================================

def test_concurrent_refresh_with_same_token_revokes_family(client):
    body = _signup_unverified(client)
    raw = body["refreshToken"]
    row = UserRefreshToken.query.filter_by(
        token_hash=auth_module._hash_refresh_token(raw)).one()
    # Simulate a concurrent request consuming the token between this
    # request's read and its update: the ORM object stays stale.
    db.session.execute(
        update(UserRefreshToken).where(UserRefreshToken.id == row.id)
        .values(revoked_at=datetime.utcnow())
        .execution_options(synchronize_session=False)
    )
    assert auth_module._rotate_refresh_token(raw) is None
    db.session.expire_all()
    active = UserRefreshToken.query.filter_by(family_id=row.family_id, revoked_at=None).count()
    assert active == 0


# ======================================================================
# TRP-22  RESET TOKENS: INDEXED SHA-256, LEGACY STILL ACCEPTED
# ======================================================================

def test_legacy_scrypt_reset_token_still_works(client):
    from werkzeug.security import generate_password_hash

    create_logged_in_user(client, name="Legacy")
    user = _user("legacy@example.com")
    user.reset_token_hash = generate_password_hash("legacy-token-value")
    user.reset_token_expires_at = datetime.utcnow() + timedelta(minutes=10)
    db.session.commit()
    resp = client.post("/api/auth/reset-password", json={
        "resetToken": "legacy-token-value", "password": "another-pass-9"})
    assert resp.status_code == 200, resp.get_json()


# ======================================================================
# TRP-23  APPLE NONCE IS MANDATORY
# ======================================================================

def test_apple_requires_nonce(monkeypatch):
    from services import social_auth_service as svc

    monkeypatch.setattr(svc.Config, "apple_client_id", classmethod(lambda cls: "com.tripora"))
    monkeypatch.setattr(svc, "_extract_kid", lambda token: "kid")

    class _Key:
        key = "k"

    class _Client:
        def __init__(self, url):
            pass

        def get_signing_key(self, kid):
            return _Key()

    monkeypatch.setattr(svc.pyjwt, "PyJWKClient", _Client)
    monkeypatch.setattr(svc.pyjwt, "decode", lambda *a, **k: {
        "sub": "a", "email": "a@privaterelay.appleid.com", "nonce": "abc"})
    with pytest.raises(svc.SocialAuthError):
        svc.verify_apple("header.payload.sig", nonce=None)


# ======================================================================
# TRP-17  ADMIN ACCOUNTS + MANDATORY TOTP
# ======================================================================

def test_totp_matches_rfc6238_vectors():
    secret = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"  # "12345678901234567890"
    assert admin_auth.totp_code(secret, step=59 // 30) == "287082"
    assert admin_auth.totp_code(secret, step=1111111109 // 30) == "081804"
    assert admin_auth.match_totp(secret, "287082", now=59) == 1
    assert admin_auth.match_totp(secret, "287082", last_used_step=1, now=59) is None


def _make_admin(app, client, name="Root"):
    create_logged_in_user(client, name=name)
    email = "{}@example.com".format(name.lower())
    result = app.test_cli_runner().invoke(args=["admin", "grant", email])
    assert result.exit_code == 0, result.output
    return email


def _admin_session(client, email, password="supersecret1"):
    pending = client.post("/api/admin/auth/login", json={
        "email": email, "password": password}).get_json()
    setup = client.post("/api/admin/auth/mfa/setup", json={
        "pendingToken": pending["pendingToken"]}).get_json()
    done = client.post("/api/admin/auth/mfa/activate", json={
        "pendingToken": pending["pendingToken"],
        "code": admin_auth.totp_code(setup["secret"]),
    })
    assert done.status_code == 200, done.get_json()
    return done.get_json(), setup["secret"]


class TestAdminAuth:

    def test_existing_users_are_not_admins(self, client):
        create_logged_in_user(client, name="Plain")
        assert _user("plain@example.com").role == "user"
        resp = client.post("/api/admin/auth/login", json={
            "email": "plain@example.com", "password": "supersecret1"})
        assert resp.status_code == 401

    def test_role_cannot_be_set_through_the_api(self, client):
        token = create_logged_in_user(client, name="Climber")
        client.patch("/api/auth/me", json={"role": "admin", "name": "C"},
                     headers=auth_headers(token))
        assert register(client, name="R", email="r@example.com", role="admin").status_code == 201
        assert _user("climber@example.com").role == "user"
        assert _user("r@example.com").role == "user"

    def test_full_enrollment_and_access(self, app, client):
        email = _make_admin(app, client)
        body, _ = _admin_session(client, email)
        assert len(body["recoveryCodes"]) == 10
        h = auth_headers(body["sessionToken"])
        assert client.get("/api/admin/stats", headers=h).status_code == 200
        assert client.get("/api/admin/users", headers=h).status_code == 200
        actions = {r.action for r in AdminAuditLog.query.all()}
        assert {"login_password_ok", "mfa_enrolled", "access"} <= actions

    def test_pending_token_cannot_access_admin_data(self, app, client):
        email = _make_admin(app, client)
        pending = client.post("/api/admin/auth/login", json={
            "email": email, "password": "supersecret1"}).get_json()["pendingToken"]
        assert client.get("/api/admin/stats", headers=auth_headers(pending)).status_code == 401

    def test_user_jwt_is_not_an_admin_credential(self, app, client):
        email = _make_admin(app, client)
        token = login(client, email, "supersecret1").get_json()["accessToken"]
        assert client.get("/api/admin/stats", headers=auth_headers(token)).status_code == 401

    def test_wrong_password_and_wrong_codes(self, app, client):
        email = _make_admin(app, client)
        assert client.post("/api/admin/auth/login", json={
            "email": email, "password": "bad-password-1"}).status_code == 401
        _, secret = _admin_session(client, email)

        pending = client.post("/api/admin/auth/login", json={
            "email": email, "password": "supersecret1"}).get_json()
        assert pending["mfaEnrolled"] is True
        for _ in range(5):
            assert client.post("/api/admin/auth/mfa/verify", json={
                "pendingToken": pending["pendingToken"], "code": "000000"}).status_code == 401
        # Session burned after 5 failures even with a valid code now.
        assert client.post("/api/admin/auth/mfa/verify", json={
            "pendingToken": pending["pendingToken"],
            "code": admin_auth.totp_code(secret, admin_auth.current_step() + 1),
        }).status_code == 401

    def test_totp_code_cannot_be_replayed(self, app, client):
        email = _make_admin(app, client)
        _, secret = _admin_session(client, email)
        code = admin_auth.totp_code(secret, admin_auth.current_step() + 1)

        def attempt():
            p = client.post("/api/admin/auth/login", json={
                "email": email, "password": "supersecret1"}).get_json()
            return client.post("/api/admin/auth/mfa/verify", json={
                "pendingToken": p["pendingToken"], "code": code}).status_code

        assert attempt() == 200
        assert attempt() == 401

    def test_recovery_code_is_single_use(self, app, client):
        email = _make_admin(app, client)
        body, _ = _admin_session(client, email)
        code = body["recoveryCodes"][0]

        def attempt():
            p = client.post("/api/admin/auth/login", json={
                "email": email, "password": "supersecret1"}).get_json()
            return client.post("/api/admin/auth/mfa/verify", json={
                "pendingToken": p["pendingToken"], "recoveryCode": code}).status_code

        assert attempt() == 200
        assert attempt() == 401

    def test_logout_and_password_change_end_admin_sessions(self, app, client):
        email = _make_admin(app, client)
        body, _ = _admin_session(client, email)
        h = auth_headers(body["sessionToken"])
        assert client.post("/api/admin/auth/logout", headers=h).status_code == 200
        assert client.get("/api/admin/stats", headers=h).status_code == 401

        body, _ = _admin_session_after_enrolled(client, email, app)
        h = auth_headers(body["sessionToken"])
        user_token = login(client, email, "supersecret1").get_json()["accessToken"]
        assert client.patch("/api/auth/me", json={
            "password": "a-new-password-2", "currentPassword": "supersecret1",
        }, headers=auth_headers(user_token)).status_code == 200
        assert client.get("/api/admin/stats", headers=h).status_code == 401

    def test_idle_timeout(self, app, client):
        email = _make_admin(app, client)
        body, _ = _admin_session(client, email)
        AdminSession.query.filter_by(state="active").update(
            {AdminSession.last_seen_at: datetime.utcnow() - timedelta(hours=2)})
        db.session.commit()
        assert client.get("/api/admin/stats", headers=auth_headers(body["sessionToken"])).status_code == 401

    def test_enrollment_window_closes(self, app, client):
        email = _make_admin(app, client)
        uid = _user(email).id
        mfa = db.session.get(AdminMfa, uid)
        mfa.created_at = datetime.utcnow() - timedelta(hours=25)
        db.session.commit()
        assert client.post("/api/admin/auth/login", json={
            "email": email, "password": "supersecret1"}).status_code == 403

    def test_role_revocation_kills_access(self, app, client):
        email = _make_admin(app, client)
        body, _ = _admin_session(client, email)
        app.test_cli_runner().invoke(args=["admin", "revoke", email])
        assert client.get("/api/admin/stats",
                          headers=auth_headers(body["sessionToken"])).status_code == 401

    def test_secret_is_encrypted_at_rest(self, app, client):
        email = _make_admin(app, client)
        _, secret = _admin_session(client, email)
        stored = db.session.get(AdminMfa, _user(email).id).secret_encrypted
        assert secret not in stored

    def test_mfa_unavailable_without_key(self, app, client, monkeypatch):
        email = _make_admin(app, client)
        monkeypatch.delenv("MFA_ENCRYPTION_KEY")
        assert client.post("/api/admin/auth/login", json={
            "email": email, "password": "supersecret1"}).status_code == 503

    def test_legacy_token_can_be_disabled(self, client, monkeypatch):
        import config.settings as settings_mod

        legacy = auth_headers("tripora-test-admin-token")
        assert client.get("/api/admin/stats", headers=legacy).status_code == 200
        assert AdminAuditLog.query.filter_by(action="legacy_token_access").count() == 1
        monkeypatch.setattr(settings_mod.Config, "ADMIN_LEGACY_TOKEN_ENABLED", False)
        assert client.get("/api/admin/stats", headers=legacy).status_code == 401

    def test_admin_login_is_rate_limited(self, client, production_limits):  # noqa: F811
        statuses = [client.post("/api/admin/auth/login", json={
            "email": "x@example.com", "password": "guess-{}".format(i)}).status_code
            for i in range(15)]
        assert 429 in statuses


def _admin_session_after_enrolled(client, email, app):
    """Sign in again with a fresh TOTP step (account already enrolled)."""
    uid = _user(email).id
    mfa = db.session.get(AdminMfa, uid)
    secret = admin_auth.decrypt_secret(mfa.secret_encrypted)
    pending = client.post("/api/admin/auth/login", json={
        "email": email, "password": "supersecret1"}).get_json()
    resp = client.post("/api/admin/auth/mfa/verify", json={
        "pendingToken": pending["pendingToken"],
        "code": admin_auth.totp_code(secret, admin_auth.current_step() + 1),
    })
    assert resp.status_code == 200, resp.get_json()
    return resp.get_json(), secret


# ======================================================================
# TRP-10  PROXY / CLIENT IP
# ======================================================================

def _proxied_app(monkeypatch, hops):
    import app as app_module
    import config.settings as settings_mod

    monkeypatch.setattr(settings_mod.Config, "TRUSTED_PROXY_HOPS", hops)
    return app_module.create_app()


@pytest.mark.parametrize("hops,xff,remote,expected", [
    (0, None, "198.51.100.1", "198.51.100.1"),                 # direct
    (0, "6.6.6.6", "198.51.100.1", "198.51.100.1"),            # spoof ignored
    (1, "6.6.6.6, 203.0.113.9", "10.0.0.1", "203.0.113.9"),    # one trusted hop
    (2, "6.6.6.6, 203.0.113.9, 10.1.1.1", "10.0.0.1", "203.0.113.9"),  # two hops
    (1, "not-an-ip", "10.0.0.1", "10.0.0.1"),                  # malformed -> peer
    (1, "", "10.0.0.1", "10.0.0.1"),                           # empty header
    (2, "203.0.113.9", "10.0.0.1", "10.0.0.1"),                # fewer entries than hops
    (1, "::ffff:203.0.113.5", "10.0.0.1", "203.0.113.5"),      # v4-mapped v6
])
def test_client_ip_resolution(app, monkeypatch, hops, xff, remote, expected):
    from services.client_ip import client_ip

    proxied = _proxied_app(monkeypatch, hops)
    headers = {"X-Forwarded-For": xff} if xff is not None else {}
    seen = {}

    @proxied.route("/__ip_probe")
    def _probe():
        seen["ip"] = client_ip()
        return "", 204

    proxied.test_client().get(
        "/__ip_probe", headers=headers, environ_base={"REMOTE_ADDR": remote})
    assert seen["ip"] == expected


def test_ipv6_clients_share_a_per_64_budget(app):
    from services.client_ip import rate_limit_ip_key

    keys = set()
    for suffix in ("1", "2", "ffff:1"):
        with app.test_request_context(
            "/", environ_base={"REMOTE_ADDR": "2001:db8:1:2::" + suffix}
        ):
            keys.add(rate_limit_ip_key())
    assert keys == {"2001:db8:1:2::/64"}


def test_login_budget_is_per_real_client_behind_proxy(app, monkeypatch, production_limits):  # noqa: F811
    proxied = _proxied_app(monkeypatch, 1)
    c = proxied.test_client()

    def attempt(client_ip, spoof):
        return c.post("/api/auth/login", json={"email": "z@example.com", "password": "x"},
                      headers={"X-Forwarded-For": "{}, {}".format(spoof, client_ip)},
                      environ_base={"REMOTE_ADDR": "10.0.0.1"}).status_code

    first = [attempt("203.0.113.10", "1.1.1.{}".format(i)) for i in range(12)]
    assert 429 in first                      # rotating the spoofed part does not help
    assert attempt("203.0.113.11", "x") != 429  # a different real client is unaffected


# ======================================================================
# TRP-18  LIMITER SEMANTICS + FAILURE MODES (no Redis needed)
# ======================================================================

class _BrokenStorage:
    def increment(self, *a):
        from services.rate_limiter import StorageError
        raise StorageError("down")

    def clear(self):
        pass


def test_storage_failure_falls_back_to_memory_limits():
    from services.rate_limiter import RateLimiter, RateLimitExceeded

    rl = RateLimiter(buckets={})
    rl.configure_bucket("auth.login", 3, 60)
    rl.use_storage(_BrokenStorage(), failure_mode="fallback",
                   sensitive_buckets={"auth.login"})
    for _ in range(3):
        rl.check("auth.login", "ip:1")
    with pytest.raises(RateLimitExceeded):
        rl.check("auth.login", "ip:1")


def test_storage_failure_closed_mode_rejects_sensitive_buckets_only():
    from services.rate_limiter import RateLimiter, RateLimitUnavailable

    rl = RateLimiter(buckets={})
    rl.configure_bucket("auth.login", 3, 60)
    rl.configure_bucket("DEFAULT_READ", 3, 60)
    rl.use_storage(_BrokenStorage(), failure_mode="closed",
                   sensitive_buckets={"auth.login"})
    with pytest.raises(RateLimitUnavailable):
        rl.check("auth.login", "ip:1")
    assert rl.check("DEFAULT_READ", "ip:1")["remaining"] == 2


def test_closed_mode_returns_503(client, production_limits, monkeypatch):  # noqa: F811
    from services.rate_limiter import limiter

    old = (limiter.storage, limiter.failure_mode, limiter.sensitive_buckets)
    limiter.use_storage(_BrokenStorage(), failure_mode="closed",
                        sensitive_buckets={"auth.login"})
    try:
        resp = client.post("/api/auth/login", json={"email": "a@b.co", "password": "x"})
        assert resp.status_code == 503
    finally:
        limiter.use_storage(old[0], failure_mode=old[1], sensitive_buckets=old[2])


def test_platform_wide_ai_budget(client, production_limits):  # noqa: F811
    from services.rate_limiter import limiter

    limiter.configure_bucket("AI_GLOBAL", 3, 3600)
    tokens = [create_logged_in_user(client, name="Ai{}".format(i)) for i in range(4)]
    statuses = [client.post("/api/trips/generate", json=TRIP,
                            headers=auth_headers(t)).status_code for t in tokens]
    assert statuses[:3] == [200, 200, 200]
    assert statuses[3] == 429


# ======================================================================
# CSP REPORTS
# ======================================================================

def test_csp_report_endpoint(client, caplog):
    report = {"csp-report": {
        "document-uri": "https://app.example/trips?token=secret",
        "violated-directive": "script-src",
        "blocked-uri": "https://evil.example/x.js?k=v",
    }}
    resp = client.post("/api/csp-report", json=report,
                       headers={"Content-Type": "application/csp-report"})
    assert resp.status_code == 204
    assert "secret" not in caplog.text and "k=v" not in caplog.text
    big = client.post("/api/csp-report", data="x" * 20000,
                      headers={"Content-Type": "application/csp-report"})
    assert big.status_code == 413
