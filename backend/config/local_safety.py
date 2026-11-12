"""Local-only safety mode for running the backend on a developer machine.

``backend/.env`` may hold production credentials (it currently points at the
production Neon database). Set ``TRIPORA_LOCAL_ONLY=1`` for any local run:

* ``backend/.env`` is never loaded. Configuration comes from the process
  environment plus an optional local file (``TRIPORA_ENV_FILE``, default
  ``backend/.env.local``), so nothing falls back to production values. The
  ``flask`` CLI auto-loads ``.env`` on its own, so under the CLI start-up is
  refused unless ``FLASK_SKIP_DOTENV=1`` (``scripts/run_local.sh`` sets it).
* ``DB_HOST`` must be a loopback host (``localhost``, ``127.0.0.1``, ``::1``).
  Anything else, including Neon, is rejected at start-up, before any database
  connection is attempted. Migrations use the same ``DB_HOST`` and are
  covered too.
* E-mail is never sent; delivery is simulated.

Without ``TRIPORA_LOCAL_ONLY`` nothing changes: ``.env`` is loaded as before
and deployed environments behave exactly as they did.

Messages never include credentials or the rejected host name.
"""

import logging
import os
import sys
from pathlib import Path

from dotenv import load_dotenv

logger = logging.getLogger(__name__)

LOCAL_ONLY_VAR = "TRIPORA_LOCAL_ONLY"
ENV_FILE_VAR = "TRIPORA_ENV_FILE"
LOCAL_DB_HOSTS = frozenset({"localhost", "127.0.0.1", "::1"})

_BACKEND_DIR = Path(__file__).resolve().parent.parent
DEFAULT_LOCAL_ENV_FILE = _BACKEND_DIR / ".env.local"
_PRODUCTION_ENV_FILE = (_BACKEND_DIR / ".env").resolve()

_TRUE = {"1", "true", "yes", "on"}


class LocalSafetyError(RuntimeError):
    """Raised when local-only mode would touch a non-local resource."""


def local_only():
    """True when the backend runs in local-only safety mode."""
    return (os.getenv(LOCAL_ONLY_VAR) or "").strip().lower() in _TRUE


def _flask_cli_dotenv_active():
    """True when the ``flask`` CLI has (or will have) auto-loaded ``.env``.

    The Flask CLI loads ``.env`` from the working directory before the app is
    imported unless ``FLASK_SKIP_DOTENV`` is set, which would bring
    backend/.env (production settings) into a local run.
    """
    if (os.getenv("FLASK_SKIP_DOTENV") or "").strip().lower() in _TRUE:
        return False
    argv0 = Path(sys.argv[0] if sys.argv else "")
    name, parent = argv0.name.lower(), argv0.parent.name.lower()
    return name in {"flask", "flask.exe"} or (name == "__main__.py" and parent == "flask")


def load_environment():
    """Load dotenv configuration, respecting local-only mode.

    Normal mode: ``load_dotenv()`` exactly as before. Local-only mode: load
    only the local env file (never ``backend/.env``); variables already set
    in the process environment win.
    """
    if not local_only():
        load_dotenv()
        return

    if _flask_cli_dotenv_active():
        raise LocalSafetyError(
            f"{LOCAL_ONLY_VAR} is set but the flask CLI auto-loads backend/.env "
            "(production settings). Set FLASK_SKIP_DOTENV=1, or use "
            "backend/scripts/run_local.sh."
        )

    path = Path(os.getenv(ENV_FILE_VAR) or DEFAULT_LOCAL_ENV_FILE).resolve()
    if path == _PRODUCTION_ENV_FILE:
        raise LocalSafetyError(
            f"{LOCAL_ONLY_VAR} is set but {ENV_FILE_VAR} points at backend/.env, "
            "which may hold production settings. Use backend/.env.local."
        )
    if path.is_file():
        load_dotenv(path, override=False)


def check_database_host(host):
    """Reject a non-loopback database host in local-only mode.

    Called while the configuration is built, before any engine or connection
    exists. No-op outside local-only mode.
    """
    if not local_only():
        return
    normalized = (host or "").strip().strip("[]").lower()
    if normalized in LOCAL_DB_HOSTS:
        return
    kind = "a Neon host" if "neon.tech" in normalized else "a non-local host"
    raise LocalSafetyError(
        f"{LOCAL_ONLY_VAR} is set but DB_HOST is {kind}. Refusing to start: "
        "local runs may only use the local PostgreSQL container "
        "(DB_HOST=127.0.0.1). No connection was attempted."
    )
