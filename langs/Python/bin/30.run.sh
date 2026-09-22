#!/usr/bin/env bash
#
# Python run
#
set -euo pipefail

PROJECT_DIR="$1"
P_TYPE="$2"
P_NAME="$3"
P_TARGET="$4"
shift 4
CONTAINER_CMD=("$@")

# Derivati
source "$(dirname -- "${BASH_SOURCE[0]}")/../../../docker-names.sh"
docker_names venv

# Costanti Python
APP_DIR_IN_CONTAINER="/app"
VENV_DIR_IN_CONTAINER="/app/.venv"

# Host
USER_="${USER_:-$(id -un)}"
UID_="${UID_:-$(id -u)}"
GID_="${GID_:-$(id -g)}"

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
    -v "${VOLUME_NAME}:${VENV_DIR_IN_CONTAINER}"
    -v "uv-python:/home/${USER_}/.local/share/uv/python"
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
