#!/usr/bin/env bash
#
# Deno build
#

set -euo pipefail

PROJECT_DIR="$1"
P_TYPE="$2"
P_NAME="$3"
P_TARGET="$4"
shift 4
CONTAINER_CMD=("$@")

source "$(dirname -- "${BASH_SOURCE[0]}")/../../../docker-names.sh"
docker_names

# Host
TZ="${TZ:-Europe/Rome}"
HOSTUSER="${HOSTUSER:-$(id -un)}"
UID_="${UID_:-$(id -u)}"
GID_="${GID_:-$(id -g)}"

DOCKERFILE="${PROJECT_DIR}/Dockerfile"

if [[ ! -f "$DOCKERFILE" ]]; then
    echo "[build] ERRORE: Dockerfile non trovato: $DOCKERFILE" >&2
    exit 1
fi

if docker inspect --type=image "$IMAGE_NAME" >/dev/null 2>&1; then
    echo "[build] Image ${IMAGE_NAME} already exists. Skipping build."
else
    echo "[build] Build image: ${IMAGE_NAME} with Dockerfile <$DOCKERFILE>"

    docker build \
        -f "$DOCKERFILE" \
        --build-arg "HOSTUSER=${HOSTUSER}" \
        --build-arg "UID=${UID_}" \
        --build-arg "GID=${GID_}" \
        -t "${IMAGE_NAME}" . 	
fi
