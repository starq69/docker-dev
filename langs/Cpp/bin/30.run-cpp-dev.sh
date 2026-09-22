#!/usr/bin/env bash
#
# C/Cpp run
#

##!/bin/sh -
#USERNAME=$(id -un)
#docker run -it --rm \
#  -v "$(pwd)":"/home/$USERNAME/app":rw \
#  -w "/home/$USERNAME/app" \
#  cpp-dev bash
#

set -euo pipefail

PROJECT_DIR="$1"
P_TYPE="$2"
P_NAME="$3"
P_TARGET="$4"
shift 4
CONTAINER_CMD=("$@")

source "$(dirname -- "${BASH_SOURCE[0]}")/../../lib/docker-names.sh"
docker_names

DOCKER_RUN_EXTRA_ARGS="${DOCKER_RUN_EXTRA_ARGS:---rm -it}"
APP_DIR_IN_CONTAINER='/app'

if docker ps -a --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
    echo "[run] Rimuovo container esistente: ${CONTAINER_NAME}"
    docker rm -f "$CONTAINER_NAME" >/dev/null
fi

echo "[run] Avvio container: ${CONTAINER_NAME}"

run_args=(
    --name "$CONTAINER_NAME"
    --hostname "$CONTAINER_NAME"
    -v "${PROJECT_DIR}":"${APP_DIR_IN_CONTAINER}":rw \
    -w "${APP_DIR_IN_CONTAINER}" \
    "$IMAGE_NAME"
)

if [[ -n "$DOCKER_RUN_EXTRA_ARGS" ]]; then
    read -r -a extra_args <<< "$DOCKER_RUN_EXTRA_ARGS"
    run_args=("${extra_args[@]}" "${run_args[@]}")
fi

if [[ "${#CONTAINER_CMD[@]}" -gt 0 ]]; then
    echo "[run] Comando container:$(printf ' %q' "${CONTAINER_CMD[@]}")"
    docker run "${run_args[@]}" "${CONTAINER_CMD[@]}"
else
    docker run "${run_args[@]}"
fi
