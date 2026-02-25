#!/usr/bin/env bash
#
# vedi: 
# - https://www.perplexity.ai/search/e-possibile-in-un-dockerfile-e-2oSS5RzdTC.AYy_JX1mIWQ
# - exported as: Perplexity-thread-init_sh.md
#
set -euo pipefail

# ---- Config (override via env) ----
PROJECT_DIR="${PROJECT_DIR:-$(pwd)}"
IMAGE_NAME="${IMAGE_NAME:-myapp:dev}"
CONTAINER_NAME="${CONTAINER_NAME:-myapp-dev}"
VOLUME_NAME="${VOLUME_NAME:-my-venv}"

APP_DIR_IN_CONTAINER="${APP_DIR_IN_CONTAINER:-/app}"
VENV_DIR_IN_CONTAINER="${VENV_DIR_IN_CONTAINER:-/app/.venv}"

TZ="${TZ:-Europe/Rome}"
HOSTUSER="${HOSTUSER:-$(id -un)}"
UID_="${UID_:-$(id -u)}"
GID_="${GID_:-$(id -g)}"

DOCKER_RUN_EXTRA_ARGS="${DOCKER_RUN_EXTRA_ARGS:-}"
CONTAINER_CMD=("$@")

cd "$PROJECT_DIR"

command -v uv >/dev/null 2>&1 || { echo "Errore: 'uv' non trovato nel PATH dell'host."; exit 1; }
command -v docker >/dev/null 2>&1 || { echo "Errore: 'docker' non trovato nel PATH dell'host."; exit 1; }

# ---- Step 1: uv init (only if needed) ----
if [ ! -f "pyproject.toml" ]; then
  echo "[init] pyproject.toml non trovato -> uv init"
  uv init
else
  echo "[init] pyproject.toml presente -> skip uv init"
fi

# ---- Step 2: uv lock (create if missing, refresh if needed) ----
if [ ! -f "uv.lock" ]; then
  echo "[init] uv.lock non trovato -> uv lock"
  uv lock
else
  echo "[init] Controllo allineamento uv.lock -> uv lock --check"
  if ! uv lock --check; then
    echo "[init] uv.lock non allineato -> uv lock (rigenero)"
    uv lock
  else
    echo "[init] uv.lock ok -> skip"
  fi
fi

# ---- Step 3: create volume (idempotent) ----
echo "[init] Creo (o riuso) volume: ${VOLUME_NAME}"
docker volume create "${VOLUME_NAME}" >/dev/null

# ---- Step 3b: init-volume-chown (make volume writable by host UID/GID) ----
# Nota: serve perché i named volumes risultano spesso root:root al mount, causando Permission denied in container non-root.
echo "[init] Inizializzo permessi volume ${VOLUME_NAME} -> chown ${UID_}:${GID_}"
docker run --rm \
  -v "${VOLUME_NAME}:/data" \
  alpine:3.20 \
  sh -c "mkdir -p /data && chown -R ${UID_}:${GID_} /data" >/dev/null

# ---- Step 4: build image ----
echo "[init] Build immagine: ${IMAGE_NAME}"
docker build \
  --build-arg "HOSTUSER=${HOSTUSER}" \
  --build-arg "UID=${UID_}" \
  --build-arg "GID=${GID_}" \
  --build-arg "TZ=${TZ}" \
  -t "${IMAGE_NAME}" \
  .

# ---- Step 5: run container ----
if docker ps -a --format '{{.Names}}' | grep -qx "${CONTAINER_NAME}"; then
  echo "[init] Rimuovo container esistente: ${CONTAINER_NAME}"
  docker rm -f "${CONTAINER_NAME}" >/dev/null
fi

echo "[init] Avvio container: ${CONTAINER_NAME}"
if [ "${#CONTAINER_CMD[@]}" -gt 0 ]; then
  docker run --rm -it \
    --name "${CONTAINER_NAME}" \
    -v "${PROJECT_DIR}:${APP_DIR_IN_CONTAINER}" \
    -v "${VOLUME_NAME}:${VENV_DIR_IN_CONTAINER}" \
    ${DOCKER_RUN_EXTRA_ARGS} \
    "${IMAGE_NAME}" \
    "${CONTAINER_CMD[@]}"
else
  docker run --rm -it \
    --name "${CONTAINER_NAME}" \
    -v "${PROJECT_DIR}:${APP_DIR_IN_CONTAINER}" \
    -v "${VOLUME_NAME}:${VENV_DIR_IN_CONTAINER}" \
    ${DOCKER_RUN_EXTRA_ARGS} \
    "${IMAGE_NAME}"
fi

