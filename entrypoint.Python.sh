#!/bin/sh
set -eu

APP_DIR="${APP_DIR:-/app}"
VENV_DIR="${VENV_DIR:-$APP_DIR/.venv}"

cd "$APP_DIR"

export UV_PROJECT_ENVIRONMENT="${UV_PROJECT_ENVIRONMENT:-$VENV_DIR}"

check_venv() {
    [ ! -d "$VENV_DIR" ] && echo "[entrypoint] MISSING $VENV_DIR" && return 2
    [ -z "$(ls -A "$VENV_DIR" 2>/dev/null)" ] && echo "[entrypoint] EMPTY $VENV_DIR" && return 1
    return 0
}
echo "[entrypoint] $(id)"
echo "[entrypoint] APP_DIR=$APP_DIR"
echo "[entrypoint] VENV_DIR=$VENV_DIR"

if check_venv; then
    if [ "${UV_SYNC_ALWAYS:-0}" = "1" ]; then
	echo "[entrypoint] UV_SYNC_ALWAYS=1 --> uv sync"
	echo "[entrypoint] uv sync"
	uv sync
    else
	echo "[entrypoint] NON empty $VENV_DIR found --> skip uv sync"
    fi
else
    ret=$?
    if [ "$ret" -eq 1 ]; then
	owner=$(stat -c "%U" "$VENV_DIR")
	echo "[entrypoint] $VENV_DIR owner=$owner"
	if [ "$owner" = "root" ]; then
    	    echo "[entrypoint] WARNING: $VENV_DIR owner is root, check 'docker run' command and try again..."
	    exit 1
	fi
        #id
        #ls -ld $VENV_DIR
        #chown -R 1000:1000 $VENV_DIR
        #chmod -R 755 $VENV_DIR
        #id
        #ls -ld $VENV_DIR
	#echo "segue uv sync..."

	uv sync

    elif [ "$ret" -eq 2 ]; then
        echo "[entrypoint] WARNING: missing $VENV_DIR volume mount, check 'docker run' command and try again..."
	exit 1
    fi
fi

if [ -z "${1:-}" ]; then
    echo "[entrypoint] No command provided, using default command"
    #exec uvicorn src.main:app --host 0.0.0.0 --port 8000 --reload
    exec bash
else
    echo "[entrypoint] exec $(printf "%s " "$@")"
    exec "$@"
fi
