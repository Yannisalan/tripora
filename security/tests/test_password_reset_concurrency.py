"""Concurrency regression tests for the password-reset flow.

The default security-test app uses an in-memory SQLite database backed by a
single shared connection, which cannot exercise genuinely concurrent requests.
These tests therefore build a file-backed SQLite app (WAL + busy timeout) so
each request thread gets its own connection, then use deterministic barriers
and events inside the hashing step to force the interleavings that protect:

- the failed-attempt counter (no lost updates),
- lockout (the final allowed attempt clears the code exactly once),
- one-time reset-code consumption (one token, not two),
- one-time reset-token consumption (one password change, not two),
- code/token rotation (an in-flight request cannot resurrect a credential).

They are regression tests for the atomic compare-and-swap UPDATEs in
``routes/auth.py``.  Sequential behaviour remains covered by
``test_password_reset.py``.
"""

import threading

import pytest
from werkzeug.security import check_password_hash

import routes.auth as auth_module
from app import create_app
from config.database import db
from config.settings import Config
from models.user import User

from .helpers import login, register


def auth_module_hash_reset_token(token):
    from routes.auth import _hash_reset_token

    return _hash_reset_token(token)


FORGOT_URL = "/api/auth/forgot-password"
VERIFY_URL = "/api/auth/forgot-password/verify"
RESET_URL = "/api/auth/reset-password"


# ----------------------------------------------------------------------
# File-backed application fixture
# ----------------------------------------------------------------------
#
# This intentionally shadows the package conftest ``app`` fixture for this
# module only.  An in-memory SQLite database with ``StaticPool`` shares one
# connection between all threads, so concurrent writes either serialize on the
# same connection or hit the same transaction; neither proves anything about
# the production (PostgreSQL) behaviour.


@pytest.fixture
def app(tmp_path):
    original_uri = Config.SQLALCHEMY_DATABASE_URI
    original_engine_options = Config.SQLALCHEMY_ENGINE_OPTIONS

    database_path = tmp_path / "tripora_password_reset_concurrency.db"

    Config.SQLALCHEMY_DATABASE_URI = "sqlite:///" + database_path.as_posix()
    Config.SQLALCHEMY_ENGINE_OPTIONS = {
        "connect_args": {
            # Wait for a writer instead of failing with "database is locked".
            "timeout": 30,
            # Connections may be handed to another request thread by the pool.
            "check_same_thread": False,
        },
    }

    application = create_app()
    application.config.update(TESTING=True)

    with application.app_context():
        db.create_all()

        # WAL lets reader threads and the single writer proceed concurrently.
        # The journal mode is a database-file property, so it is visible to
        # every pooled connection, not just this one.
        raw_connection = db.engine.raw_connection()
        try:
            cursor = raw_connection.cursor()
            cursor.execute("PRAGMA journal_mode=WAL")
            cursor.execute("PRAGMA busy_timeout=30000")
            raw_connection.commit()
        finally:
            raw_connection.close()

        try:
            yield application
        finally:
            db.session.remove()
            db.drop_all()
            db.engine.dispose()
            Config.SQLALCHEMY_DATABASE_URI = original_uri
            Config.SQLALCHEMY_ENGINE_OPTIONS = original_engine_options


# ----------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------


def _capture_email(monkeypatch):
    """Stub outbound email and record every (recipient, code) in order."""

    captured = []

    def _fake_send(email, code):
        captured.append({"email": email, "code": code})
        return True

    monkeypatch.setattr(auth_module, "send_password_reset_code", _fake_send)

    return captured


def _register_and_request_code(client, email, password="supersecret1"):
    response = register(
        client,
        name="ConcurrencyUser",
        email=email,
        password=password,
    )
    assert response.status_code == 201, response.get_json()

    response = client.post(FORGOT_URL, json={"email": email})
    assert response.status_code == 200, response.get_json()


def _fresh_user(email):
    """Read the user through a new session after the worker threads finish."""

    db.session.remove()
    return User.query.filter_by(email=email).first()


def _wrong_code(real_code):
    """Return a code that is guaranteed not to equal the real one."""

    return "000000" if real_code != "000000" else "111111"


def _run_parallel(app, functions):
    """Run one callable per thread, each with its own Flask test client."""

    results = [None] * len(functions)
    errors = [None] * len(functions)

    def _worker(index, function):
        try:
            with app.test_client() as test_client:
                results[index] = function(test_client, index)
        except BaseException as error:  # re-raised in the main thread below
            errors[index] = error

    threads = [
        threading.Thread(
            target=_worker,
            args=(index, function),
            daemon=True,
        )
        for index, function in enumerate(functions)
    ]

    for thread in threads:
        thread.start()

    for thread in threads:
        thread.join(timeout=60)

    for index, thread in enumerate(threads):
        assert not thread.is_alive(), (
            "request thread {0} did not finish".format(index)
        )

    for error in errors:
        if error is not None:
            raise error

    return results


def _barrier_hash_check(barrier, original_check):
    """Pause every request at the hash check, then run them together."""

    def _paused_check(hash_value, submitted):
        try:
            barrier.wait(timeout=20)
        except threading.BrokenBarrierError:
            # A worker failed before reaching the barrier; let the others
            # proceed so the assertion that follows reports the real failure.
            pass
        return original_check(hash_value, submitted)

    return _paused_check


# ----------------------------------------------------------------------
# Attempt counter and lockout
# ----------------------------------------------------------------------


def test_concurrent_wrong_codes_each_consume_one_attempt(
    app, client, monkeypatch
):
    captured = _capture_email(monkeypatch)
    email = "race-attempts@example.com"
    _register_and_request_code(client, email)
    code = captured[-1]["code"]

    # Give every request room to update so the assertion isolates lost
    # updates rather than the lockout transition.
    monkeypatch.setattr(auth_module, "RESET_MAX_ATTEMPTS", 50)

    attempts = 8
    barrier = threading.Barrier(attempts, timeout=20)
    original_check = auth_module.check_password_hash
    monkeypatch.setattr(
        auth_module,
        "check_password_hash",
        _barrier_hash_check(barrier, original_check),
    )

    def _attempt(test_client, _index):
        return test_client.post(
            VERIFY_URL,
            json={"email": email, "code": _wrong_code(code)},
        )

    responses = _run_parallel(app, [_attempt] * attempts)

    assert [response.status_code for response in responses] == [400] * attempts

    user = _fresh_user(email)
    # Every concurrent failure must be recorded: with a read/modify/write
    # counter, several increments would be lost and this would be < attempts.
    assert user.reset_attempts == attempts
    assert user.reset_code_hash is not None


def test_concurrent_lockout_clears_code_and_refuses_correct_code(
    app, client, monkeypatch
):
    captured = _capture_email(monkeypatch)
    email = "race-lockout@example.com"
    _register_and_request_code(client, email)
    code = captured[-1]["code"]

    attempts = auth_module.RESET_MAX_ATTEMPTS
    barrier = threading.Barrier(attempts, timeout=20)
    original_check = auth_module.check_password_hash
    monkeypatch.setattr(
        auth_module,
        "check_password_hash",
        _barrier_hash_check(barrier, original_check),
    )

    def _attempt(test_client, _index):
        return test_client.post(
            VERIFY_URL,
            json={"email": email, "code": _wrong_code(code)},
        )

    responses = _run_parallel(app, [_attempt] * attempts)

    assert [response.status_code for response in responses] == [400] * attempts

    user = _fresh_user(email)
    # The final allowed failure clears the credential, so the account cannot
    # continue guessing.  The lockout must have been applied exactly once even
    # though every request raced through it.
    assert user.reset_code_hash is None
    assert user.reset_code_expires_at is None
    assert user.reset_attempts == 0

    monkeypatch.setattr(auth_module, "check_password_hash", original_check)

    response = client.post(VERIFY_URL, json={"email": email, "code": code})
    assert response.status_code == 400
    assert (
        response.get_json()["message"]
        == auth_module.INVALID_RESET_CODE_MESSAGE
    )


# ----------------------------------------------------------------------
# One-time code and token consumption
# ----------------------------------------------------------------------


def test_concurrent_correct_verifications_issue_single_token(
    app, client, monkeypatch
):
    captured = _capture_email(monkeypatch)
    email = "race-verify@example.com"
    _register_and_request_code(client, email)
    code = captured[-1]["code"]

    barrier = threading.Barrier(2, timeout=20)
    original_check = auth_module.check_password_hash
    monkeypatch.setattr(
        auth_module,
        "check_password_hash",
        _barrier_hash_check(barrier, original_check),
    )

    def _verify(test_client, _index):
        return test_client.post(
            VERIFY_URL,
            json={"email": email, "code": code},
        )

    responses = _run_parallel(app, [_verify, _verify])

    statuses = sorted(response.status_code for response in responses)
    assert statuses == [200, 400]

    winner = next(
        response for response in responses if response.status_code == 200
    )
    loser = next(
        response for response in responses if response.status_code == 400
    )
    assert (
        loser.get_json()["message"]
        == auth_module.INVALID_RESET_CODE_MESSAGE
    )

    reset_token = winner.get_json()["resetToken"]

    user = _fresh_user(email)
    # Exactly one token was issued and the code was consumed.
    assert user.reset_code_hash is None
    assert user.reset_attempts == 0
    assert user.reset_token_hash == auth_module_hash_reset_token(reset_token)

    monkeypatch.setattr(auth_module, "check_password_hash", original_check)

    # The single token minted by the race is still usable end-to-end.
    response = client.post(
        RESET_URL,
        json={"resetToken": reset_token, "password": "newpassword1"},
    )
    assert response.status_code == 200, response.get_json()
    assert login(client, email, "newpassword1").status_code == 200


def test_concurrent_reset_with_same_token_changes_password_once(
    app, client, monkeypatch
):
    captured = _capture_email(monkeypatch)
    email = "race-reset@example.com"
    old_password = "supersecret1"
    _register_and_request_code(client, email, password=old_password)
    code = captured[-1]["code"]

    verify = client.post(VERIFY_URL, json={"email": email, "code": code})
    assert verify.status_code == 200, verify.get_json()
    reset_token = verify.get_json()["resetToken"]

    new_passwords = ["newpassword-a", "newpassword-b"]
    barrier = threading.Barrier(2, timeout=20)
    original_generate = auth_module.generate_password_hash

    def _paused_generate(password):
        if password in new_passwords:
            try:
                barrier.wait(timeout=20)
            except threading.BrokenBarrierError:
                pass
        return original_generate(password)

    # Both requests reach the password-hashing step only after they have
    # observed the same reset token and old password hash, then race the CAS.
    monkeypatch.setattr(
        auth_module,
        "generate_password_hash",
        _paused_generate,
    )

    def _reset(test_client, index):
        return test_client.post(
            RESET_URL,
            json={
                "resetToken": reset_token,
                "password": new_passwords[index],
            },
        )

    responses = _run_parallel(app, [_reset, _reset])

    statuses = sorted(response.status_code for response in responses)
    assert statuses == [200, 400]

    winner_index = next(
        index
        for index, response in enumerate(responses)
        if response.status_code == 200
    )
    loser_index = 1 - winner_index

    loser = responses[loser_index]
    assert (
        loser.get_json()["message"]
        == auth_module.INVALID_RESET_TOKEN_MESSAGE
    )

    monkeypatch.setattr(
        auth_module,
        "generate_password_hash",
        original_generate,
    )

    # Only the winning request's password was installed.
    assert login(client, email, new_passwords[winner_index]).status_code == 200
    assert login(client, email, new_passwords[loser_index]).status_code == 401
    assert login(client, email, old_password).status_code == 401

    user = _fresh_user(email)
    assert user.reset_token_hash is None
    assert user.reset_token_expires_at is None
    assert user.reset_code_hash is None
    assert user.reset_attempts == 0


# ----------------------------------------------------------------------
# Credential rotation vs in-flight requests
# ----------------------------------------------------------------------


def test_rotation_invalidates_in_flight_code_verification(
    app, client, monkeypatch
):
    captured = _capture_email(monkeypatch)
    email = "race-rotate-code@example.com"
    _register_and_request_code(client, email)
    old_code = captured[-1]["code"]

    original_check = auth_module.check_password_hash
    ready = threading.Event()
    release = threading.Event()

    def _paused_check(hash_value, submitted):
        if submitted == old_code:
            ready.set()
            release.wait(timeout=20)
        return original_check(hash_value, submitted)

    monkeypatch.setattr(auth_module, "check_password_hash", _paused_check)

    result = {}

    def _verify_old_code():
        with app.test_client() as test_client:
            result["response"] = test_client.post(
                VERIFY_URL,
                json={"email": email, "code": old_code},
            )

    thread = threading.Thread(target=_verify_old_code, daemon=True)
    thread.start()

    assert ready.wait(timeout=20), (
        "verification never reached the hash check"
    )

    # Rotate the credential while the old verification is paused mid-flight
    # (after it read the row and before it can install a reset token).
    rotate = client.post(FORGOT_URL, json={"email": email})
    assert rotate.status_code == 200, rotate.get_json()
    new_code = captured[-1]["code"]
    assert new_code != old_code

    release.set()
    thread.join(timeout=30)
    assert not thread.is_alive()

    response = result["response"]
    assert response.status_code == 400
    assert (
        response.get_json()["message"]
        == auth_module.INVALID_RESET_CODE_MESSAGE
    )

    monkeypatch.setattr(auth_module, "check_password_hash", original_check)

    # The code from the rotation that won is the only usable one.
    verify = client.post(VERIFY_URL, json={"email": email, "code": new_code})
    assert verify.status_code == 200, verify.get_json()
    assert verify.get_json()["resetToken"]


def test_rotation_invalidates_in_flight_password_reset(
    app, client, monkeypatch
):
    captured = _capture_email(monkeypatch)
    email = "race-rotate-token@example.com"
    old_password = "supersecret1"
    new_password = "newpassword1"
    _register_and_request_code(client, email, password=old_password)
    code = captured[-1]["code"]

    verify = client.post(VERIFY_URL, json={"email": email, "code": code})
    assert verify.status_code == 200, verify.get_json()
    reset_token = verify.get_json()["resetToken"]

    original_generate = auth_module.generate_password_hash
    ready = threading.Event()
    release = threading.Event()

    def _paused_generate(password):
        if password == new_password:
            ready.set()
            release.wait(timeout=20)
        return original_generate(password)

    # The reset request has already validated the token and read the old
    # password hash; it is paused just before its single CAS update.
    monkeypatch.setattr(
        auth_module,
        "generate_password_hash",
        _paused_generate,
    )

    result = {}

    def _reset():
        with app.test_client() as test_client:
            result["response"] = test_client.post(
                RESET_URL,
                json={"resetToken": reset_token, "password": new_password},
            )

    thread = threading.Thread(target=_reset, daemon=True)
    thread.start()

    assert ready.wait(timeout=20), (
        "reset never reached the password hashing step"
    )

    # A new reset request invalidates the token the paused request is holding.
    rotate = client.post(FORGOT_URL, json={"email": email})
    assert rotate.status_code == 200, rotate.get_json()

    release.set()
    thread.join(timeout=30)
    assert not thread.is_alive()

    response = result["response"]
    assert response.status_code == 400
    assert (
        response.get_json()["message"]
        == auth_module.INVALID_RESET_TOKEN_MESSAGE
    )

    monkeypatch.setattr(
        auth_module,
        "generate_password_hash",
        original_generate,
    )

    # The invalidated request must not have changed the password.
    assert login(client, email, old_password).status_code == 200
    assert login(client, email, new_password).status_code == 401

    user = _fresh_user(email)
    assert user.reset_token_hash is None
    assert user.reset_token_expires_at is None
    # The rotation that invalidated the token installed a fresh code.
    assert user.reset_code_hash is not None
