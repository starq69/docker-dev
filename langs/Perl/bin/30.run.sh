#!/usr/bin/env bash
#
# Perl container runner
#
set -euo pipefail

PROJECT_DIR="$1"
IMAGE_NAME="$2"
CONTAINER_NAME="$3"
shift 3
CONTAINER_CMD=("$@")

# Perl specific project-local-environment Path
#
LOCAL_ENV_DIR="local"
VOLUME_NAME="${VOLUME_NAME:-${LOCAL_ENV_DIR}.${CONTAINER_NAME}}"
APP_DIR_IN_CONTAINER="/app"
LOCAL_ENV_DIR_IN_CONTAINER="/app/${LOCAL_ENV_DIR}"

source "$(dirname -- "${BASH_SOURCE[0]}")/../../../docker-run-extra-args.sh"
docker_run_extra_args "$PROJECT_DIR"

if docker ps -a --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
    echo "[run] Rimuovo container esistente: ${CONTAINER_NAME}"
    docker rm -f "$CONTAINER_NAME" >/dev/null
fi

echo "[run] Avvio container: ${CONTAINER_NAME}"

run_args=(
    --name "$CONTAINER_NAME"
    --hostname "$CONTAINER_NAME"
    -v "${PROJECT_DIR}:${APP_DIR_IN_CONTAINER}"
    -v "${VOLUME_NAME}:${LOCAL_ENV_DIR_IN_CONTAINER}"
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
