"""Email delivery for Tripora verification emails.

Uses Resend for transactional email delivery.

Required environment variables:
    RESEND_API_KEY       Resend API key (server-side only)
    RESEND_FROM_EMAIL    Verified sender email address
    RESEND_FROM_NAME     Optional sender display name (default: Tripora)

The Resend API key must NEVER be exposed to the Flutter client
or committed to source control.
"""

import logging
import os

import resend

logger = logging.getLogger(__name__)


def _env(name: str, default: str = "") -> str:
    """Read an environment variable safely."""
    return os.getenv(name, default).strip()


def _email_configured() -> bool:
    """Return True only when all required Resend configuration exists."""
    return bool(
        _env("RESEND_API_KEY")
        and _env("RESEND_FROM_EMAIL")
    )


def _build_html(token: str) -> str:
    """Build the HTML verification email."""
    return (
        "<div style='font-family:Arial,Helvetica,sans-serif;"
        "max-width:480px;margin:0 auto;padding:24px'>"

        "<h2 style='color:#111827'>"
        "Verify your Tripora account"
        "</h2>"

        "<p>"
        "Welcome to Tripora! Use the verification code below "
        "to verify your email address:"
        "</p>"

        "<p style='font-size:24px;font-weight:bold;"
        "letter-spacing:4px;background:#F3F4F6;padding:16px;"
        "text-align:center;border-radius:8px'>"
        f"{token}"
        "</p>"

        "<p style='color:#6B7280'>"
        "This code expires soon. If you did not create a "
        "Tripora account, you can safely ignore this email."
        "</p>"

        "<p style='color:#9CA3AF'>"
        "– The Tripora team"
        "</p>"

        "</div>"
    )


def send_verification_email(to_email: str, token: str) -> bool:
    """Send a verification email using Resend.

    Args:
        to_email: Recipient email address.
        token: Verification code/token.

    Returns:
        True if Resend accepted the email.
        False if configuration is missing or sending failed.
    """

    # ------------------------------------------------------------
    # VALIDATE INPUT
    # ------------------------------------------------------------

    to_email = to_email.strip()
    token = str(token).strip()

    if not to_email:
        logger.error("Cannot send verification email: recipient is empty.")
        return False

    if not token:
        logger.error(
            "Cannot send verification email to %s: token is empty.",
            to_email,
        )
        return False

    # ------------------------------------------------------------
    # CHECK RESEND CONFIGURATION
    # ------------------------------------------------------------

    if not _email_configured():
        logger.error(
            "Resend is not configured. "
            "RESEND_API_KEY and RESEND_FROM_EMAIL are required."
        )
        return False

    # ------------------------------------------------------------
    # RESEND CONFIGURATION
    # ------------------------------------------------------------

    resend.api_key = _env("RESEND_API_KEY")

    from_name = _env("RESEND_FROM_NAME", "Tripora")
    from_email = _env("RESEND_FROM_EMAIL")

    sender = f"{from_name} <{from_email}>"

    # ------------------------------------------------------------
    # SEND EMAIL
    # ------------------------------------------------------------

    try:
        response = resend.Emails.send(
            {
                "from": sender,
                "to": [to_email],
                "subject": "Verify your Tripora account",
                "html": _build_html(token),
            }
        )

        logger.info(
            "Verification email successfully accepted by Resend "
            "for %s. Response: %s",
            to_email,
            response,
        )

        return True

    except Exception as error:
        logger.exception(
            "Failed to send verification email to %s: %s",
            to_email,
            error,
        )
        return False
