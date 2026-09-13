#!/usr/bin/env bash
#
# C/Cpp build
#

## !/bin/sh -
#docker build \
#  -f Dockerfile.clang_gcc \
#  --build-arg USER_UID=$(id -u) \
#  --build-arg USER_GID=$(id -g) \
#  --build-arg USERNAME=$(id -un) \
#  -t cpp-dev .
#

set -euo pipefail

PROJECT_DIR="$1"
P_TYPE="$2"
P_NAME="$3"
P_TARGET="$4"
shift 4
CONTAINER_CMD=("$@")

# Derivati
IMAGE_NAME="${IMAGE_NAME:-${P_TYPE}.${P_NAME}}"
CONTAINER_NAME="${CONTAINER_NAME:-${P_TARGET}.${P_TYPE}.${P_NAME}}"

# Host
TZ="${TZ:-Europe/Rome}"
USER_="${USER_:-$(id -un)}"
UID_="${UID_:-$(id -u)}"
GID_="${GID_:-$(id -g)}"

DOCKERFILE="${PROJECT_DIR}/.devcontainer/Dockerfile.clang_gcc"

if [[ ! -f "$DOCKERFILE" ]]; then
    echo "[build] ERRORE: Dockerfile non trovato: $DOCKERFILE" >&2
    exit 1
fi

if docker inspect --type=image "$IMAGE_NAME" >/dev/null 2>&1; then
    echo "[build] Image ${IMAGE_NAME} already exists. Skipping build."
else
    echo "[build] Build image: ${IMAGE_NAME,,} with Dockerfile <$DOCKERFILE>"

    docker build \
	#--no-cache \
        -f "$DOCKERFILE" \
        --build-arg "USERNAME=${USER_}" \
        --build-arg "USER_UID=${UID_}" \
        --build-arg "USER_GID=${GID_}" \
        -t "${IMAGE_NAME,,}" . 	
fi
