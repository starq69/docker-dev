#!/usr/bin/env bash
###############################################
#
# vedi:
# - https://www.perplexity.ai/search/e-possibile-in-un-dockerfile-e-2oSS5RzdTC.AYy_JX1mIWQ
# - exported as: Perplexity-thread-init_sh.md
#
# todo:
# env variable ORG (ora corrisp. a <user>)
# as-is:
# /home/<user>/REP e' la root del repository
#
# -d /home/<user>/REP/Python/foo-project (la cartella deve esistere con permessi rw)
#
# hyp.:
# -d /Python/new-project
#
# la validazione del progetto parte dalla ROOT /home/<user>/REP: 
# ROOT/Python DEVE ESISTERE
# quindi:
# se ROOT/Python/new-project esiste, procede come in as-is
# altrimenti crea la struttura del progetto e inizializza
#
###############################################
set -euo pipefail

usage() {
  echo "Usage: $0 [-d PROJECT_DIR] [-i IMAGE_NAME] [-c CONTAINER_NAME] [-v VOLUME_NAME]"
  echo "  -d  Specify the project directory (default: current working directory)"
  echo "  -i  Specify the docker image name" 
  echo "  -c  Specify the docker container name" 
  echo "  -v  Specify the docker volume name"
  echo "  NON-Options arguments to be passed to docker run / entrypoint.sh"
  exit 1
}

ask_to_proceed() {
  echo
  echo "Do you want to proceed? [Y/n]"
  read -p "" -n 1 -r
  echo
  REPLY=${REPLY:-Y}
  if [[ $REPLY =~ ^[Yy]$ ]]
  then
    return 0
  else
    return 1
  fi
}

check_dir() {
  #
  # TODO is_writable_dir()
  #
  local project_dir="$1"

  if [[ ! -d "$project_dir" ]]; then
    #echo "ERRORE: Invalid path [ $project_dir ]"
    return 1
  fi

  if [[ ! -w "$project_dir" ]]; then
    echo "[init] WARNING: Current user does not have write permission to $project_dir"
    #echo "Please ensure that the current user has write permission or run the script as a user with write permission."
    return 1
  fi

  return 0
}

validate_project() {
  local project="$1"
  echo "[init] validate_project: $project"
  if ! check_dir $project; then
    echo "[init] WARNING: Match $project into $BASE ..."
  else
    echo "[init] existent project: $project"
  fi
}

validate_org() {
  if [ -z "${ORG+x}" ]; then
    # ORG is NOT set
    echo "ORG is NOT set, fallback to $HOME"
    ORG="$HOME"
    BASE="$HOME/REP"
  else
    # ORG is set
    BASE="$ORG/REP"
  fi

  if ! check_dir $BASE; then
    echo "[init] ERROR: Invalid ORG=$ORG, fallback to $HOME"
    ORG="$HOME"
    BASE="$HOME/REP"
  fi

  echo "ORG : $ORG"
  echo "BASE: $BASE"
}

##################################################################################################

validate_org;

while getopts ":d:i:c:v:" opt; do
  case $opt in
    #d) PROJECT_DIR=$OPTARG;;
    #d) PROJECT_DIR=$(readlink -f "$OPTARG");;
    d)
        if ! PROJECT_DIR=$(readlink -f "$OPTARG"); then
          echo "[init] WARNING Invalid path '$OPTARG'" >&2
	  PROJECT_DIR=$OPTARG
        fi;;
    i) IMAGE_NAME=$OPTARG;;
    c) CONTAINER_NAME=$OPTARG;;
    v) VOLUME_NAME=$OPTARG;;
    \?) usage;;
  esac
done

shift $((OPTIND-1))

CONTAINER_CMD=("$@")
ONE_LINE_CONTAINER_CMD=$(printf "%s " "${CONTAINER_CMD[@]}")
echo "NON-Options arguments (container command): $ONE_LINE_CONTAINER_CMD"

TZ="${TZ:-Europe/Rome}"
HOSTUSER="$(id -un)"    	# ${HOSTUSER:-$(id -un)}"
UID_="${UID_:-$(id -u)}"
GID_="${GID_:-$(id -g)}"

PROJECT_DIR="${PROJECT_DIR:-$(pwd)}"

# TEST
validate_project $PROJECT_DIR;
exit 1

if ! check_dir "$PROJECT_DIR"; then
  echo "[init] ERROR: Invalid path passed with -d option [$PROJECT_DIR]"
  exit 1
fi

# Split PROJECT_DIR into components
IFS='/' read -r -a components <<< "$PROJECT_DIR"

# Find the index of 'REP'
REP_INDEX=-1
for i in "${!components[@]}"; do
  if [ "${components[i]}" = "REP" ]; then
    REP_INDEX=$i
    break
  fi
done

if [ $REP_INDEX -ne -1 ]; then
  # Extract project name, type, and target from PROJECT_DIR
  P_NAME=$(basename "$PROJECT_DIR" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/_/g')
  P_TARGET=${components[REP_INDEX + 1]}
  P_TYPE=${components[REP_INDEX + 2]}

  # Format P_NAME to replace '-' with '_'
  P_NAME=${P_NAME//-/_}

  echo "Project Folder : $PROJECT_DIR"
  echo "Project Name   : $P_NAME"
  echo "Project Type   : $P_TYPE"	# Project Language...
  echo "Project Target : $P_TARGET"
else
  echo "ERROR: 'REP' directory not found in path [ $PROJECT_DIR ]"
  exit 1
fi

# Default values for other variables
#
IMAGE_NAME="${IMAGE_NAME:-${P_NAME}}"
CONTAINER_NAME="${CONTAINER_NAME:-${P_TARGET}.${P_NAME}}"
VOLUME_NAME="${VOLUME_NAME:-venv.${P_TARGET}.${P_NAME}}"


echo "Image Name     : $IMAGE_NAME"
echo "Container Name : $CONTAINER_NAME"
echo "Volume Name    : $VOLUME_NAME"

# NOTA:
# semplifico usando sempre /app al posto di $P_NAME (run manuali dei containers + uniformi)
#
#APP_DIR_IN_CONTAINER="/${P_NAME}" 
#VENV_DIR_IN_CONTAINER="/${P_NAME}/.venv" 
APP_DIR_IN_CONTAINER="/app" 
VENV_DIR_IN_CONTAINER="/app/.venv" 

DOCKER_RUN_EXTRA_ARGS="${DOCKER_RUN_EXTRA_ARGS:-}"

echo "APP_DIR_IN_CONTAINER  : $APP_DIR_IN_CONTAINER"
echo "VENV_DIR_IN_CONTAINER : $VENV_DIR_IN_CONTAINER"
echo "TZ                    : $TZ"
echo "HOSTUSER              : $HOSTUSER"
echo "UID                   : $UID_"
echo "GID                   : $GID_"
echo
echo "DOCKER_RUN_EXTRA_ARGS : $DOCKER_RUN_EXTRA_ARGS"
echo "CONTAINER_CMD         : $ONE_LINE_CONTAINER_CMD"

if ! ask_to_proceed; then
  echo "Exiting..."
  exit 1
fi

echo "WARNING: COPIO DIRETTAMENTE Dockerfile.Python..."

DOCKERFILE=~/.local/share/docker-dev/Dockerfile.$P_TYPE
if [[ -f $DOCKERFILE ]]; then
  #echo "$DOCKERFILE --> ok"
  #echo "copio in $PROJECT_DIR ..."
  cp $DOCKERFILE $PROJECT_DIR
  DOCKERFILE="$PROJECT_DIR/Dockerfile.$P_TYPE" ### !!!
  echo "...Dockerfile --> $DOCKERFILE"
fi

echo "WARNING: COPIO DIRETTAMENTE entrypoint.sh..."
ENTRYPOINT=~/.local/share/docker-dev/entrypoint.sh
if [[ -f $ENTRYPOINT ]]; then
  #echo "$ENTRYPOINT --> ok"
  cp $ENTRYPOINT $PROJECT_DIR
  ENTRYPOINT="$PROJECT_DIR/entrypoint.sh"
  echo "...entrypoint --> $ENTRYPOINT"
fi

command -v docker >/dev/null 2>&1 || { echo "Errore: 'docker' non trovato nel PATH dell'host."; exit 1; }
echo "docker found..."
command -v uv >/dev/null 2>&1 || { echo "Errore: 'uv' non trovato nel PATH dell'host."; exit 1; }
echo "uv found..."

cd "$PROJECT_DIR"

# ---- Step 1: uv init (only if needed) ----
#
echo "project type=<$P_TYPE>"
if [[ "$P_TYPE" != "Python" ]]; then
  echo "[init] Can manage Python projects only."
  exit 1
fi
echo "[init] Python project found..."

if [ ! -f "pyproject.toml" ]; then
  echo "[init] Missing pyproject.toml -> uv init"
  uv init
else
  echo "[init] pyproject.toml already present -> skip uv init"
fi

# ---- Step 2: uv lock (create if missing, refresh if needed) ----
#
if [ ! -f "uv.lock" ]; then
  echo "[init] Missing uv.lock -> uv lock"
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
#
echo "[init] Creo (o riuso) volume: ${VOLUME_NAME}"
docker volume create "${VOLUME_NAME}" >/dev/null

# ---- Step 3b: init-volume-chown (make volume writable by host UID/GID) ----
#
echo "[init] Inizializzo permessi volume ${VOLUME_NAME} -> chown ${UID_}:${GID_}"
docker run --rm \
  -v "${VOLUME_NAME}:${APP_DIR_IN_CONTAINER}" \
  alpine:3.20 \
  sh -c "mkdir -p ${APP_DIR_IN_CONTAINER} && chown -R ${UID_}:${GID_} ${APP_DIR_IN_CONTAINER}" >/dev/null

#exit 0

echo "[ $(pwd)/Dockerfile ]"

# ---- Step 4: build image ----
#
if docker inspect --type=image "$IMAGE_NAME" > /dev/null 2>&1; then
  echo "[init] Image ${IMAGE_NAME} already exists. Skipping build."
else
  echo "[init] Build image: ${IMAGE_NAME} with Dockerfile <$DOCKERFILE>"
  docker build \
    --build-arg "HOSTUSER=$HOSTUSER" \
    --build-arg "UID=$UID_" \
    --build-arg "GID=$GID_" \
    --build-arg "TZ=$TZ" \
    --build-arg "APP_DIR=$APP_DIR_IN_CONTAINER" \
    -t "$IMAGE_NAME" \
    -f $DOCKERFILE \
    .
fi

# ---- Step 5: run container ----
# docker run -it -p 8000:8000 -v "/home/starq/REP/DEV/Python/foo:/app" -v venv.DEV.foo:/app/.venv
#
if docker ps -a --format '{{.Names}}' | grep -qx "${CONTAINER_NAME}"; then
  echo "[init] Rimuovo container esistente: ${CONTAINER_NAME}"
  docker rm -f "${CONTAINER_NAME}" >/dev/null
fi

echo "[init] Avvio container: ${CONTAINER_NAME}"
if [ "${#CONTAINER_CMD[@]}" -gt 0 ]; then
  echo "[init] run container with arguments: < $ONE_LINE_CONTAINER_CMD>"
  docker run --rm -it \
    --name "${CONTAINER_NAME}" \
    -v "${PROJECT_DIR}:${APP_DIR_IN_CONTAINER}" \
    -v "${VOLUME_NAME}:${VENV_DIR_IN_CONTAINER}" \
    ${DOCKER_RUN_EXTRA_ARGS} \
    "${IMAGE_NAME}" \
    "${CONTAINER_CMD[@]}"
else
  echo "[init] run container with NO arguments"
  docker run --rm -it \
    --name "${CONTAINER_NAME}" \
    -v "${PROJECT_DIR}:${APP_DIR_IN_CONTAINER}" \
    -v "${VOLUME_NAME}:${VENV_DIR_IN_CONTAINER}" \
    ${DOCKER_RUN_EXTRA_ARGS} \
    "${IMAGE_NAME}"
fi

exit 0
