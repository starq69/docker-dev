#!/usr/bin/env bash
#
# Perl build
#
set -euo pipefail

PROJECT_DIR="$1"
P_TYPE="$2"
P_NAME="$3"
P_TARGET="$4"
shift 4
CONTAINER_CMD=("$@")

IMAGE_NAME="${IMAGE_NAME:-${P_TARGET}.${P_TYPE}}"
IMAGE_NAME="${IMAGE_NAME,,}"
CONTAINER_NAME="${CONTAINER_NAME:-${IMAGE_NAME}.${P_NAME}}"
VOLUME_NAME="${VOLUME_NAME:-local.${P_TARGET}.${P_TYPE}.${P_NAME}}"

# Costanti Python
APP_DIR_IN_CONTAINER="/app"
VENV_DIR_IN_CONTAINER="/app/local"

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
