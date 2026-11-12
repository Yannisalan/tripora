"""Bot protection for unauthenticated, abuse-prone forms.

Two independent layers, checked in this order:

1. **Honeypot.** The web form contains an input named ``website`` that is
   positioned off-screen by a static stylesheet rule (not by JavaScript),
   marked ``aria-hidden``, ``tabindex=-1`` and ``autocomplete=off``. People
   never see or reach it; naive form-filling bots fill every input. Browsers
   do not autofill a field called "website", and whitespace-only values are
   ignored, so autofill and assistive tools do not cause false positives.
   A filled honeypot gets the endpoint's normal *success* response without
   any side effect, so the bot learns nothing.

   Native apps have no DOM a bot could fill: there the field is always sent
   empty and the honeypot adds nothing. Turnstile is the real control.

2. **Turnstile.** See ``services/turnstile.py``.

``check(data, action)`` runs both and returns a ``BotCheck`` that the route
turns into a response. It never raises and never logs submitted values.
"""

import logging
from dataclasses import dataclass

from services import turnstile
from services.client_ip import client_ip

logger = logging.getLogger(__name__)

HONEYPOT_FIELD = "website"
TOKEN_FIELD = "turnstileToken"

PASS = "pass"
HONEYPOT = "honeypot"
CHALLENGE_FAILED = "challenge_failed"
CHALLENGE_UNAVAILABLE = "challenge_unavailable"

CHALLENGE_FAILED_MESSAGE = (
    "We could not verify that you are human. Please complete the "
    "verification and try again."
)
CHALLENGE_UNAVAILABLE_MESSAGE = (
    "Verification is temporarily unavailable. Please try again in a moment."
)


@dataclass(frozen=True)
class BotCheck:
    outcome: str
    reason: str = ""

    @property
    def passed(self):
        return self.outcome == PASS


def honeypot_triggered(data):
    """True when the hidden field carries anything but whitespace."""
    if not isinstance(data, dict):
        return False
    value = data.get(HONEYPOT_FIELD)
    if value is None:
        return False
    if isinstance(value, str):
        return bool(value.strip())
    # Any non-string value (number, list, object) was not typed by a person
    # into an empty text input.
    return True


def check(data, action):
    if honeypot_triggered(data):
        logger.info("Bot protection: honeypot triggered (action=%s).", action)
        return BotCheck(HONEYPOT, "honeypot")

    token = data.get(TOKEN_FIELD) if isinstance(data, dict) else None
    result = turnstile.verify(token, action, remote_ip=client_ip())
    if result.ok:
        return BotCheck(PASS, result.reason)
    if result.unavailable:
        return BotCheck(CHALLENGE_UNAVAILABLE, result.reason)
    return BotCheck(CHALLENGE_FAILED, result.reason)


def failure_response(result):
    """(body, status) for a failed challenge. Not used for the honeypot."""
    if result.outcome == CHALLENGE_UNAVAILABLE:
        return {
            "success": False,
            "message": CHALLENGE_UNAVAILABLE_MESSAGE,
            "code": "turnstile_unavailable",
        }, 503
    return {
        "success": False,
        "message": CHALLENGE_FAILED_MESSAGE,
        "code": "turnstile_failed",
    }, 400
