"""Regression tests for the 2026-11 security audit (SECURITY_AUDIT_REPORT.md).

Each test names the finding it covers (TRP-xx). They were written BEFORE the
remediation and failed against the original code, demonstrating the weakness;
they pass once the fix is in place. Only synthetic users and data are used,
the AI and weather providers are stubbed by conftest, and nothing leaves the
process.
"""

import pytest
from sqlalchemy import event, text

import routes.auth as auth_module
from config.database import db
from models.activity_log import ActivityLog
from models.user import User
from models.user_refresh_token import UserRefreshToken

from .helpers import (
    auth_headers,
    create_logged_in_user,
    create_trip_and_get_id,
    login,
    register,
)


@pytest.fixture
def production_limits(monkeypatch):
    """Load the real production bucket table from Config into the limiter.

    conftest disables rate limiting for the general suite; these tests must
    exercise exactly what production configures, so gaps in the table are
    caught. The limiter singleton is restored to unlimited afterwards.
    """
    import config.settings as settings_mod
    from services.rate_limiter import limiter

    monkeypatch.setattr(settings_mod.Config, "RATE_LIMIT_ENABLED", True)
    for name, cfg in settings_mod.Config.rate_limit_buckets().items():
        limiter.configure_bucket(name, cfg["limit"], cfg["window"])
    limiter.reset()
    yield
    for name in list(limiter._buckets.keys()):
        limiter.configure_bucket(name, None, 600)
    limiter.reset()


def _swap(client, token, trip_id):
    return client.post(
        "/api/trips/{}/swap-activity".format(trip_id),
        json={"day": 1, "time": "Morning"},
        headers=auth_headers(token),
    )


# ----------------------------------------------------------------------
# TRP-01  AI swap endpoint had no rate limit (unbounded Gemini spend)
# ----------------------------------------------------------------------

def test_trp01_swap_activity_is_rate_limited(client, production_limits):
    token = create_logged_in_user(client, name="Swapper")
    trip_id = create_trip_and_get_id(client, token)

    statuses = [_swap(client, token, trip_id).status_code for _ in range(40)]

    assert 429 in statuses, statuses


# ----------------------------------------------------------------------
# TRP-02  Reset-code verification endpoint was unthrottled (bucket name
#         mismatch: "auth.forgot_password_verify" vs "auth.verify_reset_code")
# ----------------------------------------------------------------------

def test_trp02_reset_code_verification_is_rate_limited(client, production_limits):
    statuses = [
        client.post(
            "/api/auth/forgot-password/verify",
            json={"email": "nobody@example.com", "code": "000000"},
        ).status_code
        for _ in range(20)
    ]

    assert 429 in statuses, statuses


# ----------------------------------------------------------------------
# TRP-03  Third-party-backed endpoints configured with limit=None
# ----------------------------------------------------------------------

@pytest.mark.parametrize("path,method,body", [
    ("/api/travel/flights/prices", "post", {}),
    ("/api/rates/bridge?to=EUR", "get", None),
])
def test_trp03_third_party_endpoints_are_rate_limited(client, production_limits, path, method, body):
    token = create_logged_in_user(client, name="Pricer")
    headers = auth_headers(token)

    statuses = []
    for _ in range(80):
        if method == "post":
            resp = client.post(path, json=body, headers=headers)
        else:
            resp = client.get(path, headers=headers)
        statuses.append(resp.status_code)

    assert 429 in statuses, statuses


# ----------------------------------------------------------------------
# TRP-04  Admin token endpoints were unthrottled (online brute force)
# ----------------------------------------------------------------------

def test_trp04_admin_token_guessing_is_rate_limited(client, production_limits):
    statuses = [
        client.get(
            "/api/admin/login-status",
            headers={"Authorization": "Bearer guess-{}".format(i)},
        ).status_code
        for i in range(30)
    ]
    statuses += [
        client.get(
            "/api/admin/stats",
            headers={"Authorization": "Bearer guess-{}".format(i)},
        ).status_code
        for i in range(30)
    ]

    assert 429 in statuses, statuses


# ----------------------------------------------------------------------
# TRP-05  Email change did not require re-authentication
#         (stolen access token -> change email -> reset password -> ATO)
# ----------------------------------------------------------------------

def test_trp05_email_change_requires_current_password(client):
    token = create_logged_in_user(client, name="Victim")

    resp = client.patch(
        "/api/auth/me",
        json={"email": "attacker@example.com"},
        headers=auth_headers(token),
    )

    assert resp.status_code in (400, 401), resp.get_json()
    assert User.query.filter_by(email="attacker@example.com").first() is None


def test_trp05_email_change_with_current_password_succeeds(client):
    token = create_logged_in_user(client, name="Mover")

    resp = client.patch(
        "/api/auth/me",
        json={
            "email": "mover-new@example.com",
            "currentPassword": "supersecret1",
        },
        headers=auth_headers(token),
    )

    assert resp.status_code == 200, resp.get_json()
    assert resp.get_json()["user"]["email"] == "mover-new@example.com"


def test_trp05_unchanged_email_does_not_require_password(client):
    # The profile screen always re-sends the current email; that must keep
    # working without a password.
    token = create_logged_in_user(client, name="Same")

    resp = client.patch(
        "/api/auth/me",
        json={"name": "Same Name", "email": "same@example.com"},
        headers=auth_headers(token),
    )

    assert resp.status_code == 200, resp.get_json()


# ----------------------------------------------------------------------
# TRP-06  Pre-account-takeover via automatic social linking
# ----------------------------------------------------------------------

def _stub_google(monkeypatch, email, sub="google-sub-victim", verified=True):
    def _fake(provider, id_token_value, nonce=None):
        return {
            "provider": "google",
            "provider_id": sub,
            "email": email,
            "name": "Victim",
            "email_verified": verified,
        }

    monkeypatch.setattr(auth_module, "verify_identity_token", _fake)


def test_trp06_social_login_does_not_adopt_attacker_password_account(
    client, monkeypatch
):
    # Attacker pre-registers the victim's address (no email verification).
    assert register(
        client, name="Mallory", email="victim@gmail.com",
        password="attacker-pass-1",
    ).status_code == 201

    # The victim later signs in with Google using that address.
    _stub_google(monkeypatch, "victim@gmail.com")
    resp = client.post("/api/auth/google", json={"idToken": "x"})

    if resp.status_code == 200:
        # If the identities were merged, the attacker's password must no
        # longer open the account the victim now uses.
        assert login(
            client, "victim@gmail.com", "attacker-pass-1"
        ).status_code == 401
    else:
        assert resp.status_code == 409, resp.get_json()


def test_trp06_unverified_provider_email_is_rejected(client, monkeypatch):
    _stub_google(monkeypatch, "unverified@corp.example", verified=False)

    resp = client.post("/api/auth/google", json={"idToken": "x"})

    assert resp.status_code in (400, 401, 403), resp.get_json()
    assert User.query.filter_by(email="unverified@corp.example").first() is None


# ----------------------------------------------------------------------
# TRP-07  Account deletion failed once the user had a refresh token
#         (FK user_refresh_tokens.user_id has no ON DELETE CASCADE)
# ----------------------------------------------------------------------

def test_trp07_account_deletion_removes_refresh_tokens(app, client):
    engine = db.engine
    if engine.dialect.name == "sqlite":
        with engine.connect() as conn:
            conn.execute(text("PRAGMA foreign_keys=ON"))
            conn.commit()

    token = create_logged_in_user(client, name="Leaver")
    user_id = User.query.filter_by(email="leaver@example.com").first().id
    assert UserRefreshToken.query.filter_by(user_id=user_id).count() >= 1

    resp = client.delete(
        "/api/auth/account",
        json={"currentPassword": "supersecret1"},
        headers=auth_headers(token),
    )

    assert resp.status_code == 200, resp.get_json()
    db.session.expire_all()
    assert db.session.get(User, user_id) is None
    assert UserRefreshToken.query.filter_by(user_id=user_id).count() == 0

    if engine.dialect.name == "sqlite":
        with engine.connect() as conn:
            conn.execute(text("PRAGMA foreign_keys=OFF"))
            conn.commit()


# ----------------------------------------------------------------------
# TRP-08  Public page-view beacon trusted a client-supplied userId
# ----------------------------------------------------------------------

def test_trp08_page_view_ignores_client_supplied_user_id(client):
    create_logged_in_user(client, name="Bystander")
    victim_id = User.query.filter_by(email="bystander@example.com").first().id

    resp = client.post(
        "/api/admin/page-view",
        json={"path": "/forged", "userId": victim_id},
    )

    assert resp.status_code in (200, 201), resp.get_json()
    row = ActivityLog.query.filter_by(event_type="page_view", path="/forged").first()
    assert row is not None
    assert row.user_id is None


def test_trp08_page_view_attributes_authenticated_user(client):
    token = create_logged_in_user(client, name="Viewer")
    viewer_id = User.query.filter_by(email="viewer@example.com").first().id

    client.post(
        "/api/admin/page-view",
        json={"path": "/mine"},
        headers=auth_headers(token),
    )

    row = ActivityLog.query.filter_by(event_type="page_view", path="/mine").first()
    assert row is not None and row.user_id == viewer_id


# ----------------------------------------------------------------------
# TRP-09  Password change accepted 6-character passwords (policy is 8)
# ----------------------------------------------------------------------

def test_trp09_password_change_enforces_minimum_length(client):
    token = create_logged_in_user(client, name="Shorty")

    resp = client.patch(
        "/api/auth/me",
        json={"password": "abc123", "currentPassword": "supersecret1"},
        headers=auth_headers(token),
    )

    assert resp.status_code == 400, resp.get_json()


# ----------------------------------------------------------------------
# TRP-10  Rate-limit key / audit IP used a spoofable X-Forwarded-For value
#         (activity log) and the proxy address (limiter) instead of the
#         real client address resolved by a trusted proxy count.
# ----------------------------------------------------------------------

def test_trp10_spoofed_forwarded_for_does_not_reset_login_budget(client, production_limits):
    statuses = []
    for i in range(15):
        resp = client.post(
            "/api/auth/login",
            json={"email": "x@example.com", "password": "wrong-pass"},
            headers={"X-Forwarded-For": "203.0.113.{}".format(i)},
        )
        statuses.append(resp.status_code)

    # With no trusted proxy configured (tests), XFF must be ignored, so the
    # single real client exhausts its budget.
    assert 429 in statuses, statuses


def test_trp10_activity_log_does_not_store_spoofed_ip(client):
    client.post(
        "/api/admin/page-view",
        json={"path": "/ip-check"},
        headers={"X-Forwarded-For": "6.6.6.6"},
    )
    row = ActivityLog.query.filter_by(event_type="page_view", path="/ip-check").first()
    assert row is not None
    assert row.ip_address != "6.6.6.6"


# ----------------------------------------------------------------------
# TRP-11  Login revealed social-only accounts (enumeration)
# ----------------------------------------------------------------------

def test_trp11_login_does_not_reveal_social_only_accounts(client):
    db.session.add(User(
        name="Social", email="social-only@example.com", password_hash=None,
        auth_provider="google", provider_id="g-1",
    ))
    db.session.commit()

    social = login(client, "social-only@example.com", "whatever-pass")
    missing = login(client, "missing@example.com", "whatever-pass")

    assert social.status_code == missing.status_code == 401
    assert social.get_json()["message"] == missing.get_json()["message"]


# ----------------------------------------------------------------------
# TRP-12  Sensitive API responses were cacheable
# ----------------------------------------------------------------------

def test_trp12_authenticated_responses_are_not_cacheable(client):
    token = create_logged_in_user(client, name="Cachey")

    me = client.get("/api/auth/me", headers=auth_headers(token))
    trips = client.get("/api/trips", headers=auth_headers(token))
    refreshed = client.post(
        "/api/auth/login",
        json={"email": "cachey@example.com", "password": "supersecret1"},
    )

    for resp in (me, trips, refreshed):
        assert "no-store" in resp.headers.get("Cache-Control", ""), resp.headers


# ----------------------------------------------------------------------
# TRP-13  Provider verification detail leaked to API clients
# ----------------------------------------------------------------------

def test_trp13_social_verification_errors_are_generic(client, monkeypatch):
    from services.social_auth_service import SocialAuthError

    def _fail(provider, id_token_value, nonce=None):
        raise SocialAuthError(
            "Invalid Google ID token. Token used too early, 1700000000 < 1700000100"
        )

    monkeypatch.setattr(auth_module, "verify_identity_token", _fail)

    resp = client.post("/api/auth/google", json={"idToken": "x"})

    assert resp.status_code == 401
    assert "1700000000" not in resp.get_data(as_text=True)


# ----------------------------------------------------------------------
# Guards that keep the rate-limit table honest (TRP-01..04 root cause)
# ----------------------------------------------------------------------

def test_every_configured_bucket_names_a_real_endpoint(app, monkeypatch):
    import config.settings as settings_mod

    monkeypatch.setattr(settings_mod.Config, "RATE_LIMIT_ENABLED", True)
    endpoints = {rule.endpoint for rule in app.url_map.iter_rules()}
    configured = set(settings_mod.Config.rate_limit_buckets())

    stale = {
        name for name in configured
        if not name.startswith("DEFAULT_")
        and name != "AI_GLOBAL"
        and name not in endpoints
    }
    assert not stale, "Buckets for non-existent endpoints: {}".format(stale)


def test_every_endpoint_gets_a_rate_limit_budget(app, monkeypatch):
    """Endpoints without their own bucket fall back to DEFAULT_READ/WRITE."""
    import config.settings as settings_mod
    from services.rate_limiter import UNLIMITED_ENDPOINTS

    monkeypatch.setattr(settings_mod.Config, "RATE_LIMIT_ENABLED", True)
    buckets = settings_mod.Config.rate_limit_buckets()
    assert buckets["DEFAULT_READ"]["limit"] and buckets["DEFAULT_WRITE"]["limit"]

    for rule in app.url_map.iter_rules():
        if rule.endpoint in UNLIMITED_ENDPOINTS or rule.endpoint == "static":
            continue
        cfg = buckets.get(rule.endpoint)
        if cfg is not None:
            assert cfg["limit"], rule.endpoint


def test_unbucketed_write_endpoint_falls_back_to_default_write(
    client, production_limits
):
    from services.rate_limiter import limiter

    # Drop the dedicated bucket to simulate a newly added endpoint.
    limiter._buckets.pop("expenses.create_expense", None)
    token = create_logged_in_user(client, name="Spender")
    trip_id = create_trip_and_get_id(client, token)

    resp = client.post(
        "/api/trips/{}/expenses".format(trip_id),
        json={"amount": 1, "category": "food", "date": "2026-01-01"},
        headers=auth_headers(token),
    )
    assert resp.headers.get("X-RateLimit-Limit") == "30", resp.headers




@pytest.mark.parametrize("password", [
    "short7!",            # too short
    "password123",        # common
    " " * 12,             # whitespace only
    "x" * 129,            # too long
])
def test_registration_rejects_weak_passwords(client, password):
    resp = register(client, name="Weak", email="weak@example.com", password=password)
    assert resp.status_code == 400, resp.get_json()


# ----------------------------------------------------------------------
# Proxy trust boundary (TRP-10)
# ----------------------------------------------------------------------

def test_trusted_proxy_hop_uses_proxy_appended_address(app, monkeypatch):
    import app as app_module
    import config.settings as settings_mod

    monkeypatch.setattr(settings_mod.Config, "TRUSTED_PROXY_HOPS", 1)
    proxied = app_module.create_app()

    with proxied.app_context():
        db.create_all()
        try:
            # The client forges the first entry; the trusted proxy appends
            # the real peer address last.
            proxied.test_client().post(
                "/api/admin/page-view",
                json={"path": "/proxied"},
                headers={"X-Forwarded-For": "6.6.6.6, 198.51.100.7"},
            )
            row = ActivityLog.query.filter_by(path="/proxied").first()
            assert row is not None
            assert row.ip_address == "198.51.100.7"
        finally:
            db.session.remove()
            db.drop_all()
