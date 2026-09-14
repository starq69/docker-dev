#!/bin/sh
set -eu

APP_DIR="${APP_DIR:-/app}"
cd "$APP_DIR"

if [ -z "${1:-}" ]; then
    echo "[entrypoint] No command provided, using default command"
    # full hostname in prompt
    export PS1='\u@\H:\w\$ '
    exec bash --noprofile --norc -i
else
    echo "[entrypoint] exec $(printf "%s " "$@")"
    exec "$@"
fi
