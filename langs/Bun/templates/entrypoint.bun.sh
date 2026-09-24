#!/bin/sh
#
# Bun entrypoint
#
set -eu

APP_DIR="${APP_DIR:-/app}"
cd "$APP_DIR"

if [ -z "${1:-}" ]; then
    echo "[entrypoint] No command provided, using default command"
    # interactive bash with persistent history (see .docker_container/.bashrc)
    RCFILE="${APP_DIR}/.docker_container/.bashrc"
    if [ ! -f "$RCFILE" ]; then
        echo "[entrypoint] ERROR: missing $RCFILE (re-run docker-dev to apply templates)" >&2
        exit 1
    fi
    exec bash --rcfile "$RCFILE" -i
else
    echo "[entrypoint] exec $(printf "%s " "$@")"
    exec "$@"
fi
