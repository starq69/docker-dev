#!/bin/sh
set -eu

APP_DIR="${APP_DIR:-/app}"
cd "$APP_DIR"

echo "[entrypoint] $(id)"
echo "[entrypoint] APP_DIR=$APP_DIR"
echo "[entrypoint] to launch VSCode execute 'code .' from WSL project dir (not from container)"
echo "[entrypoint] In VSCode: Ctrl+Shift+P then Dev Containers: Reopen in Container"
echo "[entrypoint] To configure project: Ctrl+Shift+P → CMake: Configure"
echo "[entrypoint] ...or execute cmake -S . -B build -G Ninja"
echo "[entrypoint] To build project: Ctrl+Shift+B o CMake: Build"
echo "[entrypoint] To run/debug with F5..."

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
