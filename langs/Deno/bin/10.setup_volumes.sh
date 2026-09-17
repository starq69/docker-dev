#!/usr/bin/env bash
#
# Deno setup deno_dir volume
#
set -euo pipefail
PROJECT_DIR="$1"
P_TYPE="$2"
P_NAME="$3"
P_TARGET="$4"
shift 4

IMAGE_NAME="${IMAGE_NAME:-${P_TYPE}.${P_NAME}}"
IMAGE_NAME="${IMAGE_NAME,,}"
CONTAINER_NAME="${CONTAINER_NAME:-${P_TARGET}.${P_TYPE}.${P_NAME}}"
#VOLUME_NAME="${VOLUME_NAME:-deno.${P_TARGET}.${P_TYPE}.${P_NAME}}"
VOLUME_NAME="${VOLUME_NAME:-deno_cache.${P_TARGET}.${P_NAME}}"

USER_="${USER_:-$(id -un)}"
UID_="${UID_:-$(id -u)}"
GID_="${GID_:-$(id -g)}"

# Mount fittizio per l'inizializzazione del volume
INIT_MOUNT="/mnt/deno_vol"

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

# Creiamo una struttura interna pulita dentro al volume
ensure_initialized_volume \
    "$VOLUME_NAME" \
    "$INIT_MOUNT" \
    "mkdir -p '${INIT_MOUNT}/cache' && chown -R '${UID_}:${GID_}' '${INIT_MOUNT}'"

