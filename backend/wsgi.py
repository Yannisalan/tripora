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
    app.run(host="0.0.0.0", port=5000)
