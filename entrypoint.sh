#!/bin/sh
set -eu

APP_DIR="${APP_DIR:-/app}"
VENV_DIR="${VENV_DIR:-$APP_DIR/.venv}"

cd "$APP_DIR"

export UV_PROJECT_ENVIRONMENT="${UV_PROJECT_ENVIRONMENT:-$VENV_DIR}"

venv_is_empty() {
	[ ! -d "$VENV_DIR" ] || [ -z "$(ls -A "$VENV_DIR" 2>/dev/null || true)" ]
}
echo "[entrypoint] $(id)"
#echo "[entrypoint] APP_DIR=$APP_DIR"
#echo "[entrypoint] VENV_DIR=$VENV_DIR"

if venv_is_empty; then
	echo "[entrypoint] missing or empty <.venv> folder"
	echo "[entrypoint] uv sync"
	chown -R 1000:1000 ${VENV_DIR} # TODO uid:gid
	chmod -R 755 ${VENV_DIR}
	uv sync
else
	if [ "${UV_SYNC_ALWAYS:-0}" = "1" ]; then
		echo "[entrypoint] UV_SYNC_ALWAYS=1 : uv sync"
		uv sync
	else
		echo "[entrypoint] <.venv> folder founded (skip uv sync)"
	fi
fi

if [ -z "${1:-}" ]; then
    echo "[entrypoint] No command provided, using default command"
    exec uvicorn src.main:app --host 0.0.0.0 --port 8000 --reload
else
    echo "[entrypoint] exec $(printf "%s " "$@")"
    exec "$@"
fi
