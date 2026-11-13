"""Client-safe error messages (F9).

Exception text is written for developers: it can contain user input echoed
back by a parser, SQL statements and bind parameters, provider names,
configuration state, file paths or library internals. None of that belongs
in an API response.

The rule this module enforces is simple: a handler may only show an
exception's message to the client when the exception is a
``ClientValidationError``, i.e. when the code that raised it wrote the
message *for the client*. Every other exception is reduced to a fixed,
generic message and the detail goes to the server log only.
"""


# Fixed, client-facing messages shared by several routes.
INVALID_SESSION_MESSAGE = "Invalid authenticated user."
GENERIC_INVALID_REQUEST_MESSAGE = "The request could not be processed."
GENERIC_SERVER_ERROR = "Internal server error."
UNEXPECTED_ERROR_MESSAGE = "An unexpected error occurred. Please try again."


class ClientValidationError(ValueError):
    """A validation failure whose message is safe to return to the client.

    Subclasses ``ValueError`` so existing ``except ValueError`` handlers keep
    catching it; only the *message* handling differs.
    """


def client_message(error, fallback=GENERIC_INVALID_REQUEST_MESSAGE):
    """Return ``str(error)`` only for a ``ClientValidationError``.

    Any other exception (including a plain ``ValueError`` raised by the
    standard library, e.g. ``date.fromisoformat``) yields ``fallback``.
    """
    if isinstance(error, ClientValidationError):
        message = str(error).strip()
        if message:
            return message
    return fallback
