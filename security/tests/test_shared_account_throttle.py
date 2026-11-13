"""M1 + L1 - one per-account login budget for every password endpoint.

M1 (final review): ``POST /api/admin/auth/login`` verifies the same account
password as ``POST /api/auth/login`` but was limited only per IP, so it was a
password oracle for admin accounts that bypassed the F3 per-account throttle.
Both endpoints now draw from the SAME ``auth.login_account`` counter (same
bucket, same HMAC key, same normalized e-mail).

L1 (final review): a completed password reset now clears the account's
counter, so an attacker-imposed lockout cannot outlive a successful reset.
Failed or invalid reset attempts never clear it.

Only module-level names that already existed before the fix are imported, so
this file also runs (and fails) against the pre-fix code (negative control).
"""

import threading

import pytest

import routes.auth as auth_module
from models.admin_security import AdminAuditLog, AdminSession
from routes.auth import ACCOUNT_LOGIN_BUCKET, _account_login_key
from services import admin_auth
from services.rate_limiter import limiter

from .helpers import create_logged_in_user, get_user_by_email

LIMIT = 5
PASSWORD = "supersecret1"
WRONG = "definitely-not-the-password"
NEW_PASSWORD = "brand-new-pass-123"

_ip_counter = [0]


def _ip():
    """A fresh source IP per request, so per-IP limits never fire."""
    _ip_counter[0] += 1
    n = _ip_counter[0]
    return "10.{}.{}.{}".format((n >> 16) & 255, (n >> 8) & 255, n & 255)


def _user_login(client, email, password):
    return client.post("/api/auth/login",
                       json={"email": email, "password": password},
                       environ_base={"REMOTE_ADDR": _ip()})


def _admin_login(client, email, password):
    return client.post("/api/admin/auth/login",
                       json={"email": email, "password": password},
                       environ_base={"REMOTE_ADDR": _ip()})


def _count(email):
    key = _account_login_key(str(email).strip().lower())
    return limiter.peek(ACCOUNT_LOGIN_BUCKET, key)["count"]


@pytest.fixture(autouse=True)
def limits():
    limiter.configure_bucket(ACCOUNT_LOGIN_BUCKET, LIMIT, 3600)
    for name in ("auth.login", "admin_auth.admin_login",
                 "admin_auth.admin_mfa_setup", "admin_auth.admin_mfa_activate",
                 "auth.forgot_password", "auth.verify_reset_code",
                 "auth.reset_password", "auth.register", "auth.verify_email",
                 "DEFAULT_READ", "DEFAULT_WRITE"):
        limiter.configure_bucket(name, 100000, 600)
    yield
    for name in list(limiter._buckets):
        limiter.configure_bucket(name, None, 600)


def _make_admin(app, client, name):
    email = "{}@example.com".format(name.lower())
    create_logged_in_user(client, name=name, email=email, password=PASSWORD)
    result = app.test_cli_runner().invoke(args=["admin", "grant", email])
    assert result.exit_code == 0, result.output
    return email


def _sessions(email):
    user = get_user_by_email(email)
    return AdminSession.query.filter_by(user_id=user.id).count()


# ----------------------------------------------------------------------
# M1: one shared counter
# ----------------------------------------------------------------------

class TestSharedCounter:

    def test_user_login_failures_lock_admin_login(self, app, client):
        email = _make_admin(app, client, "Boss1")
        for _ in range(LIMIT):
            assert _user_login(client, email, WRONG).status_code == 401
        assert _count(email) == LIMIT

        resp = _admin_login(client, email, PASSWORD)
        assert resp.status_code == 429
        assert "pendingToken" not in (resp.get_json() or {})
        assert _sessions(email) == 0

    def test_admin_login_failures_lock_user_login(self, app, client):
        email = _make_admin(app, client, "Boss2")
        for _ in range(LIMIT):
            assert _admin_login(client, email, WRONG).status_code == 401
        assert _count(email) == LIMIT

        resp = _user_login(client, email, PASSWORD)
        assert resp.status_code == 429
        assert "accessToken" not in (resp.get_json() or {})

    def test_distributed_mixed_attempts_share_one_budget(self, app, client):
        email = _make_admin(app, client, "Boss3")
        # Every request from a different IP, alternating endpoints.
        statuses = []
        for i in range(12):
            send = _admin_login if i % 2 else _user_login
            statuses.append(send(client, email, WRONG).status_code)
        assert statuses[:LIMIT] == [401] * LIMIT
        assert statuses[LIMIT:] == [429] * (12 - LIMIT)

    def test_admin_endpoint_alone_is_now_bounded(self, app, client):
        # The exact review reproduction: many wrong guesses from many IPs,
        # then the correct password. Before the fix: 401... then 200.
        email = _make_admin(app, client, "Boss4")
        statuses = [_admin_login(client, email, "guess-%d" % i).status_code
                    for i in range(30)]
        assert statuses.count(401) == LIMIT
        assert statuses.count(429) == 30 - LIMIT

        right = _admin_login(client, email, PASSWORD)
        assert right.status_code == 429
        assert _sessions(email) == 0
        # And the oracle cannot be moved to the user endpoint either.
        assert _user_login(client, email, PASSWORD).status_code == 429

    def test_concurrent_mixed_burst_admits_at_most_limit(self, app, client):
        email = _make_admin(app, client, "Boss5")
        limiter.configure_bucket(ACCOUNT_LOGIN_BUCKET, 1, 3600)
        n = 30
        barrier = threading.Barrier(n)
        statuses, lock = [], threading.Lock()
        ips = [_ip() for _ in range(n)]

        def attempt(i):
            path = "/api/admin/auth/login" if i % 2 else "/api/auth/login"
            barrier.wait()
            r = client.post(path, json={"email": email, "password": WRONG},
                            environ_base={"REMOTE_ADDR": ips[i]})
            with lock:
                statuses.append(r.status_code)

        threads = [threading.Thread(target=attempt, args=(i,)) for i in range(n)]
        for t in threads:
            t.start()
        for t in threads:
            t.join()

        admitted = [s for s in statuses if s != 429]
        assert len(admitted) == 1, statuses
        assert admitted[0] == 401, statuses


# ----------------------------------------------------------------------
# M1: admin flow, enumeration, audit, fail-closed
# ----------------------------------------------------------------------

class TestAdminLoginBehaviour:

    def test_success_resets_counter_and_mfa_flow_still_works(self, app, client):
        email = _make_admin(app, client, "Boss6")
        for _ in range(LIMIT - 1):
            _admin_login(client, email, WRONG)
        assert _count(email) == LIMIT - 1

        pending = _admin_login(client, email, PASSWORD)
        assert pending.status_code == 200, pending.get_json()
        body = pending.get_json()
        assert body["pendingToken"] and body["mfaEnrolled"] is False
        assert _count(email) == 0

        # Second factor unchanged: enroll + activate -> active session.
        setup = client.post("/api/admin/auth/mfa/setup",
                            json={"pendingToken": body["pendingToken"]})
        assert setup.status_code == 200, setup.get_json()
        done = client.post("/api/admin/auth/mfa/activate", json={
            "pendingToken": body["pendingToken"],
            "code": admin_auth.totp_code(setup.get_json()["secret"]),
        })
        assert done.status_code == 200, done.get_json()
        me = client.get("/api/admin/auth/me", headers={
            "Authorization": "Bearer " + done.get_json()["sessionToken"]})
        assert me.status_code == 200

    def test_pending_token_alone_grants_no_admin_access(self, app, client):
        email = _make_admin(app, client, "Boss7")
        pending = _admin_login(client, email, PASSWORD).get_json()["pendingToken"]
        resp = client.get("/api/admin/auth/me",
                          headers={"Authorization": "Bearer " + pending})
        assert resp.status_code == 401

    def test_throttle_does_not_reveal_admin_or_existence(self, app, client):
        admin_email = _make_admin(app, client, "Boss8")
        user_email = "plainuser@example.com"
        create_logged_in_user(client, name="PlainUser", email=user_email)
        unknown = "nobody-here@example.com"

        below = {}
        for email in (admin_email, user_email, unknown):
            below[email] = _admin_login(client, email, WRONG)
        bodies = {e: (r.status_code, r.get_json()) for e, r in below.items()}
        assert len(set(map(str, bodies.values()))) == 1, bodies

        for email in (admin_email, user_email, unknown):
            for _ in range(LIMIT):
                _admin_login(client, email, WRONG)
        over = {e: _admin_login(client, e, WRONG) for e in
                (admin_email, user_email, unknown)}
        assert {r.status_code for r in over.values()} == {429}
        assert len({str(r.get_json()) for r in over.values()}) == 1

    def test_non_admin_correct_password_is_a_failed_admin_attempt(self, app,
                                                                  client):
        email = "worker@example.com"
        create_logged_in_user(client, name="Worker", email=email)
        resp = _admin_login(client, email, PASSWORD)
        assert resp.status_code == 401
        assert _count(email) == 1  # counted, not reset

    def test_throttled_admin_attempts_are_audited(self, app, client):
        email = _make_admin(app, client, "Boss9")
        for _ in range(LIMIT):
            _admin_login(client, email, WRONG)
        before = AdminAuditLog.query.filter_by(action="login_throttled").count()
        assert _admin_login(client, email, PASSWORD).status_code == 429
        rows = AdminAuditLog.query.filter_by(action="login_throttled").all()
        assert len(rows) == before + 1
        assert rows[-1].status_code == 429
        assert rows[-1].admin_user_id is None  # no lookup before the gate

    def test_admin_gate_fails_closed(self, app, client, monkeypatch):
        email = _make_admin(app, client, "Boss10")

        real_check = limiter.check

        def broken(bucket, key):
            # Only the per-account gate fails; the global per-IP check works.
            if bucket == ACCOUNT_LOGIN_BUCKET:
                raise RuntimeError("limiter exploded")
            return real_check(bucket, key)

        monkeypatch.setattr(limiter, "check", broken)
        resp = _admin_login(client, email, PASSWORD)
        assert resp.status_code == 503
        assert _sessions(email) == 0

    def test_mfa_unavailable_still_short_circuits(self, app, client,
                                                  monkeypatch):
        email = _make_admin(app, client, "Boss11")
        monkeypatch.setattr(admin_auth, "mfa_available", lambda: False)
        resp = _admin_login(client, email, WRONG)
        assert resp.status_code == 503
        assert _count(email) == 0


# ----------------------------------------------------------------------
# L1: completed password reset clears the lockout
# ----------------------------------------------------------------------

def _capture_reset_codes(monkeypatch):
    sent = {}

    def fake_send(email, code):
        sent[email] = code
        return True

    monkeypatch.setattr(auth_module, "send_password_reset_code", fake_send)
    return sent


def _lock(client, email):
    for _ in range(LIMIT):
        _user_login(client, email, WRONG)
    assert _user_login(client, email, PASSWORD).status_code == 429
    assert _count(email) == LIMIT + 1


def _reset_token(client, sent, email):
    assert client.post("/api/auth/forgot-password",
                       json={"email": email}).status_code == 200
    verify = client.post("/api/auth/forgot-password/verify",
                         json={"email": email, "code": sent[email]})
    assert verify.status_code == 200, verify.get_json()
    return verify.get_json()["resetToken"]


class TestPasswordResetClearsLockout:

    def test_completed_reset_clears_counter(self, client, monkeypatch):
        sent = _capture_reset_codes(monkeypatch)
        email = "locked@example.com"
        create_logged_in_user(client, name="Locked", email=email)
        _lock(client, email)

        token = _reset_token(client, sent, email)
        done = client.post("/api/auth/reset-password",
                           json={"resetToken": token, "password": NEW_PASSWORD})
        assert done.status_code == 200, done.get_json()

        assert _count(email) == 0
        assert _user_login(client, email, NEW_PASSWORD).status_code == 200

    def test_reset_clears_admin_lockout_too(self, app, client, monkeypatch):
        sent = _capture_reset_codes(monkeypatch)
        email = _make_admin(app, client, "Boss12")
        for _ in range(LIMIT):
            _admin_login(client, email, WRONG)
        # Locked: even the correct password is refused on the admin endpoint.
        assert _admin_login(client, email, PASSWORD).status_code == 429
        token = _reset_token(client, sent, email)
        assert client.post("/api/auth/reset-password", json={
            "resetToken": token, "password": NEW_PASSWORD}).status_code == 200
        assert _admin_login(client, email, NEW_PASSWORD).status_code == 200

    def test_failed_reset_attempts_do_not_clear(self, client, monkeypatch):
        sent = _capture_reset_codes(monkeypatch)
        email = "stilllocked@example.com"
        create_logged_in_user(client, name="StillLocked", email=email)
        _lock(client, email)
        locked = _count(email)

        resets = []
        real_reset_key = limiter.reset_key
        monkeypatch.setattr(limiter, "reset_key", lambda b, k: (
            resets.append(b), real_reset_key(b, k)))

        # Requesting a code, and a wrong code, do not clear it.
        assert client.post("/api/auth/forgot-password",
                           json={"email": email}).status_code == 200
        bad_code = "000000" if sent[email] != "000000" else "111111"
        assert client.post("/api/auth/forgot-password/verify", json={
            "email": email, "code": bad_code}).status_code == 400
        # An invalid token does not clear it.
        assert client.post("/api/auth/reset-password", json={
            "resetToken": "not-a-real-token", "password": NEW_PASSWORD,
        }).status_code == 400
        # A valid token with a rejected password (policy / same as old)
        # does not clear it either.
        token = _reset_token(client, sent, email)
        assert client.post("/api/auth/reset-password", json={
            "resetToken": token, "password": "short"}).status_code == 400
        assert client.post("/api/auth/reset-password", json={
            "resetToken": token, "password": PASSWORD}).status_code == 400

        assert ACCOUNT_LOGIN_BUCKET not in resets
        assert _count(email) == locked
        assert _user_login(client, email, PASSWORD).status_code == 429

    def test_reused_token_does_not_clear_again(self, client, monkeypatch):
        sent = _capture_reset_codes(monkeypatch)
        email = "reuse@example.com"
        create_logged_in_user(client, name="Reuse", email=email)
        token = _reset_token(client, sent, email)
        assert client.post("/api/auth/reset-password", json={
            "resetToken": token, "password": NEW_PASSWORD}).status_code == 200
        _lock(client, email)
        assert client.post("/api/auth/reset-password", json={
            "resetToken": token, "password": "another-pass-456"},
        ).status_code == 400
        assert _count(email) == LIMIT + 1

    def test_reset_clears_only_that_account(self, client, monkeypatch):
        sent = _capture_reset_codes(monkeypatch)
        a, b = "acct-a@example.com", "acct-b@example.com"
        create_logged_in_user(client, name="AcctA", email=a)
        create_logged_in_user(client, name="AcctB", email=b)
        _lock(client, a)
        _lock(client, b)

        token = _reset_token(client, sent, a)
        assert client.post("/api/auth/reset-password", json={
            "resetToken": token, "password": NEW_PASSWORD}).status_code == 200
        assert _count(a) == 0
        assert _count(b) == LIMIT + 1
        assert _user_login(client, b, PASSWORD).status_code == 429
