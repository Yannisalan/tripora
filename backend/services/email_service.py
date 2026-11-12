"""Email delivery for Tripora (password reset, account emails).

Provider strategy:

1. Resend (HTTP API) when RESEND_API_KEY is set.
2. SMTP when MAIL_HOST + MAIL_USER + MAIL_PASSWORD are set.
3. A safe development-only delivery simulation otherwise.

Production never falls back to logging email content.  When no provider is
configured, delivery fails so callers can avoid activating recovery material
that the recipient cannot receive.

For the current Tripora setup, Gmail SMTP is used:

    MAIL_HOST=smtp.gmail.com
    MAIL_PORT=465
    MAIL_USE_TLS=false
    MAIL_USER=gotripora@gmail.com
    MAIL_PASSWORD=<Google App Password>
    MAIL_FROM=gotripora@gmail.com
    MAIL_FROM_NAME=Tripora

Gmail SMTP requires a Google App Password, not the normal Gmail password.

This module never logs email bodies, recipients, passwords, reset codes, or
reset tokens.
"""

import logging
import os
import smtplib
import ssl
from email.message import EmailMessage

from config import local_safety

logger = logging.getLogger(__name__)

local_safety.load_environment()

DEFAULT_FROM_ADDRESS = "gotripora@gmail.com"
DEFAULT_FROM_NAME = "Tripora"

# Timeout for SMTP / HTTP email delivery (seconds).
_SMTP_TIMEOUT = 15


def _env(key, default=""):
    return os.getenv(key, default)


def _smtp_configured():
    """Return True when SMTP credentials are configured."""
    host = _env("MAIL_HOST").strip()
    user = _env("MAIL_USER").strip()
    password = _env("MAIL_PASSWORD").strip()

    return bool(host and user and password)


def _development_delivery_simulation_enabled():
    """Return whether a provider-less delivery simulation is explicitly safe.

    Production is the default.  Keeping the simulation behind an explicit
    development/test environment avoids silently treating an undeliverable
    password-reset email as successful in a deployed service.
    """
    environment = _env("TRIPORA_ENV", "production").strip().lower()
    return environment in {"development", "dev", "test", "testing"}


def _smtp_use_ssl():
    """Decide whether SMTP should use implicit SSL or STARTTLS."""

    mode = _env("MAIL_USE_TLS", "").strip().lower()

    # Explicit settings.
    if mode == "ssl":
        return True

    if mode == "tls":
        return False

    if mode in ("true", "1", "yes", "on"):
        return False

    if mode in ("false", "0", "no", "off"):
        # With port 465, SSL is still required.
        port = _env("MAIL_PORT", "465").strip()

        try:
            return int(port) == 465
        except ValueError:
            return True

    # Automatically use SSL for port 465.
    port = _env("MAIL_PORT", "465").strip()

    try:
        return int(port) == 465
    except ValueError:
        return True


def _send_via_smtp(to_email, subject, text_body, html_body):
    """Send an email through the configured SMTP server."""

    host = _env("MAIL_HOST").strip()
    port_raw = _env("MAIL_PORT", "465").strip()
    user = _env("MAIL_USER").strip()
    password = _env("MAIL_PASSWORD").strip()

    from_address = _env(
        "MAIL_FROM",
        DEFAULT_FROM_ADDRESS,
    ).strip()

    from_name = _env(
        "MAIL_FROM_NAME",
        DEFAULT_FROM_NAME,
    ).strip()

    try:
        port = int(port_raw)
    except ValueError:
        port = 465

    use_ssl = _smtp_use_ssl()

    logger.info("SMTP delivery attempt started.")

    message = EmailMessage()

    message["From"] = "{} <{}>".format(
        from_name,
        from_address,
    )

    message["To"] = to_email
    message["Subject"] = subject

    message.set_content(text_body)

    if html_body:
        message.add_alternative(
            html_body,
            subtype="html",
        )

    if use_ssl:
        logger.info("Connecting to SMTP server using SSL...")

        context = ssl.create_default_context()

        with smtplib.SMTP_SSL(
            host,
            port,
            timeout=_SMTP_TIMEOUT,
            context=context,
        ) as server:

            logger.info("SMTP connection established.")
            logger.info("Authenticating with SMTP server...")

            server.login(
                user,
                password,
            )

            logger.info("SMTP authentication successful.")
            logger.info("Sending email...")

            server.send_message(message)

            logger.info("SMTP email sent successfully.")

    else:
        logger.info("Connecting to SMTP server using STARTTLS...")

        with smtplib.SMTP(
            host,
            port,
            timeout=_SMTP_TIMEOUT,
        ) as server:

            server.ehlo()

            logger.info("Starting STARTTLS...")

            server.starttls(
                context=ssl.create_default_context()
            )

            server.ehlo()

            logger.info("Authenticating with SMTP server...")

            server.login(
                user,
                password,
            )

            logger.info("SMTP authentication successful.")
            logger.info("Sending email...")

            server.send_message(message)

            logger.info("SMTP email sent successfully.")

    return True


def _send_via_resend(to_email, subject, text_body, html_body):
    """Send an email through Resend."""

    import httpx

    api_key = _env("RESEND_API_KEY").strip()

    from_email = _env(
        "RESEND_FROM_EMAIL",
        "onboarding@resend.dev",
    ).strip()

    from_name = _env(
        "RESEND_FROM_NAME",
        DEFAULT_FROM_NAME,
    ).strip()

    payload = {
        "from": "{} <{}>".format(
            from_name,
            from_email,
        ),
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
            "Resend email delivery failed (status=%s).",
            response.status_code,
        )
        return False

    logger.info("Resend email sent successfully.")

    return True


def send_email(
    to_email,
    subject,
    text_body,
    html_body=None,
):
    """Deliver an email through the configured backend.

    Returns True when delivery succeeds.
    Returns False when delivery fails.

    SMTP is preferred when SMTP credentials are configured.
    Resend is used only when SMTP is not configured.
    """

    if not to_email:
        return False

    to_email = str(to_email).strip()

    # Local-only safety mode never sends real e-mail, whatever is configured.
    if local_safety.local_only():
        logger.warning(
            "Email delivery simulated (TRIPORA_LOCAL_ONLY); nothing was sent."
        )
        return True

    # ------------------------------------------------------------
    # SMTP
    # ------------------------------------------------------------

    if _smtp_configured():

        logger.info(
            "SMTP is configured. Attempting to send email."
        )

        try:
            result = _send_via_smtp(
                to_email,
                subject,
                text_body,
                html_body,
            )

            logger.info("SMTP delivery completed: success=%s", bool(result))

            return result

        except Exception:
            logger.error("SMTP email delivery failed.")

            return False

    # ------------------------------------------------------------
    # Resend
    # ------------------------------------------------------------

    if _env("RESEND_API_KEY").strip():

        logger.info(
            "SMTP is not configured. Using Resend."
        )

        try:
            result = _send_via_resend(
                to_email,
                subject,
                text_body,
                html_body,
            )

            logger.info("Resend delivery completed: success=%s", bool(result))

            return result

        except Exception:
            logger.error("Resend email delivery failed.")

            return False

    # ------------------------------------------------------------
    # Provider-less mode
    # ------------------------------------------------------------

    if _development_delivery_simulation_enabled():
        logger.warning(
            "Email delivery simulated in development; no provider configured."
        )
        return True

    logger.error("Email delivery unavailable; no provider configured.")
    return False


def send_password_reset_code(to_email, code):
    """Send a one-time password reset code."""

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

    return send_email(
        to_email,
        subject,
        text_body,
    )


def send_verification_code(to_email, code):
    """Send the one-time email-verification code."""

    subject = "Your Tripora verification code"

    text_body = (
        "Welcome to Tripora!\n\n"
        "Your email verification code is: {code}\n\n"
        "Enter it in the app to finish creating your account. "
        "It expires in 30 minutes and can only be used once.\n\n"
        "If you did not create a Tripora account, ignore this email; "
        "the account will stay unverified.\n\n"
        "— Tripora"
    ).format(code=code)

    return send_email(to_email, subject, text_body)


def send_existing_account_notice(to_email):
    """Tell an existing account owner that someone tried to register.

    Sent instead of a verification code so the register endpoint behaves the
    same for new and existing addresses (no account enumeration).
    """

    subject = "Someone tried to create a Tripora account with your email"

    text_body = (
        "Hello,\n\n"
        "Someone tried to create a new Tripora account with this email "
        "address, but you already have one.\n\n"
        "If this was you, sign in instead, or use \"Forgot password\" to "
        "reset your password.\n\n"
        "If it was not you, no action is needed; your account was not "
        "changed.\n\n"
        "— Tripora"
    )

    return send_email(to_email, subject, text_body)
