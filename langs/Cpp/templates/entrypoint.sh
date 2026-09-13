#!/bin/sh
set -eu

APP_DIR="${APP_DIR:-/workspace}"
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
    # full hostname in prompt
    export PS1='\u@\H:\w\$ '
    exec bash --noprofile --norc -i
else
    echo "[entrypoint] exec $(printf "%s " "$@")"
    exec "$@"
fi
