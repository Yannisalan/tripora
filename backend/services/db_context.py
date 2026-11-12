"""Per-transaction PostgreSQL Row-Level Security context.

The RLS policies (migrations ``f0e9d8c7b6a5`` and ``a9b8c7d6e5f4``) read three
transaction-local settings:

``request.jwt.claims.sub``  the verified JWT subject (user id)
``app.auth_flow``           'on' inside pre-authentication flows that must look
                             users up by email or token (login, register,
                             refresh, password reset, admin login, admin CLI)
``app.admin_read``          'on' only after the admin guard has authorized the
                             request

Values live in context variables that the app sets from *server-side*
decisions (verified token, endpoint name, admin authorization) and never
from client input. A SQLAlchemy ``after_begin`` hook re-applies them at the
start of EVERY transaction, so a ``commit()`` in the middle of a request does
not silently drop the context (``set_config(..., true)`` is transaction-local).

On non-PostgreSQL engines (the SQLite test database) this is a no-op.
"""

import contextlib
import contextvars
import logging

from sqlalchemy import event, text
from sqlalchemy.orm import Session

logger = logging.getLogger(__name__)

_sub = contextvars.ContextVar("tripora_rls_sub", default=None)
_auth_flow = contextvars.ContextVar("tripora_rls_auth_flow", default=False)
_admin_read = contextvars.ContextVar("tripora_rls_admin_read", default=False)


def _sync_open_transaction(strict=True):
    """Re-apply the context to a transaction that is already open.

    ``after_begin`` only fires when a transaction starts. If the context
    changes while the scoped session already holds an open transaction (a
    CLI command after earlier queries, a session that outlived a request),
    that transaction would otherwise keep the previous settings.
    """
    try:
        from flask import has_app_context

        if not has_app_context():
            return
        from config.database import db

        session = db.session()
        transaction = session.get_transaction()
        # A failed transaction can only be rolled back, and rollback discards
        # its transaction-local settings anyway.
        if transaction is not None and transaction.is_active:
            apply_to_connection(session.connection())
    except Exception:
        logger.exception("Failed to re-apply the RLS context")
        if strict:
            raise


def reset():
    """Clear the context (start and end of every request)."""
    _sub.set(None)
    _auth_flow.set(False)
    _admin_read.set(False)
    # Never fail a request teardown over this: the cleared context only
    # narrows access, and the session is rolled back/removed afterwards.
    _sync_open_transaction(strict=False)


def set_subject(user_id):
    _sub.set(str(int(user_id)) if user_id is not None else None)
    _sync_open_transaction()


def enable_auth_flow():
    _auth_flow.set(True)
    _sync_open_transaction()


def enable_admin_read():
    _admin_read.set(True)
    _sync_open_transaction()


def current():
    return {
        "sub": _sub.get(),
        "auth_flow": _auth_flow.get(),
        "admin_read": _admin_read.get(),
    }


@contextlib.contextmanager
def scoped(sub=None, auth_flow=False, admin_read=False):
    """Temporarily apply a context (used by CLI commands and tests)."""
    tokens = (
        _sub.set(str(int(sub)) if sub is not None else None),
        _auth_flow.set(bool(auth_flow)),
        _admin_read.set(bool(admin_read)),
    )
    _sync_open_transaction()
    try:
        yield
    finally:
        _sub.reset(tokens[0])
        _auth_flow.reset(tokens[1])
        _admin_read.reset(tokens[2])
        _sync_open_transaction()


def apply_to_connection(connection):
    """Write the current context into the connection's transaction."""
    if connection.dialect.name != "postgresql":
        return
    connection.execute(
        text(
            "SELECT "
            "set_config('request.jwt.claims.sub', :sub, true), "
            "set_config('app.auth_flow', :auth_flow, true), "
            "set_config('app.admin_read', :admin_read, true)"
        ),
        {
            "sub": _sub.get() or "",
            "auth_flow": "on" if _auth_flow.get() else "off",
            "admin_read": "on" if _admin_read.get() else "off",
        },
    )


@event.listens_for(Session, "after_begin")
def _apply_rls_context(session, transaction, connection):
    try:
        apply_to_connection(connection)
    except Exception:
        # Fail closed: without the context every RLS policy denies access.
        logger.exception("Failed to apply the RLS context")
        raise
