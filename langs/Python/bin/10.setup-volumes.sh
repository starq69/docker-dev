#!/usr/bin/env bash
#
# Python setup volumes
#
set -euo pipefail

PROJECT_DIR="$1"
IMAGE_NAME="$2"
CONTAINER_NAME="$3"
shift 3
CONTAINER_CMD=("$@")

VOLUME_NAME="${VOLUME_NAME:-venv.${CONTAINER_NAME}}"
APP_DIR_IN_CONTAINER="/app"
VENV_DIR_IN_CONTAINER="/app/.venv"

# Host
UID_="${UID_:-$(id -u)}"
GID_="${GID_:-$(id -g)}"

ensure_initialized_volume() {
    local volume_name="$1"
    local mount_path="$2"
    local init_cmd="$3"

    if docker volume inspect "$volume_name" >/dev/null 2>&1; then
        echo "[volumes] Docker volume già presente: ${volume_name}"
        return 0
    fi

    echo "[volumes] Creo e inizializzo Docker volume: ${volume_name}"
    docker volume create "$volume_name" >/dev/null

    docker run --rm \
        -v "${volume_name}:${mount_path}" \
        alpine:3.20 \
        sh -c "$init_cmd" \
        >/dev/null
}

ensure_initialized_volume \
    "$VOLUME_NAME" \
    "$APP_DIR_IN_CONTAINER" \
    "mkdir -p '${APP_DIR_IN_CONTAINER}' && chown -R '${UID_}:${GID_}' '${APP_DIR_IN_CONTAINER}'"

ensure_initialized_volume \
    "uv-python" \
    "/uvpy" \
    "mkdir -p /uvpy && chown -R '${UID_}:${GID_}' /uvpy"
