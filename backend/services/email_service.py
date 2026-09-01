"""Email delivery for Tripora (verification codes).

Uses Resend for transactional email delivery.

Configuration:
    RESEND_API_KEY      Resend API key (server-side only)
    RESEND_FROM_EMAIL   Sender address, e.g. onboarding@resend.dev
    RESEND_FROM_NAME    Optional sender display name (default: Tripora)

The Resend API key must NEVER be exposed to the Flutter client or committed
to source control.
"""

import logging
import os

import resend

logger = logging.getLogger(__name__)


def _env(name, default=""):
    return os.getenv(name, default)


def _email_configured():
    return bool(_env("RESEND_API_KEY") and _env("RESEND_FROM_EMAIL"))


def _build_html(token):
    return (
        "<div style='font-family:Arial,Helvetica,sans-serif;"
        "max-width:480px;margin:0 auto;padding:24px'>"
        "<h2 style='color:#111827'>Verify your Tripora account</h2>"
        "<p>Welcome to Tripora! Use the code below to verify your email "
        "address:</p>"
        "<p style='font-size:24px;font-weight:bold;letter-spacing:4px;"
        "background:#F3F4F6;padding:16px;text-align:center;"
        "border-radius:8px'>"
        f"{token}"
        "</p>"
        "<p style='color:#6B7280'>"
        "This code expires soon. If you did not create a Tripora account, "
        "you can safely ignore this email."
        "</p>"
        "<p style='color:#9CA3AF'>– The Tripora team</p>"
        "</div>"
    )


def send_verification_email(to_email, token):
    """Send an email verification code using Resend.

    Args:
        to_email (str): Recipient email address.
        token (str): Verification token/code.

    Returns:
        bool: True when the email was sent successfully,
              False when delivery failed.
    """

    if not _email_configured():
        logger.info(
            "[EMAIL-PLACEHOLDER] Verification email requested for %s "
            "(Resend not configured)",
            to_email,
        )

        # Never log the verification token.
        return True

    resend.api_key = _env("RESEND_API_KEY")

    from_name = _env("RESEND_FROM_NAME", "Tripora")
    from_email = _env("RESEND_FROM_EMAIL")

    sender = f"{from_name} <{from_email}>"

    try:
        resend.Emails.send({
            "from": sender,
            "to": [to_email],
            "subject": "Verify your Tripora account",
            "html": _build_html(token),
        })

        logger.info("Verification email sent to %s", to_email)
        return True

    except Exception:
        logger.exception(
            "Failed to send verification email to %s",
            to_email,
        )
        return False
