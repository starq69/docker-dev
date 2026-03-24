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

#MANAGED_P_TYPES=("Python" "Typescript" "Javascript")

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

validate_project() {
  local project="$1"
  echo "[init] validate_project: $project"
  if ! check_dir $project; then
    echo "[init] WARNING: Match $project into $BASE ..."
  else
    echo "[init] existent project: $project"
  fi
}

ex_validate_project() {
  # 
  # project setup
  # 
  local __PROJECT_DIR="$1"
  _tag="[ex_validate_project]"

  # Split PROJECT_DIR into components
  IFS='/' read -r -a components <<< "$__PROJECT_DIR"
  c_size=${#components[@]}
  echo "$_tag [debug] c_size=${c_size}"

  # Find the index of 'REP'
  REP_INDEX=-1
  for i in "${!components[@]}"; do
    if [ "${components[i]}" = "REP" ]; then
      REP_INDEX=$i
      break
    fi
  done
  echo "$_tag [debug] TODO: check if REP index found... <${REP_INDEX}>"
  echo "$_tag [debug] ...or if REP index = last index!"

  if [ $REP_INDEX -ne -1 ]; then
    # Extract project name, type, and target from PROJECT_DIR
    P_NAME=$(basename "$__PROJECT_DIR" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/_/g')
    P_TARGET=${components[REP_INDEX + 1]}
    P_TYPE=${components[REP_INDEX + 2]}

    #echo "...segue check_project_type..."
    #if ! check_project_type "$P_TYPE"; then
    #  exit 1
    #fi

    # Format P_NAME to replace '-' with '_'
    P_NAME=${P_NAME//-/_}

    echo "Project Folder : $__PROJECT_DIR"
    echo "Project Name   : $P_NAME"
    echo "Project Type   : $P_TYPE"	# Project Language...
    echo "Project Target : $P_TARGET"
  else
    echo "ERROR: 'REP' directory not found in path [ $PROJECT_DIR ]"
    exit 1
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

  # TEMP....
  BASE="$HOME/REP/DEV" # TODO 

  echo "ORG : $ORG"
  echo "BASE: $BASE"

  mapfile -t MANAGED_P_TYPES < <(find "$BASE" -maxdepth 1 -mindepth 1 -type d -printf '%f\n')
  echo "Managed Project types:"
  local __TYPES=$(IFS=", "; echo "${MANAGED_P_TYPES[*]}")
  echo "$__TYPES"

}

is_valid() {

    local _tag="[is_valid]"
    local input="$1"

    #echo "$_tag [debug] $1"

    # 1: Only allow a-zA-Z0-9-_/. characters
    if [[ ! "$input" =~ ^[a-zA-Z0-9._/-]+$ ]]; then
        echo "$_tag Condition 1 FAIL"
        return 1
    fi

    # 2: Can't contain two consecutive dots or slashes
    if [[ "$input" =~ \.\. ]] || [[ "$input" =~ // ]]; then
        echo "$_tag Condition 2 FAIL"
        return 1
    fi

    # 3: Can't contain the sequence '/.'
    if [[ "$input" =~ /\. ]]; then
        echo "$_tag Condition 3 FAIL"
        return 1
    fi

    # 4: Can't begin or end with a dot or slash
    if [[ "$input" =~ ^[./] ]] || [[ "$input" =~ [./]$ ]]; then
        echo "$_tag Condition 4 FAIL"
        return 1
    fi

    # 5: Must contain at least one '/'
    if [[ ! "$input" =~ / ]]; then
        echo "$_tag Condition 5 FAIL"
        return 1
    fi

    return 0
}

check_dir() {
  local _tag="[check_dir]"
  local _dir="$1"
  if [[ ! -d "$_dir" ]]; then
    #echo "ERRORE: Invalid path [ $_dir ]"
    return 1
  fi
  if [[ ! -w "$_dir" ]] || [[ ! -r "$_dir" ]]; then
    echo "$_tag WARNING: Current user does not have read/write permission to $_dir"
    return 1
  fi
  return 0
}

check() {
  local _tag="[check]"
  _resolved="$(readlink -f "$1")" 
  echo "$_tag [debug] resolved=${_resolved}"

  if [[ -d "$_resolved" ]]; then
    echo "$_tag [debug] -d pass"
    if [[ -r "$_resolved" ]] && [[ -w "$_resolved" ]]; then
      echo "$_tag [debug] $1 - -r -w pass"
      PROJECT_DIR="$_resolved"
      #
      ### path assoluto a progetto esistente ###
    else
      echo "$_tag missing rw permission on $_resolved"
      return 1
    fi

  else
    if is_absolute "$1"; then
      echo "$_tag cannot create new absolute path $1"
      echo "$_tag use relative path instead"
      return 1
    fi
    echo "$_tag is_absolute() pass"

    if ! is_valid $1; then
      echo "$_tag $1 is NOT valid"
      return 1
    fi
    echo "$_tag is_valid() pass"

    if ! create_relative_folder "$1"; then
      echo "$_tag Error creating $1" >&2
      return 1
    fi
  fi

  echo "$_tag NEW: ex_validate_project() ...."
  ex_validate_project $PROJECT_DIR
  echo "debug exit"
  exit 1
}

create_relative_folder() {
  #
  # _full_target : e' un project target relativo a ORG (es.: Python/foo corrisp. a $BASE/Python/foo)
  # _p_type      : e' un project type ammesso (es.: Python)
  # _p_target    : e' un project target (es.: /foo)
  #
  local _tag="[create_relative_folder]"
  local _full_target="$1"

  # is_valid() garantisce che ci siano almeno 2 elementi separati da '/'
  #
  IFS=/ read -r -a components <<< "$_full_target"

  local _p_type="${components[0]}"
  local _p_target="${_full_target#*/}"

  # debug
  echo "$_tag p_type=${_p_type}"
  echo "$_tag p_target=${_p_target}"

  if [ ! -d "$BASE/$_p_type" ]; then  # readlink ?
    echo "$_tag WARNING: $_p_type project type is NOT defined" >&2
    echo "$_tag Select one of the following project types:"
    local ALLOWED_TYPES=$(IFS=", "; echo "${MANAGED_P_TYPES[*]}")
    echo "$_tag $ALLOWED_TYPES"
    return 1
  fi

  if [ -n "$_p_target" ]; then
    if [ ! -d "$(readlink -f "$BASE/$_p_type/$_p_target")" ]; then  ### mkdir only if not exist
      echo "$_tag mkdir -p $BASE/$_p_type/$_p_target"
      mkdir -p "$BASE/$_p_type/$_p_target"
    else
      echo "$_tag directory already exist"
    fi
    PROJECT_DIR="$BASE/$_p_type/$_p_target"
  else
    echo "$_tag WARNING: Missing project Name"
    return 1
  fi

  return 0
}

is_absolute() {
  local _tag="[is_absolute]"
  if [[ "$1" =~ ^/ ]]; then
    #echo "$_tag test : absolute path?"
    return 0
  fi
    #echo "$_tag test: relative path?"
    return 1
}

check_project_type() {
  #
  # TODO rimuovere
  #
  local P_TYPE="$1" 
  local FOUND=false
  echo "project type=<$P_TYPE>"

  for TYPE in "${MANAGED_P_TYPES[@]}"; do
    if [[ "$P_TYPE" == "$TYPE" ]]; then
      FOUND=true
      break
    fi
  done

  if [[ "$FOUND" == false ]]; then
    local ALLOWED_TYPES=$(IFS=", "; echo "${MANAGED_P_TYPES[*]}")
    echo "[init] Can manage the following projects only: $ALLOWED_TYPES."
    return 1
  fi
  #echo "[init] Project type '$P_TYPE' is valid."
  return 0
}
##################################################################################################
echo "Welcome to docker-dev"

validate_org;

# Extract --target= mandatory argument or exit
#
for arg in "$@"; do
  case $arg in
    --target=*)
      _target="${arg#--target=}"
      if ! check "$_target"; then
        echo "invalid argument --target=$_target"
        exit 1
      fi
      shift
      break
      ;;
  esac
done

if [ -z "${_target+x}" ]; then
  echo "[init] missing --target argument"
  exit 1
fi

while getopts ":i:c:v:" opt; do
  case $opt in
    i) IMAGE_NAME=$OPTARG;;
    c) CONTAINER_NAME=$OPTARG;;
    v) VOLUME_NAME=$OPTARG;;
    \?) usage;;
  esac
done

shift $((OPTIND-1))

CONTAINER_CMD=("$@")
ONE_LINE_CONTAINER_CMD=$(printf "%s " "${CONTAINER_CMD[@]}")
#echo "NON-Options arguments (container command): $ONE_LINE_CONTAINER_CMD"

TZ="${TZ:-Europe/Rome}"
HOSTUSER="$(id -un)"    	# ${HOSTUSER:-$(id -un)}"
UID_="${UID_:-$(id -u)}"
GID_="${GID_:-$(id -g)}"

#if [ -z "${PROJECT_DIR+x}" ]; then
#  echo "[init] PROJECT_DIR IS NOT SET"
#fi

PROJECT_DIR="${PROJECT_DIR:-$(pwd)}"
echo "[debug] project_dir=${PROJECT_DIR}"

# TEST
#validate_project $PROJECT_DIR;

ex_validate_project "$PROJECT_DIR"
###

# Split PROJECT_DIR into components
#IFS='/' read -r -a components <<< "$PROJECT_DIR"

# Find the index of 'REP'
#REP_INDEX=-1
#for i in "${!components[@]}"; do
#  if [ "${components[i]}" = "REP" ]; then
#    REP_INDEX=$i
#    break
#  fi
#done

#if [ $REP_INDEX -ne -1 ]; then
  # Extract project name, type, and target from PROJECT_DIR
#  P_NAME=$(basename "$PROJECT_DIR" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/_/g')
#  P_TARGET=${components[REP_INDEX + 1]}
#  P_TYPE=${components[REP_INDEX + 2]}

#  echo "...segue check_project_type..."
#  if ! check_project_type "$P_TYPE"; then
#    exit 1
#  fi

  # Format P_NAME to replace '-' with '_'
#  P_NAME=${P_NAME//-/_}

#  echo "Project Folder : $PROJECT_DIR"
#  echo "Project Name   : $P_NAME"
#  echo "Project Type   : $P_TYPE"	# Project Language...
#  echo "Project Target : $P_TARGET"
#else
#  echo "ERROR: 'REP' directory not found in path [ $PROJECT_DIR ]"
#  exit 1
#fi

###

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

DOCKER_RUN_EXTRA_ARGS="${DOCKER_RUN_EXTRA_ARGS:-"--rm -it"}"

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

# check Project type
#
#echo "project type=<$P_TYPE>"
#if [[ "$P_TYPE" != "Python" ]]; then
#  echo "[init] Can manage Python projects only."
#  exit 1
#fi

echo "[init] ${P_TYPE} project found..."

command -v docker >/dev/null 2>&1 || { echo "Errore: 'docker' non trovato nel PATH dell'host."; exit 1; }
echo "docker found..."

#command -v uv >/dev/null 2>&1 || { echo "Errore: 'uv' non trovato nel PATH dell'host."; exit 1; }
#echo "uv found..."

echo "WARNING: COPIO DIRETTAMENTE Dockerfile.Python..."

#DOCKERFILE=~/.local/share/docker-dev/Dockerfile.$P_TYPE
DOCKERFILE=Dockerfile.$P_TYPE
if [[ -f $DOCKERFILE ]]; then
  #echo "$DOCKERFILE --> ok"
  #echo "copio in $PROJECT_DIR ..."
  cp $DOCKERFILE $PROJECT_DIR/
  DOCKERFILE="$PROJECT_DIR/Dockerfile.${P_TYPE}" ### !!!
  echo "...Dockerfile --> $DOCKERFILE"
fi

echo "WARNING: COPIO DIRETTAMENTE entrypoint.sh..."
#ENTRYPOINT=~/.local/share/docker-dev/entrypoint.sh
ENTRYPOINT=entrypoint.Python.sh
if [[ -f $ENTRYPOINT ]]; then
  #echo "$ENTRYPOINT --> ok"
  cp $ENTRYPOINT $PROJECT_DIR/
  ENTRYPOINT="$PROJECT_DIR/entrypoint.${P_TYPE}.sh"
  echo "...entrypoint --> $ENTRYPOINT"
fi

cd "$PROJECT_DIR"

# ---- Step 3.1: create (if not exist) venv volume and make it writable by UID/GID
#
echo "[init] Activate docker volume ${VOLUME_NAME}"
docker volume create "${VOLUME_NAME}" >/dev/null
docker run --rm \
	-v "${VOLUME_NAME}:${APP_DIR_IN_CONTAINER}" \
	alpine:3.20 \
	sh -c "mkdir -p ${APP_DIR_IN_CONTAINER} && chown -R ${UID_}:${GID_} ${APP_DIR_IN_CONTAINER}" >/dev/null

# ---- Step 3.2: create (if not exist) uv-python volume iand make it writable by UID/GID
#
echo "[init] Activate docker volume uv-python"
docker volume create uv-python >/dev/null
docker run --rm \
	-v uv-python:/uvpy \
	alpine:3.20 \
       	sh -c "chown $UID_:$GID_ /uvpy" # change from ash to sh

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
#
if docker ps -a --format '{{.Names}}' | grep -qx "${CONTAINER_NAME}"; then
  echo "[init] Rimuovo container esistente: ${CONTAINER_NAME}"
  docker rm -f "${CONTAINER_NAME}" >/dev/null
fi

echo "[init] Avvio container: ${CONTAINER_NAME}"

# NOTA: ${DOCKER_RUN_EXTRA_ARGS} senza "" evita espansione in ' ' se vuoto
# debug
# set -x
if [ "${#CONTAINER_CMD[@]}" -gt 0 ]; then
  echo "[init] run container with arguments: < $ONE_LINE_CONTAINER_CMD>"
  docker run ${DOCKER_RUN_EXTRA_ARGS} \
    --name "${CONTAINER_NAME}" \
    -v "${PROJECT_DIR}:${APP_DIR_IN_CONTAINER}" \
    -v "${VOLUME_NAME}:${VENV_DIR_IN_CONTAINER}" \
    -v "uv-python:/home/${HOSTUSER}/.local/share/uv/python" \
    "${IMAGE_NAME}" \
    "${CONTAINER_CMD[@]}"
else
  docker run ${DOCKER_RUN_EXTRA_ARGS} \
    --name "${CONTAINER_NAME}" \
    -v "${PROJECT_DIR}:${APP_DIR_IN_CONTAINER}" \
    -v "${VOLUME_NAME}:${VENV_DIR_IN_CONTAINER}" \
    -v "uv-python:/home/${HOSTUSER}/.local/share/uv/python" \
    "${IMAGE_NAME}"
fi

exit 0
