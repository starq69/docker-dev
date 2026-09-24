#!/bin/sh
#
# entrypoint.Perl
#

set -eu

APP_DIR="${APP_DIR:-/app}"
VENV_DIR="${VENV_DIR:-$APP_DIR/local}"

cd "$APP_DIR"

check_venv() {
    [ ! -d "$VENV_DIR" ] && echo "[entrypoint] MISSING $VENV_DIR" && return 2
    [ -z "$(ls -A "$VENV_DIR" 2>/dev/null)" ] && echo "[entrypoint] EMPTY $VENV_DIR" && return 1
    return 0
}
echo "[entrypoint] $(id)"
echo "[entrypoint] APP_DIR=$APP_DIR"
echo "[entrypoint] VENV_DIR=$VENV_DIR"

if check_venv; then
    if [ ! -f "cpanfile.snapshot" ] && [ -f "cpanfile" ]; then # (nuovo progetto)
	echo "[entrypoint] carton install... "
	carton install --without develop --without test
    else
	echo "[entrypoint] NON empty $VENV_DIR found --> skip carton install"
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

	#if [ ! -f "cpanfile.snapshot" ]; then  # (nuovo progetto)
	if [ -f "cpanfile.snapshot" ]; then
	    echo "[entrypoint] snapshot found --> carton install --deployment"
	    carton install --deployment --without develop --without test
	elif [ -f "cpanfile" ]; then
	    echo "[entrypoint] This is a new project"
	    echo "[entrypoint] carton install..."
	    carton install --without develop --without test
	else
	    echo "[entrypoint] WARNING: cpanfile not found, generate it and run 'carton install'"
	fi

    elif [ "$ret" -eq 2 ]; then
        echo "[entrypoint] WARNING: missing $VENV_DIR volume mount, check 'docker run' command and try again..."
	exit 1
    fi
fi

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
