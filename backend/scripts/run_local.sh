#!/usr/bin/env bash
# Run the backend locally in TRIPORA_LOCAL_ONLY safety mode.
#
#   bash backend/scripts/run_local.sh            # migrate local DB, then serve
#   bash backend/scripts/run_local.sh --no-migrate
#
# Stop with Ctrl+C. Configuration: backend/.env.local (copy
# backend/.env.local.example). backend/.env is never read in this mode, a
# non-loopback DB_HOST (e.g. Neon) is refused before any connection, and no
# e-mail is sent. Prints no configuration values.
set -euo pipefail

cd "$(dirname "$0")/.."

export TRIPORA_LOCAL_ONLY=1
export TRIPORA_ENV_FILE="${TRIPORA_ENV_FILE:-$PWD/.env.local}"
# The flask CLI would otherwise auto-load backend/.env (production settings).
export FLASK_SKIP_DOTENV=1

if [ ! -f "$TRIPORA_ENV_FILE" ]; then
  echo "Missing $TRIPORA_ENV_FILE. Copy backend/.env.local.example to backend/.env.local first." >&2
  exit 1
fi

PY=venv/Scripts/python
[ -x "$PY" ] || [ -x "$PY.exe" ] || PY=venv/bin/python

if [ "${1:-}" != "--no-migrate" ]; then
  "$PY" -m flask --app app db upgrade
fi

exec "$PY" -m flask --app app run --host 127.0.0.1 --port "${PORT:-5000}"
