#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source "${SCRIPT_DIR}/docker-dev-cli.sh"

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

ddev_set_explicit_project_identity() {
    local project_dir="$1"
    local model="$2"
    local repo_root
    local repo_relative

    P_NAME="$(basename -- "$project_dir" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/_/g')"
    P_NAME="${P_NAME//-/_}"
    P_MODEL="$model"
    P_TARGET="DEV"

    repo_root="$(readlink -m -- "${ORG}/REP")"
    case "$project_dir" in
        "${repo_root}/"*)
            repo_relative="${project_dir#"${repo_root}"/}"
            if [[ "$repo_relative" == */* ]]; then
                P_TARGET="${repo_relative%%/*}"
            fi
            ;;
    esac

    IMAGE_NAME="${IMAGE_NAME:-${P_TARGET}.${P_MODEL}}"
    IMAGE_NAME="${IMAGE_NAME,,}"
    CONTAINER_NAME="${IMAGE_NAME}.${P_NAME}"
}

  ddev_run_tag_command() {
    local project_base
    local target_dir

    ORG="${ORG:-$HOME}"
    BASE="$(readlink -m -- "${ORG}/REP")"
    project_base="$(readlink -m -- "${BASE}/DEV")"

    if [[ -z "$DDEV_TARGET" ]]; then
      target_dir="$(readlink -m -- "$PWD")"
    elif [[ "$DDEV_TARGET" == /* ]]; then
      target_dir="$(readlink -m -- "$DDEV_TARGET")"
    else
      if ! ddev_cli_validate_relative_target "$DDEV_TARGET"; then
        echo "[tag] ERROR: $DDEV_RESOLVE_ERROR" >&2
        return 2
      fi
      target_dir="$(readlink -m -- "${PWD}/${DDEV_TARGET}")"
    fi

    if [[ ! -d "$target_dir" || ! -r "$target_dir" || ! -w "$target_dir" ]]; then
      echo "[tag] ERROR: target must be an existing readable and writable directory: $target_dir" >&2
      return 1
    fi
    if ! ddev_path_is_within "$target_dir" "$project_base"; then
      echo "[tag] ERROR: instance directory must be under project base: $project_base" >&2
      return 1
    fi
    if ! ddev_write_instance_tag "$target_dir" "$DDEV_MODEL" "$SCRIPT_DIR"; then
      echo "[tag] ERROR: $DDEV_RESOLVE_ERROR" >&2
      return 1
    fi

    printf '[tag] Instance model %s recorded in %s/.docker-dev/instance-tag\n' \
      "$DDEV_MODEL" "$target_dir"
  }

  ddev_run_info_command() {
    local project_base
    local project_dir
    local project_tag_file
    local project_model="absent"

    ORG="${ORG:-$HOME}"
    BASE="$(readlink -m -- "${ORG}/REP")"
    project_base="$(readlink -m -- "${BASE}/DEV")"
    project_dir="$(readlink -m -- "$PWD")"
    project_tag_file="${project_dir}/.docker-dev/project-tag"

    printf 'Project directory: %s\n' "$project_dir"
    if [[ -e "$project_tag_file" || -L "$project_tag_file" ]]; then
      if ! ddev_read_project_tag "$project_dir" "$SCRIPT_DIR"; then
        printf 'Project tag: invalid (%s)\n' "$DDEV_RESOLVE_ERROR" >&2
        return 1
      fi
      project_model="$DDEV_TAG_MODEL"
      printf 'Project tag: %s (%s)\n' "$project_model" "$project_tag_file"
    else
      printf 'Project tag: absent\n'
    fi

    if ! ddev_resolve_instance_context "$SCRIPT_DIR" "$project_base" "$project_dir"; then
      printf 'Instance tag: invalid (%s)\n' "$DDEV_RESOLVE_ERROR" >&2
      return 1
    fi
    if [[ "$DDEV_INSTANCE_SOURCE" == instance-tag ]]; then
      printf 'Instance tag: %s (%s/.docker-dev/instance-tag)\n' \
        "$DDEV_INSTANCE_MODEL" "$DDEV_INSTANCE_DIR"
    elif [[ "$DDEV_INSTANCE_SOURCE" == legacy-root ]]; then
      printf 'Instance tag: absent; legacy model root: %s\n' "$DDEV_INSTANCE_MODEL"
    else
      printf 'Instance tag: absent\n'
    fi

    if ! ddev_resolve_project_model "$SCRIPT_DIR" "$project_base" "$project_dir" "" 1; then
      printf 'Effective model: unavailable (%s)\n' "$DDEV_RESOLVE_ERROR" >&2
      return 1
    fi
    printf 'Effective model: %s (%s)\n' "$DDEV_PROJECT_MODEL" "$DDEV_MODEL_SOURCE"
  }

ddev_run_explicit_command() {
    local operation="$DDEV_OPERATION"
    local project_base
    local resolver_status=0
    local apply_templates="${SCRIPT_DIR}/apply-templates.sh"

    ORG="${ORG:-$HOME}"
    BASE="${ORG}/REP"
    project_base="${BASE}/DEV"

    if [[ "$operation" == build ]]; then
        if [[ -n "$DDEV_TARGET" && "$DDEV_TARGET" != /* ]]; then
            if ! ddev_cli_validate_relative_target "$DDEV_TARGET"; then
                echo "[build] ERROR: $DDEV_RESOLVE_ERROR" >&2
                return 2
            fi
        fi
        if ! ddev_resolve_build_project "$SCRIPT_DIR" "$project_base" "$DDEV_MODEL" "$DDEV_TARGET"; then
            echo "[build] ERROR: $DDEV_RESOLVE_ERROR" >&2
            return 1
        fi
    else
        ddev_resolve_run_project "$SCRIPT_DIR" "$project_base" "$DDEV_TARGET" || resolver_status=$?
        if [[ "$resolver_status" -ne 0 ]]; then
            if [[ "$resolver_status" -eq 2 ]]; then
                printf '[run] ERROR: %s\n' "$DDEV_RESOLVE_ERROR" >&2
                return 2
            fi
            printf '[run] ERROR: %s\n' "$DDEV_RESOLVE_ERROR" >&2
            return 1
        fi
    fi

    PROJECT_DIR="$DDEV_PROJECT_DIR"
    P_MODEL="$DDEV_PROJECT_MODEL"
    ddev_set_explicit_project_identity "$PROJECT_DIR" "$P_MODEL"

    echo "Project Folder : $PROJECT_DIR"
    echo "Project Model  : $P_MODEL"
    echo "Project Target : $P_TARGET"
    echo "Image Name     : $IMAGE_NAME"
    echo "Container Name : $CONTAINER_NAME"

    if ! check_docker; then
        return 1
    fi

    if [[ "$operation" == run ]]; then
        if ! docker inspect --type=image "$IMAGE_NAME" >/dev/null 2>&1; then
            echo "[run] ERROR: image '$IMAGE_NAME' is not available locally." >&2
            printf '[run] Build it first with: docker-dev build --model %q --target %q\n' \
                "$P_MODEL" "$PROJECT_DIR" >&2
            return 1
        fi
    fi

    if [[ "$operation" == build ]]; then
        if [[ "$DDEV_ASSUME_YES" -ne 1 ]] && ! ask_to_proceed; then
            echo "Exiting..."
            return 1
        fi
        if [[ ! -f "$apply_templates" ]]; then
            echo "[build] ERROR: apply-templates.sh not found: $apply_templates" >&2
            return 1
        fi
        if ! mkdir -p -- "$PROJECT_DIR"; then
            echo "[build] ERROR: cannot create project directory: $PROJECT_DIR" >&2
            return 1
        fi

        if ! "$apply_templates" "$PROJECT_DIR" "$P_MODEL"; then
            echo "[build] ERROR: template application failed for: $PROJECT_DIR" >&2
            return 1
        fi
        if ! cd "$PROJECT_DIR"; then
            echo "[build] ERROR: cannot enter project directory: $PROJECT_DIR" >&2
            return 1
        fi
        if ! ddev_run_model_operation \
            "$SCRIPT_DIR" "$PROJECT_DIR" "$P_MODEL" "$IMAGE_NAME" "$CONTAINER_NAME" build; then
            echo "[build] ERROR: ${DDEV_RESOLVE_ERROR:-model setup/build failed}" >&2
            return 1
        fi
        if ! ddev_write_project_tag "$PROJECT_DIR" "$P_MODEL" "$SCRIPT_DIR"; then
            echo "[build] ERROR: $DDEV_RESOLVE_ERROR" >&2
            return 1
        fi
        echo "[build] Project tag written: ${PROJECT_DIR}/.docker-dev/project-tag"

        if [[ "$DDEV_BUILD_AND_RUN" -eq 1 ]]; then
            if ! ddev_run_model_operation \
                "$SCRIPT_DIR" "$PROJECT_DIR" "$P_MODEL" "$IMAGE_NAME" "$CONTAINER_NAME" run-only; then
                echo "[run] ERROR: ${DDEV_RESOLVE_ERROR:-model run failed}" >&2
                return 1
            fi
        fi
        return 0
    fi

    if ! ask_to_proceed; then
        echo "Exiting..."
        return 1
    fi
    if ! cd "$PROJECT_DIR"; then
        echo "[run] ERROR: cannot enter project directory: $PROJECT_DIR" >&2
        return 1
    fi
    if ! ddev_run_model_operation \
        "$SCRIPT_DIR" "$PROJECT_DIR" "$P_MODEL" "$IMAGE_NAME" "$CONTAINER_NAME" run; then
        echo "[run] ERROR: ${DDEV_RESOLVE_ERROR:-model run failed}" >&2
        return 1
    fi
}

##################################################################################################

if ! ddev_cli_parse "$@"; then
    printf '[cli] ERROR: %s\n' "$DDEV_PARSE_ERROR" >&2
    case "$DDEV_OPERATION" in
        build) ddev_cli_build_usage >&2 ;;
        run) ddev_cli_run_usage >&2 ;;
        tag) ddev_cli_tag_usage >&2 ;;
        info) ddev_cli_info_usage >&2 ;;
        *) ddev_cli_usage >&2 ;;
    esac
    exit 2
fi

if [[ "$DDEV_SHOW_HELP" -eq 1 ]]; then
    case "$DDEV_OPERATION" in
        build) ddev_cli_build_usage ;;
        run) ddev_cli_run_usage ;;
        tag) ddev_cli_tag_usage ;;
        info) ddev_cli_info_usage ;;
        *) ddev_cli_usage ;;
    esac
    exit 0
fi

case "$DDEV_OPERATION" in
    tag)
        ddev_run_tag_command || exit $?
        ;;
    info)
        ddev_run_info_command || exit $?
        ;;
    *)
        ddev_run_explicit_command || exit $?
        ;;
esac
