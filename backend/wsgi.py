"""WSGI entrypoint for production servers (Gunicorn/uvicorn, Railway/Render/Fly/VPS).

The app is built at import time via ``create_app()`` in ``app.py``. Production
servers import this module (``wsgi:app``) which is separate from the
``python app.py``-style ``__main__`` debug runner, so ``debug=True`` and the
built-in dev server are never used in production.

Run with, for example::

    gunicorn --bind 0.0.0.0:5000 --workers 2 --timeout 120 wsgi:app

Note: The process-wide, in-memory rate limiter and SQLAlchemy connection pool
require a persistent (non-serverless) host. This is intentionally NOT wired for
Vercel serverless functions.
"""

from app import app

if __name__ == "__main__":
    import os

    # Fallback runner only; production uses Gunicorn. Bind to loopback unless
    # the operator opts in (e.g. HOST=0.0.0.0 inside a container).
    app.run(
        host=os.getenv("HOST", "127.0.0.1"),
        port=int(os.getenv("PORT", "5000")),
    )
