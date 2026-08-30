import logging

logger = logging.getLogger(__name__)


# ============================================================
# EMAIL SERVICE
# ============================================================
#
# IMPORTANT:
#   A real email provider has NOT been configured yet.
#
#   The user will provide the email service / provider details
#   later. Until then this module only logs the verification
#   token so the flow can be tested without exposing it to the
#   API response or the Flutter UI.
#
#   To wire up a real provider (e.g. SMTP, SendGrid, Resend,
#   etc.), replace the body of `send_verification_email`
#   with the provider's send call.
# ============================================================


def send_verification_email(to_email, token):
    """Send the email verification code to the user.

    Args:
        to_email (str): The recipient's email address.
        token (str): The verification token/code for the user.

    Returns:
        bool: True when the email was sent (or queued) successfully,
              False when delivery failed.
    """
    logger.info(
        "[EMAIL-PLACEHOLDER] Verification code generated for %s",
        to_email,
    )

    # TODO(provider):
    # Wire up the real email provider here once it is provided.
    # Example (conceptual):
    #
    #   _send_email(
    #       to=to_email,
    #       subject="Verify your Tripora account",
    #       body=(
    #           "Your Tripora verification code is:\n\n"
    #           f"{token}\n\n"
    #           "If you did not create this account, you can "
    #           "ignore this email."
    #       ),
    #   )

    return True
