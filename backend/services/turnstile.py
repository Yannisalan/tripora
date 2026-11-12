"""Cloudflare Turnstile server-side verification.

Turnstile is a CAPTCHA alternative: the browser (or the Android WebView
challenge page) solves a widget and receives a short-lived, single-use token;
the backend redeems that token with Cloudflare's Siteverify API using the
**secret** key. The secret never leaves the server.

Configuration (read at call time, so tests and deploys see current values):

``TURNSTILE_ENABLED``
    ``true``/``false``. When unset, protection is ON unless ``TRIPORA_ENV`` is
    ``development``/``dev``/``test``/``testing``. A deployed service therefore
    cannot silently run without it; turning it off requires an explicit
    ``TURNSTILE_ENABLED=false``, which is logged as a warning at start-up.
``TURNSTILE_SECRET_KEY``
    Server-only secret. Enabled without a secret = every protected request is
    refused (fail closed) and an error is logged at start-up.
``TURNSTILE_SITE_KEY``
    Public site key handed to the client (``/api/turnstile/config``).
``TURNSTILE_ALLOWED_HOSTNAMES``
    Comma-separated hostnames on which the widget may be solved (the web app's
    host and the API host that serves the Android challenge page). When set,
    a token solved anywhere else is rejected.
``TURNSTILE_TIMEOUT_SECONDS``
    Siteverify timeout (default 5, clamped to 1-10).

Never logged: tokens, the secret, the remote IP or the raw Siteverify body.
Only the outcome, the action and Cloudflare's fixed error-code names are.
"""

import logging
import os
from dataclasses import dataclass, field

import httpx

logger = logging.getLogger(__name__)

SITEVERIFY_URL = "https://challenges.cloudflare.com/turnstile/v0/siteverify"

# Cloudflare documents a 2048-character maximum token length.
MAX_TOKEN_LENGTH = 2048

# Turnstile action names: up to 32 characters of [A-Za-z0-9_-].
ACTION_REGISTER = "register"
ACTION_FORGOT_PASSWORD = "forgot_password"
KNOWN_ACTIONS = frozenset({ACTION_REGISTER, ACTION_FORGOT_PASSWORD})

_DEV_ENVIRONMENTS = {"development", "dev", "test", "testing"}
_TRUE = {"1", "true", "yes", "on"}
_FALSE = {"0", "false", "no", "off"}

# Outcome reasons.
OK = "ok"
DISABLED = "disabled"
MISSING = "missing"
INVALID = "invalid"
EXPIRED_OR_REUSED = "expired_or_reused"
ACTION_MISMATCH = "action_mismatch"
HOSTNAME_MISMATCH = "hostname_mismatch"
UNAVAILABLE = "unavailable"


@dataclass(frozen=True)
class TurnstileResult:
    """Outcome of a verification. ``ok`` is the only thing callers branch on,
    plus ``unavailable`` to choose between 400 (client) and 503 (server)."""

    ok: bool
    reason: str
    error_codes: tuple = field(default_factory=tuple)

    @property
    def unavailable(self):
        return self.reason == UNAVAILABLE


# ----------------------------------------------------------------------
# Configuration
# ----------------------------------------------------------------------

def is_enabled():
    raw = (os.getenv("TURNSTILE_ENABLED", "") or "").strip().lower()
    if raw in _TRUE:
        return True
    if raw in _FALSE:
        return False
    environment = (os.getenv("TRIPORA_ENV", "production") or "").strip().lower()
    return environment not in _DEV_ENVIRONMENTS


def site_key():
    return (os.getenv("TURNSTILE_SITE_KEY", "") or "").strip()


def _secret_key():
    return (os.getenv("TURNSTILE_SECRET_KEY", "") or "").strip()


def allowed_hostnames():
    raw = os.getenv("TURNSTILE_ALLOWED_HOSTNAMES", "") or ""
    return frozenset(h.strip().lower() for h in raw.split(",") if h.strip())


def _timeout_seconds():
    try:
        value = float(os.getenv("TURNSTILE_TIMEOUT_SECONDS", "5") or "5")
    except ValueError:
        value = 5.0
    return max(1.0, min(10.0, value))


def log_startup_status():
    """One line at boot so a misconfiguration is visible in the deploy log."""
    if not is_enabled():
        if os.getenv("RENDER", "").lower() == "true":
            logger.warning(
                "Turnstile bot protection is DISABLED (TURNSTILE_ENABLED=false)."
            )
        return
    missing = [
        name for name, value in (
            ("TURNSTILE_SECRET_KEY", _secret_key()),
            ("TURNSTILE_SITE_KEY", site_key()),
        ) if not value
    ]
    if missing:
        logger.error(
            "Turnstile is enabled but %s is not set: registration and "
            "password-reset requests will be refused.",
            " and ".join(missing),
        )
    if not allowed_hostnames():
        logger.warning(
            "TURNSTILE_ALLOWED_HOSTNAMES is not set: token hostnames are not "
            "checked by the backend (only by the widget's Cloudflare settings)."
        )


# ----------------------------------------------------------------------
# Verification
# ----------------------------------------------------------------------

def _siteverify_post(form, timeout):
    """The only network call. Isolated so tests can replace it."""
    return httpx.post(
        SITEVERIFY_URL,
        data=form,
        timeout=httpx.Timeout(timeout, connect=min(3.0, timeout)),
        follow_redirects=False,
    )


_CODE_REASONS = {
    "missing-input-response": MISSING,
    "invalid-input-response": INVALID,
    "timeout-or-duplicate": EXPIRED_OR_REUSED,
    "bad-request": INVALID,
    # Our own misconfiguration or Cloudflare trouble: not the user's fault.
    "missing-input-secret": UNAVAILABLE,
    "invalid-input-secret": UNAVAILABLE,
    "internal-error": UNAVAILABLE,
}


def _fail(reason, action, codes=()):
    log = logger.error if reason == UNAVAILABLE else logger.info
    log(
        "Turnstile verification failed: reason=%s action=%s codes=%s",
        reason, action, ",".join(codes) or "-",
    )
    return TurnstileResult(False, reason, tuple(codes))


def verify(token, expected_action, remote_ip=None):
    """Redeem ``token`` for ``expected_action``. Never raises."""
    if not is_enabled():
        return TurnstileResult(True, DISABLED)

    secret = _secret_key()
    if not secret:
        return _fail(UNAVAILABLE, expected_action, ("missing-input-secret",))

    if not isinstance(token, str) or not token.strip():
        return _fail(MISSING, expected_action)
    token = token.strip()
    if len(token) > MAX_TOKEN_LENGTH:
        return _fail(INVALID, expected_action)

    form = {"secret": secret, "response": token}
    if remote_ip:
        form["remoteip"] = str(remote_ip)

    try:
        response = _siteverify_post(form, _timeout_seconds())
    except Exception:
        # Timeouts, DNS/TLS/connection errors. No exception detail is logged:
        # some HTTP client errors echo the request, which holds the secret.
        return _fail(UNAVAILABLE, expected_action, ("network-error",))

    if response.status_code != 200:
        return _fail(UNAVAILABLE, expected_action, ("http-%d" % response.status_code,))

    try:
        body = response.json()
    except Exception:
        return _fail(UNAVAILABLE, expected_action, ("bad-json",))
    if not isinstance(body, dict):
        return _fail(UNAVAILABLE, expected_action, ("bad-json",))

    codes = tuple(
        str(code) for code in (body.get("error-codes") or [])
        if isinstance(code, str)
    )[:5]

    if body.get("success") is not True:
        reason = INVALID
        for code in codes:
            if code in _CODE_REASONS:
                reason = _CODE_REASONS[code]
                break
        return _fail(reason, expected_action, codes)

    if body.get("action") != expected_action:
        return _fail(ACTION_MISMATCH, expected_action)

    allowed = allowed_hostnames()
    if allowed:
        hostname = str(body.get("hostname") or "").strip().lower()
        if hostname not in allowed:
            return _fail(HOSTNAME_MISMATCH, expected_action)

    return TurnstileResult(True, OK)
