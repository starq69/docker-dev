#!/usr/bin/env bash
#
# Perl image builder 
#
set -euo pipefail

PROJECT_DIR="$1"
IMAGE_NAME="$2"
CONTAINER_NAME="$3"
shift 3
CONTAINER_CMD=("$@")

APP_DIR_IN_CONTAINER="/app"

# Host
TZ="${TZ:-Europe/Rome}"
USER_="${USER_:-$(id -un)}"
UID_="${UID_:-$(id -u)}"
GID_="${GID_:-$(id -g)}"

DOCKERFILE="${PROJECT_DIR}/Dockerfile"

if [[ ! -f "$DOCKERFILE" ]]; then
    echo "[build] ERRORE: Dockerfile non trovato: $DOCKERFILE" >&2
    exit 1
fi

# TODO:
# evitare il check con docker inspect in quanto non permette la rigenerazione
# dell'immagine se cambiano i layers
#
if docker inspect --type=image "$IMAGE_NAME" >/dev/null 2>&1; then
    echo "[build] Image ${IMAGE_NAME} already exists. Skipping build."
else
    echo "[build] Build image: ${IMAGE_NAME} with Dockerfile <$DOCKERFILE>"

    docker build \
        --build-arg "HOSTUSER=${USER_}" \
        --build-arg "UID=${UID_}" \
        --build-arg "GID=${GID_}" \
        --build-arg "TZ=${TZ}" \
        --build-arg "APP_DIR=${APP_DIR_IN_CONTAINER}" \
        -t "$IMAGE_NAME" \
        -f "$DOCKERFILE" \
        "$PROJECT_DIR"
fi
