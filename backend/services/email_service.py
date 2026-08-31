"""Email delivery for Tripora (verification codes).

Uses SMTP from the Python standard library (``smtplib``/``email``), so no extra
dependency is required. Everything is configured through server-side
environment variables (never the client).

Configuration (all optional; when unset the module falls back to a log-only
placeholder so local dev / tests keep working without a mail server):

    MAIL_HOST           SMTP host, e.g. ``smtp-relay.brevo.com``
    MAIL_PORT           SMTP port, e.g. ``587`` (STARTTLS) or ``465`` (SSL)
    MAIL_USER           SMTP username/login (e.g. Brevo SMTP key part)
    MAIL_PASSWORD       SMTP password/secret (e.g. Brevo SMTP key)
    MAIL_FROM           Sender address, e.g. ``you@gmail.com``
                        (must be a confirmed sender in the provider)
    MAIL_FROM_NAME      Optional display name (default "Tripora")
    MAIL_USE_TLS        "tls" / "true" for STARTTLS on 587 (default when
                        port != 465), "ssl" for implicit SSL on 465

The "from" address can be a personal email now and swapped to a domain sender
later — only ``MAIL_FROM`` changes; no code changes are needed.
"""

import logging
import os
import smtplib
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText

logger = logging.getLogger(__name__)


def _env(name, default=""):
    return os.getenv(name, default)


def _email_configured():
    return bool(_env("MAIL_HOST") and _env("MAIL_PASSWORD"))


def _build_message(to_email, token):
    subject = "Verify your Tripora account"

    body = (
        "Hi,\n\n"
        "Welcome to Tripora! Use the code below to verify your email "
        "address and finish setting up your account:\n\n"
        f"{token}\n\n"
        "This code expires soon. If you did not create a Tripora account, "
        "you can safely ignore this email.\n\n"
        "– The Tripora team"
    )

    msg = MIMEMultipart("alternative")
    msg["Subject"] = subject
    msg["To"] = to_email
    msg["From"] = "%s <%s>" % (
        _env("MAIL_FROM_NAME", "Tripora"),
        _env("MAIL_FROM", ""),
    )
    msg.attach(MIMEText(body, "plain"))

    html_body = (
        "<div style='font-family:Arial,Helvetica,sans-serif;max-width:480px'>"
        "<h2 style='color:#111827'>Verify your Tripora account</h2>"
        "<p>Welcome to Tripora! Use the code below to verify your email "
        "address:</p>"
        "<p style='font-size:20px;font-weight:bold;letter-spacing:2px;"
        "background:#F3F4F6;padding:12px 16px;border-radius:8px'>"
        f"{token}</p>"
        "<p style='color:#6B7280'>This code expires soon. If you did not "
        "create a Tripora account, you can safely ignore this email.</p>"
        "<p style='color:#9CA3AF'>– The Tripora team</p>"
        "</div>"
    )
    msg.attach(MIMEText(html_body, "html"))

    return msg


def send_verification_email(to_email, token):
    """Send the email verification code to the user.

    Args:
        to_email (str): The recipient's email address.
        token (str): The verification token/code for the user.

    Returns:
        bool: True when the email was sent (or queued) successfully,
              False when delivery failed.
    """
    if not _email_configured():
        logger.info(
            "[EMAIL-PLACEHOLDER] Verification code generated for %s "
            "(SMTP not configured)",
            to_email,
        )
        logger.info("[EMAIL-PLACEHOLDER] token for %s: %s", to_email, token)
        return True

    msg = _build_message(to_email, token)
    host = _env("MAIL_HOST")
    port_raw = _env("MAIL_PORT", "")
    try:
        port = int(port_raw) if port_raw else (465 if _env("MAIL_USE_TLS", "tls").lower() == "ssl" else 587)
    except (TypeError, ValueError):
        port = 587

    use_ssl = _env("MAIL_USE_TLS", "").lower() in ("ssl", "tls_ssl") or port == 465

    try:
        if use_ssl:
            with smtplib.SMTP_SSL(host, port, timeout=30) as server:
                server.login(_env("MAIL_USER"), _env("MAIL_PASSWORD"))
                server.sendmail(_env("MAIL_FROM"), [to_email], msg.as_string())
        else:
            with smtplib.SMTP(host, port, timeout=30) as server:
                server.ehlo()
                server.starttls()
                server.ehlo()
                server.login(_env("MAIL_USER"), _env("MAIL_PASSWORD"))
                server.sendmail(_env("MAIL_FROM"), [to_email], msg.as_string())

        logger.info("Verification email sent to %s", to_email)
        return True

    except Exception:
        # Log the full traceback for diagnostics. Do NOT re-raise: a transient
        # mail outage should not prevent registration or trigger a 500. The
        # caller can fall back to the user resending the code later.
        logger.exception("Failed to send verification email to %s", to_email)
        return False
