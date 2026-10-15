#!/usr/bin/env bash
#
# v0.9
#
# --target=<Lang>/path/to/project es.: --target="Python/path/to/project"
# oppure:
# path assoluto a progetto esistente (con permessi utente rw)
# --target="/home/user/REP/DEV/Python/baz"
#
# vedi:
# split PROJECT_DIR in project_identity()
# MANAGED_MODELS in project_setup()

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source "${SCRIPT_DIR}/docker-run-extra-args.sh"

usage() {
  echo "Usage: $0 --target=<Type>/<name> [--penv=ENV] [-i IMAGE_NAME] [-o] [-- command...]"
  echo "  --target  Project dir: relative <Type>/<name> under \$BASE or absolute existing path"
  echo "  --penv    Project environment subdir (default: DEV)"
  echo "  -i        Specify the docker image name"
  echo "  -o        Overwrite existing template files in the project folder"
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

check_docker() {
    local tag="[check_docker]"
    local docker_error

    if ! command -v docker >/dev/null 2>&1; then
        echo "$tag ERRORE: 'docker' non trovato nel PATH di WSL." >&2
        return 1
    fi

    if docker_error=$(docker info 2>&1); then
        echo "$tag Docker Desktop è avviato e raggiungibile."
        return 0
    fi

    echo "$tag ERRORE: Docker daemon non raggiungibile." >&2
    echo "$tag Dettaglio:" >&2
    printf '%s\n' "$docker_error" >&2
    echo >&2
    echo "$tag Possibili cause:" >&2
    echo "$tag - Docker Desktop non è stato avviato su Windows." >&2
    echo "$tag - L'integrazione WSL 2 non è abilitata per questa distribuzione." >&2
    echo "$tag - Il contesto Docker selezionato non è quello corretto." >&2

    return 1
}

run_lang_pipeline() {
    local script_dir="$1"
    local project_dir="$2"
    local p_type="$3"
    local image_name="$4"
    local container_name="$5"
    shift 5

    local container_cmd=("$@")
    local lang_root
    local bin_dir
    local script
    local scripts_found=0

    bin_dir="${script_dir}/langs/${p_type}/bin"

    if [[ ! -d "$bin_dir" ]]; then
        echo "[pipeline] ERROR: Missing /bin folder: $bin_dir" >&2
        return 1
    fi

    # Globbing disabilitato temporaneamente: se non esistono corrispondenze,
    # il pattern resta letterale e può essere gestito esplicitamente.
    local -a pipeline_scripts=()
    while IFS= read -r -d '' script; do
        pipeline_scripts+=("$script")
    done < <(
        find "$bin_dir" -maxdepth 1 -type f \
            -regextype posix-extended \
            -regex '.*/[0-9]+\..*\.sh' \
            -print0 \
        | sort -z -V
    )

    if [[ "${#pipeline_scripts[@]}" -eq 0 ]]; then
        echo "[pipeline] ERRORE: nessuno script pipeline trovato in: $bin_dir" >&2
        return 1
    fi

    scripts_found=1


    for script in "${pipeline_scripts[@]}"; do

        if [[ ! -x "$script" ]]; then
            echo "[pipeline] ERRORE: script non eseguibile: $script" >&2
            echo "[pipeline] Eseguire: chmod +x -- '$script'" >&2
            return 1
        fi

        echo "[pipeline] Eseguo: $(basename -- "$script")"

	"$script" \
            "$project_dir" \
            "$image_name" \
            "$container_name" \
            "${container_cmd[@]}"
    done

    (( scripts_found == 1 ))
}

project_identity() {
  # 
  # Split PROJECT_DIR into components &
  # Extract project name, type, and target into P_NAME, P_TARGET, P_TYPE
  # es.: PROJECT_DIR=/home/user/REP/DEV/Python/foo' -> P_NAME=foo, P_TARGET=DEV, P_TYPE=Python

  local __PROJECT_DIR="$1"
  _tag="[project_identity]"

  # Split PROJECT_DIR into components
  IFS='/' read -r -a components <<< "$__PROJECT_DIR"
  c_size=${#components[@]}
  #echo "$_tag [debug] c_size=${c_size}"

  # Find the index of 'REP'
  REP_INDEX=-1
  for i in "${!components[@]}"; do
    if [ "${components[i]}" = "REP" ]; then
      REP_INDEX=$i
      break
    fi
  done
  #echo "$_tag [debug] TODO: check if if REP index <${REP_INDEX}> is last index!"

  if [ $REP_INDEX -ne -1 ]; then
    # Extract project name, type, and target from PROJECT_DIR
    P_NAME=$(basename "$__PROJECT_DIR" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/_/g')
    P_TARGET=${components[REP_INDEX + 1]}
    P_TYPE=${components[REP_INDEX + 2]}

    # Format P_NAME to replace '-' with '_'
    P_NAME=${P_NAME//-/_}

    echo "Project Folder : $__PROJECT_DIR"
    echo "Project Name   : $P_NAME"
    echo "Project Type   : $P_TYPE"	# Project Language...
    echo "Project Target : $P_TARGET"
    return 0
  else
    echo "ERROR: 'REP' directory not found in path [ $PROJECT_DIR ]"
    #exit 1
    return 1
  fi
}

validate_org() {
  #
  # 
  #
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
}

is_valid() {
  
    local _tag="[is_valid]"
    local input="$1"

    # 1: Only allow a-zA-Z0-9-_+/. characters
    if [[ ! "$input" =~ ^[a-zA-Z0-9._+/-]+$ ]]; then
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

    # input contiene almeno 2 elementi separati da '/'
    #
    return 0
}

check_dir() {
  local _tag="[check_dir]"
  local _dir="$1"
  if [[ ! -d "$_dir" ]]; then
    # Invalid path
    return 1
  fi
  if [[ ! -w "$_dir" ]] || [[ ! -r "$_dir" ]]; then
    echo "$_tag WARNING: Current user does not have read/write permission to $_dir"
    return 1
  fi
  return 0
}

project_setup() {

  local _tag="[project_setup]"

  local _full_target="$1"
  IFS=/ read -r -a components <<< "$_full_target"
  local _p_type="${components[0]}"
  local _p_target_folder="${_full_target#*/}"

  BASE="$BASE/$2"   # aggiorna $BASE con il valore dell'argomento --penv ($2)

  echo "ORG : $ORG"
  echo "BASE: $BASE"

  mapfile -t MANAGED_MODELS < <(
    for _dir in "$SCRIPT_DIR/langs" "$SCRIPT_DIR/services" "$SCRIPT_DIR/stacks"; do
      [[ -d "$_dir" ]] || continue
      find "$_dir" -maxdepth 1 -mindepth 1 -type d -printf '%f\n'
    done | sort
  )
  local _MODELS=$(IFS=", "; echo "${MANAGED_MODELS[*]}")
  
  echo "Managed Models :"  ### debug only
  echo "    << $_MODELS >>"

  _resolved="$(readlink -m -- "$1")"

  if [[ -d "$_resolved" ]]; then
    #
    # --target= PATH assoluto
    #
    if [[ -r "$_resolved" ]] && [[ -w "$_resolved" ]]; then
      
      # permiessi rw -> PATH assoluto AMMESSO
      #
      PROJECT_DIR="$_resolved"
      echo "$_tag PATH assoluto a progetto esistente: <$PROJECT_DIR>"

    else
      echo "$_tag missing rw permission on $_resolved"
      return 1
    fi

  else

    # --target=<Lang>/path/to/project
    #
    if ! is_managed_project_type "$_p_type"; then
      echo "$_tag WARNING: Unknow Model $_p_type" >&2
      echo "$_tag Select one of the following:"
      echo "$_tag $_MODELS"
      return 1
    fi

    if is_absolute "_full_target"; then
      echo "$_tag cannot create new absolute path $1"
      echo "$_tag use relative path instead"
      return 1
    fi

    if ! is_valid "_full_target"; then
      echo "$_tag $1 is NOT valid"
      return 1
    fi

    if ! create_relative_folder "$_p_type" "$_p_target_folder"; then
      echo "$_tag Error creating $1" >&2
      return 1
    fi
  fi

  if ! project_identity "$PROJECT_DIR"; then
    return 1
  fi

}

create_relative_folder() {

  # _p_type      : e' un project type ammesso (es.: Python)
  # _p_target_folder    : e' il project name (es.: foo se --target='Python/foo')
  #
  local _p_type="$1"
  local _p_target_folder="$2"

  if [ -n "$_p_target_folder" ]; then
    if [ ! -d "$(readlink -f "$BASE/$_p_type/$_p_target_folder")" ]; then  # mkdir only if not exist
      echo "$_tag mkdir -p $BASE/$_p_type/$_p_target_folder"
      mkdir -p "$BASE/$_p_type/$_p_target_folder"
    else
      echo "$_tag directory already exist"
    fi
    PROJECT_DIR="$BASE/$_p_type/$_p_target_folder"
  else
    echo "$_tag ERROR: Missing project Name!"
    return 1
  fi

  return 0
}

is_absolute() {
  local _tag="[is_absolute]"
  if [[ "$1" =~ ^/ ]]; then
    # absolute path
    return 0
  fi
    # relative path 
    return 1
}

is_managed_project_type() {
  
  # -> is_managed_model()
  # MANAGED_MODELS definita in project_setup()
  #
  local p_type="$1"

  for t in "${MANAGED_MODELS[@]}"; do
    if [[ "$t" == "$p_type" ]]; then
      return 0
    fi
  done

  return 1
}

##################################################################################################

echo "Welcome to docker-dev"

##################################################################################################
validate_org;

_target=""
_prj_env="DEV"
_remaining_args=()

for arg in "$@"; do
    case "$arg" in
        --target=*)
            _target="${arg#--target=}";;
        --penv=*)
            _prj_env="${arg#--penv=}";;
        --help)
            usage;;
        *)
            _remaining_args+=("$arg");;
    esac
done

check_docker;

if [[ -z "$_target" ]]; then
    _target="$(pwd)"
    echo "[init] DEBUG: missing --target argument, fallback to current directory <$_target>"
fi

if ! project_setup "$_target" "$_prj_env"; then
    echo "project_setup() FAIL" >&2
    exit 1
fi

# Sostituisce gli argomenti originali con quelli rimasti:
# -i, -h e argomenti posizionali
#
set -- "${_remaining_args[@]}"

OPTIND=1
OVERWRITE=0

while getopts ":i:oh" opt; do
    case "$opt" in
        i)
            IMAGE_NAME="$OPTARG";;
        o)
            OVERWRITE=1;;
        h)
            usage;;
        :)
            echo "opzione -$OPTARG richiede un argomento" >&2
            usage;;
        \?)
            echo "opzione non valida: -$OPTARG" >&2
            usage;;
    esac
done

shift $((OPTIND - 1))

CONTAINER_CMD=("$@")
ONE_LINE_CONTAINER_CMD=$(printf "%s " "${CONTAINER_CMD[@]}")
#echo "NON-Options arguments (container command): $ONE_LINE_CONTAINER_CMD"

TZ="${TZ:-Europe/Rome}"
USER_="${USER_:-$(id -un)}"
UID_="${UID_:-$(id -u)}"
GID_="${GID_:-$(id -g)}"

# Naming:
# - IMAGE_NAME gia' impostata (opzione -i oppure export) -> mantenuta
# - altrimenti                                            -> ${P_TARGET}.${P_TYPE}
# IMAGE_NAME viene comunque lowercased (docker repo names reject uppercase)
# e CONTAINER_NAME e' sempre derivata da essa.
# VOLUME_NAME resta a carico dei langs/*/bin scripts:
# prefisso di linguaggio + CONTAINER_NAME (override one-off via env).
#
IMAGE_NAME="${IMAGE_NAME:-${P_TARGET}.${P_TYPE}}"
IMAGE_NAME="${IMAGE_NAME,,}"
CONTAINER_NAME="${IMAGE_NAME}.${P_NAME}"

echo "Image Name     : $IMAGE_NAME"
echo "Container Name : $CONTAINER_NAME"

# NOTA:
# semplifico usando sempre /app al posto di $P_NAME (run manuali dei containers + uniformi)
#
APP_DIR_IN_CONTAINER="/app" 

docker_run_extra_args "$PROJECT_DIR"

echo "TZ                    : $TZ"
echo "USER                  : $USER_"
echo "UID                   : $UID_"
echo "GID                   : $GID_"
echo
echo "DOCKER_RUN_EXTRA_ARGS : $DOCKER_RUN_EXTRA_ARGS"
echo "CONTAINER_CMD         : $ONE_LINE_CONTAINER_CMD"

if ! ask_to_proceed; then
  echo "Exiting..."
  exit 1
fi

echo "[main] script_dir=$SCRIPT_DIR"
APPLY_TEMPLATES="${SCRIPT_DIR}/apply-templates.sh"

if [[ ! -f "$APPLY_TEMPLATES" ]]; then
    echo "[init] ERRORE: apply-templates.sh non trovato: $APPLY_TEMPLATES" >&2
    exit 1
fi

if [[ "$OVERWRITE" -eq 1 ]]; then
    "$APPLY_TEMPLATES" -o "$PROJECT_DIR" "$P_TYPE"
else
    "$APPLY_TEMPLATES" "$PROJECT_DIR" "$P_TYPE"
fi

cd "$PROJECT_DIR"

run_lang_pipeline \
    "$SCRIPT_DIR" \
    "$PROJECT_DIR" \
    "$P_TYPE" \
    "$IMAGE_NAME" \
    "$CONTAINER_NAME" \
    "${CONTAINER_CMD[@]}"

exit 0 
