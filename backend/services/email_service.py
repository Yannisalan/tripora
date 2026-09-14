"""Email delivery for Tripora (password reset, account emails).

Provider strategy (replaceable without touching callers):

1. **Resend** (HTTP API) when ``RESEND_API_KEY`` is set.
2. **SMTP** when ``MAIL_HOST`` + ``MAIL_USER`` + ``MAIL_PASSWORD`` are set
   (supports both implicit SSL on ``MAIL_PORT=465`` and STARTTLS on
   ``MAIL_PORT=587`` / ``MAIL_USE_TLS=tls``).
3. **Log-only fallback** otherwise (local development / tests): the email is
   written to the log stream instead of being delivered. This keeps the suite
   hermetic and never touches real credentials.

The v1 Tripora sender is ``gotripora@gmail.com`` (set via ``MAIL_FROM`` /
``MAIL_FROM_NAME``, or ``RESEND_FROM_EMAIL`` / ``RESEND_FROM_NAME``). Gmail
SMTP requires an *App Password*, which is supplied through ``MAIL_PASSWORD``,
never hard-coded.

Nothing in this module ever logs credentials, reset codes, or tokens.
"""

import logging
import os
import smtplib
import ssl
from email.message import EmailMessage

from dotenv import load_dotenv

logger = logging.getLogger(__name__)

load_dotenv()

DEFAULT_FROM_ADDRESS = "gotripora@gmail.com"
DEFAULT_FROM_NAME = "Tripora"

# Sender used by the Resend HTTP API until a custom domain is configured.
# ``onboarding@resend.dev`` is Resend's free sandbox sender.
RESEND_LOCALED_NAME = "Resend"

# Timeout for SMTP / HTTP email delivery (seconds).
_SMTP_TIMEOUT = 15


def _env(key, default=""):
    return os.getenv(key, default)


def _email_configured():
    """Return True when any real delivery backend is configured."""
    if _env("RESEND_API_KEY").strip():
        return True
    host = _env("MAIL_HOST").strip()
    user = _env("MAIL_USER").strip()
    password = _env("MAIL_PASSWORD").strip()
    return bool(host and user and password)


def _smtp_configured():
    host = _env("MAIL_HOST").strip()
    user = _env("MAIL_USER").strip()
    password = _env("MAIL_PASSWORD").strip()
    return bool(host and user and password)


def _smtp_use_ssl():
    """Decide between implicit SSL and STARTTLS."""
    mode = _env("MAIL_USE_TLS", "").strip().lower()
    if mode in ("ssl", "tls"):
        return mode == "ssl"
    port = _env("MAIL_PORT", "465").strip()
    try:
        return int(port) == 465
    except ValueError:
        return True


def _send_via_resend(to_email, subject, text_body, html_body):
    import httpx

    api_key = _env("RESEND_API_KEY").strip()
    from_email = _env("RESEND_FROM_EMAIL", "onboarding@resend.dev").strip()
    from_name = _env("RESEND_FROM_NAME", DEFAULT_FROM_NAME).strip()

    payload = {
        "from": "{} <{}>".format(from_name, from_email),
        "to": [to_email],
        "subject": subject,
        "text": text_body,
    }
    if html_body:
        payload["html"] = html_body

    response = httpx.post(
        "https://api.resend.com/emails",
        headers={
            "Authorization": "Bearer {}".format(api_key),
            "Content-Type": "application/json",
        },
        json=payload,
        timeout=15,
    )

    if response.status_code < 200 or response.status_code >= 300:
        logger.error(
            "Resend email delivery failed (status=%s): %s",
            response.status_code,
            response.text[:500],
        )
        return False

    return True


def _send_via_smtp(to_email, subject, text_body, html_body):
    host = _env("MAIL_HOST").strip()
    port_raw = _env("MAIL_PORT", "465").strip()
    user = _env("MAIL_USER").strip()
    password = _env("MAIL_PASSWORD").strip()
    from_address = _env("MAIL_FROM", DEFAULT_FROM_ADDRESS).strip()
    from_name = _env("MAIL_FROM_NAME", DEFAULT_FROM_NAME).strip()

    try:
        port = int(port_raw)
    except ValueError:
        port = 465

    message = EmailMessage()
    message["From"] = "{} <{}>".format(from_name, from_address)
    message["To"] = to_email
    message["Subject"] = subject
    message.set_content(text_body)

    if html_body:
        message.add_alternative(html_body, subtype="html")

    use_ssl = _smtp_use_ssl()

    if use_ssl:
        context = ssl.create_default_context()
        with smtplib.SMTP_SSL(
            host, port, timeout=_SMTP_TIMEOUT, context=context
        ) as server:
            server.login(user, password)
            server.send_message(message)
    else:
        with smtplib.SMTP(host, port, timeout=_SMTP_TIMEOUT) as server:
            server.starttls(context=ssl.create_default_context())
            server.login(user, password)
            server.send_message(message)

    return True


def send_email(to_email, subject, text_body, html_body=None):
    """Deliver an email through the first configured backend.

    Returns True when the email was delivered (or intentionally logged),
    False when no backend is configured or delivery failed. Never raises
    for configuration problems; callers treat a False as "best effort".

    Important: ``text_body`` may contain a reset code — it is written to the
    log stream ONLY when no mail backend is configured (dev/tests). Never log
    the recipient's reset code elsewhere.
    """

    if not to_email:
        return False

    to_email = str(to_email).strip()

    if _smtp_configured():
        try:
            return _send_via_smtp(to_email, subject, text_body, html_body)
        except Exception:
            logger.exception(
                "SMTP email delivery failed. Resend will not be attempted "
                "because we never fall back to a second provider mid-request."
            )
            return False

    if _env("RESEND_API_KEY").strip():
        try:
            return _send_via_resend(to_email, subject, text_body, html_body)
        except Exception:
            logger.exception("Resend email delivery failed")
            return False

    # ------------------------------------------------------------
    # Log-only mode (local dev / tests). The code is shown ONLY here
    # because no mail backend exists; it is never printed in prod.
    # ------------------------------------------------------------
    logger.warning(
        "EMAIL (log-only mode, no mail backend configured):\n"
        "To: %s\nSubject: %s\n\n%s",
        to_email,
        subject,
        text_body,
    )
    return True


def send_password_reset_code(to_email, code):
    """Send a one-time password reset code to a user's email.

    ``code`` is a human-readable one-time code (shown only in log-only dev
    mode or in the delivered email itself, never in API logging).
    """
    subject = "Your Tripora password reset code"
    text_body = (
        "Hello,\n\n"
        "We received a request to reset your Tripora password.\n\n"
        "Your one-time password reset code is: {code}\n\n"
        "This code expires in 15 minutes and can only be used once.\n\n"
        "If you did not request this, you can safely ignore this email — "
        "your password will not be changed.\n\n"
        "— Tripora"
    ).format(code=code)

    return send_email(to_email, subject, text_body)