#!/usr/bin/env bash

ddev_cli_usage() {
    cat <<'USAGE'
Usage:
  docker-dev build --model <model> [--target <target>] [-x] [-y]
  docker-dev run [--target <target>]

Commands:
  build  Prepare and build a project; -x also requests a run.
  run    Run a project without an implicit build.

Options:
  --model <model>   Required by build. May be in langs/, services/, or stacks/.
  --lang <lang>     Legacy alias for --model.
  --target <target> Project target.
  -x                Also run after build.
  -y                Skip the build confirmation prompt.
  -h, --help        Show this help.
USAGE
}

ddev_cli_build_usage() {
    cat <<'USAGE'
Usage: docker-dev build --model <model> [--target <target>] [-x] [-y]
USAGE
}

ddev_cli_run_usage() {
    cat <<'USAGE'
Usage: docker-dev run [--target <target>]
USAGE
}

ddev_cli_parse() {
    DDEV_OPERATION=legacy
    DDEV_MODEL=""
    DDEV_TARGET=""
    DDEV_BUILD_AND_RUN=0
    DDEV_ASSUME_YES=0
    DDEV_SHOW_HELP=0
    DDEV_PARSE_ERROR=""

    case "${1-}" in
        build|run)
            DDEV_OPERATION="$1"
            shift
            ;;
        *)
            return 0
            ;;
    esac

    while (($#)); do
        case "$1" in
            -h|--help)
                DDEV_SHOW_HELP=1
                shift
                ;;
            --model|--lang)
                if [[ "$DDEV_OPERATION" != build ]]; then
                    DDEV_PARSE_ERROR="--model is only valid with build"
                    return 2
                fi
                if (($# < 2)) || [[ -z "$2" ]]; then
                    DDEV_PARSE_ERROR="--model requires a non-empty value"
                    return 2
                fi
                if [[ -n "$DDEV_MODEL" ]]; then
                    DDEV_PARSE_ERROR="--model may be specified only once"
                    return 2
                fi
                DDEV_MODEL="$2"
                shift 2
                ;;
            --model=*|--lang=*)
                if [[ "$DDEV_OPERATION" != build ]]; then
                    DDEV_PARSE_ERROR="--model is only valid with build"
                    return 2
                fi
                local model_value="${1#*=}"
                if [[ -z "$model_value" ]]; then
                    DDEV_PARSE_ERROR="--model requires a non-empty value"
                    return 2
                fi
                if [[ -n "$DDEV_MODEL" ]]; then
                    DDEV_PARSE_ERROR="--model may be specified only once"
                    return 2
                fi
                DDEV_MODEL="$model_value"
                shift
                ;;
            --target)
                if (($# < 2)) || [[ -z "$2" ]]; then
                    DDEV_PARSE_ERROR="--target requires a non-empty value"
                    return 2
                fi
                if [[ -n "$DDEV_TARGET" ]]; then
                    DDEV_PARSE_ERROR="--target may be specified only once"
                    return 2
                fi
                DDEV_TARGET="$2"
                shift 2
                ;;
            --target=*)
                if [[ -z "${1#--target=}" ]]; then
                    DDEV_PARSE_ERROR="--target requires a non-empty value"
                    return 2
                fi
                if [[ -n "$DDEV_TARGET" ]]; then
                    DDEV_PARSE_ERROR="--target may be specified only once"
                    return 2
                fi
                DDEV_TARGET="${1#--target=}"
                shift
                ;;
            -x)
                if [[ "$DDEV_OPERATION" != build ]]; then
                    DDEV_PARSE_ERROR="-x is only valid with build"
                    return 2
                fi
                DDEV_BUILD_AND_RUN=1
                shift
                ;;
            -y)
                if [[ "$DDEV_OPERATION" != build ]]; then
                    DDEV_PARSE_ERROR="-y is only valid with build"
                    return 2
                fi
                DDEV_ASSUME_YES=1
                shift
                ;;
            *)
                DDEV_PARSE_ERROR="unknown argument for $DDEV_OPERATION: $1"
                return 2
                ;;
        esac
    done

    if [[ "$DDEV_OPERATION" == build && "$DDEV_SHOW_HELP" -eq 0 && -z "$DDEV_MODEL" ]]; then
        DDEV_PARSE_ERROR="build requires --model"
        return 2
    fi
}

ddev_cli_load_models() {
    local script_dir="$1"
    local model_root
    local model
    local -A seen=()

    DDEV_MODELS=()
    for model_root in langs services stacks; do
        model_root="${script_dir}/${model_root}"
        [[ -d "$model_root" ]] || continue
        while IFS= read -r model; do
            [[ -n "$model" ]] && seen["$model"]=1
        done < <(find "$model_root" -mindepth 1 -maxdepth 1 -type d -printf '%f\n')
    done
    if ((${#seen[@]})); then
        mapfile -t DDEV_MODELS < <(printf '%s\n' "${!seen[@]}" | sort)
    fi
    if ((${#DDEV_MODELS[@]} == 0)); then
        DDEV_RESOLVE_ERROR="no managed models found under langs/, services/, or stacks/ in: $script_dir"
        return 1
    fi
}

ddev_cli_find_model_dir() {
    local script_dir="$1"
    local model="$2"
    local model_root
    local candidate
    local -a matches=()

    DDEV_MODEL_DIR=""
    DDEV_RESOLVE_ERROR=""
    if [[ ! "$model" =~ ^[A-Za-z0-9_-]+$ ]]; then
        DDEV_RESOLVE_ERROR="invalid model name: $model"
        return 1
    fi
    for model_root in langs services stacks; do
        candidate="${script_dir}/${model_root}/${model}"
        [[ -d "$candidate" ]] && matches+=("$candidate")
    done
    if ((${#matches[@]} == 0)); then
        DDEV_RESOLVE_ERROR="unknown or unmanaged model: $model"
        return 1
    fi
    if ((${#matches[@]} > 1)); then
        DDEV_RESOLVE_ERROR="ambiguous model '$model' exists in multiple model roots: ${matches[*]}"
        return 1
    fi
    DDEV_MODEL_DIR="${matches[0]}"
}

ddev_cli_is_managed_model() {
    ddev_cli_find_model_dir "$1" "$2"
}

ddev_cli_validate_relative_target() {
    local target="$1"
    local component
    local -a components=()

    if [[ -z "$target" || "$target" == /* || ! "$target" =~ ^[A-Za-z0-9._+/-]+$ ]]; then
        DDEV_RESOLVE_ERROR="target must be a non-empty relative path containing only letters, digits, '.', '_', '+', '-', and '/'"
        return 1
    fi

    if [[ "$target" == */ || "$target" == *//* ]]; then
        DDEV_RESOLVE_ERROR="target must not contain empty path components: $target"
        return 1
    fi

    IFS='/' read -r -a components <<< "$target"
    for component in "${components[@]}"; do
        if [[ "$component" == "." || "$component" == ".." ]]; then
            DDEV_RESOLVE_ERROR="target must not contain '.' or '..' path components: $target"
            return 1
        fi
    done
}

ddev_resolve_build_project() {
    local script_dir="$1"
    local base="$2"
    local model="$3"
    local target="$4"
    local resolved_base
    local resolved_project

    DDEV_PROJECT_DIR=""
    DDEV_PROJECT_MODEL=""
    DDEV_RESOLVE_ERROR=""

    if ! ddev_cli_is_managed_model "$script_dir" "$model"; then
        return 1
    fi
    if [[ "$base" != /* ]]; then
        DDEV_RESOLVE_ERROR="project base must be an absolute directory: $base"
        return 1
    fi
    resolved_base="$(readlink -m -- "$base")"

    if [[ -z "$target" ]]; then
        resolved_project="$(readlink -m -- "$PWD")"
        if [[ ! -d "$resolved_project" || ! -r "$resolved_project" || ! -w "$resolved_project" ]]; then
            DDEV_RESOLVE_ERROR="current directory must be an existing readable and writable project directory: $resolved_project"
            return 1
        fi
    elif [[ "$target" == /* ]]; then
        resolved_project="$(readlink -m -- "$target")"
        if [[ ! -d "$resolved_project" || ! -r "$resolved_project" || ! -w "$resolved_project" ]]; then
            DDEV_RESOLVE_ERROR="absolute target must be an existing readable and writable directory: $resolved_project"
            return 1
        fi
    else
        if ! ddev_cli_validate_relative_target "$target"; then
            return 1
        fi
        resolved_project="$(readlink -m -- "${resolved_base}/${model}/${target}")"
        case "$resolved_project" in
            "${resolved_base}/${model}/"*) ;;
            *)
                DDEV_RESOLVE_ERROR="target resolves outside the model project directory: $target"
                return 1
                ;;
        esac
    fi

    DDEV_PROJECT_DIR="$resolved_project"
    DDEV_PROJECT_MODEL="$model"
}

ddev_read_project_tag() {
    local project_dir="$1"
    local script_dir="$2"
    local metadata_dir="${project_dir}/.docker-dev"
    local tag_file="${metadata_dir}/project-tag"
    local line
    local schema_version=""
    local model=""
    local legacy_lang=""
    local seen_schema=0
    local seen_model=0
    local seen_legacy_lang=0

    DDEV_TAG_MODEL=""
    DDEV_RESOLVE_ERROR=""

    if [[ -L "$metadata_dir" || ! -d "$metadata_dir" ]]; then
        DDEV_RESOLVE_ERROR="project metadata directory is missing or invalid: $metadata_dir"
        return 1
    fi
    if [[ -L "$tag_file" || ! -f "$tag_file" || ! -r "$tag_file" ]]; then
        DDEV_RESOLVE_ERROR="project tag is missing or is not a readable regular file: $tag_file"
        return 1
    fi

    while IFS= read -r line || [[ -n "$line" ]]; do
        case "$line" in
            schema_version=*)
                if ((seen_schema)); then
                    DDEV_RESOLVE_ERROR="duplicate schema_version in project tag: $tag_file"
                    return 1
                fi
                schema_version="${line#schema_version=}"
                seen_schema=1
                ;;
            model=*)
                if ((seen_model)); then
                    DDEV_RESOLVE_ERROR="duplicate model in project tag: $tag_file"
                    return 1
                fi
                model="${line#model=}"
                seen_model=1
                ;;
            lang=*)
                if ((seen_legacy_lang)); then
                    DDEV_RESOLVE_ERROR="duplicate lang in project tag: $tag_file"
                    return 1
                fi
                legacy_lang="${line#lang=}"
                seen_legacy_lang=1
                ;;
            *)
                DDEV_RESOLVE_ERROR="invalid field in project tag: $tag_file"
                return 1
                ;;
        esac
    done < "$tag_file"

    if ((seen_model && seen_legacy_lang)); then
        DDEV_RESOLVE_ERROR="project tag must not contain both model and legacy lang fields: $tag_file"
        return 1
    fi
    if ((!seen_schema || (!seen_model && !seen_legacy_lang))) || [[ -z "$schema_version" ]]; then
        DDEV_RESOLVE_ERROR="project tag must contain non-empty schema_version and model fields: $tag_file"
        return 1
    fi
    if ((!seen_model)); then
        model="$legacy_lang"
    fi
    if [[ -z "$model" ]]; then
        DDEV_RESOLVE_ERROR="project tag must contain a non-empty model: $tag_file"
        return 1
    fi
    if [[ "$schema_version" != 1 ]]; then
        DDEV_RESOLVE_ERROR="unsupported project tag schema_version '$schema_version': $tag_file"
        return 1
    fi
    if ! ddev_cli_is_managed_model "$script_dir" "$model"; then
        DDEV_RESOLVE_ERROR="project tag refers to ${DDEV_RESOLVE_ERROR}: $tag_file"
        return 1
    fi

    DDEV_TAG_MODEL="$model"
}

ddev_write_project_tag() {
    local project_dir="$1"
    local model="$2"
    local script_dir="$3"
    local metadata_dir="${project_dir}/.docker-dev"
    local tag_file="${metadata_dir}/project-tag"
    local temporary_file

    DDEV_RESOLVE_ERROR=""

    if ! ddev_cli_is_managed_model "$script_dir" "$model"; then
        return 1
    fi
    if [[ ! -d "$project_dir" || ! -w "$project_dir" ]]; then
        DDEV_RESOLVE_ERROR="project directory must exist and be writable: $project_dir"
        return 1
    fi
    if [[ -L "$metadata_dir" || ( -e "$metadata_dir" && ! -d "$metadata_dir" ) ]]; then
        DDEV_RESOLVE_ERROR="project metadata path is not a real directory: $metadata_dir"
        return 1
    fi
    if [[ ! -d "$metadata_dir" ]] && ! mkdir -p -- "$metadata_dir"; then
        DDEV_RESOLVE_ERROR="cannot create project metadata directory: $metadata_dir"
        return 1
    fi
    if [[ -L "$tag_file" || ( -e "$tag_file" && ! -f "$tag_file" ) ]]; then
        DDEV_RESOLVE_ERROR="project tag path is not a regular file: $tag_file"
        return 1
    fi

    if ! temporary_file="$(mktemp -- "${metadata_dir}/.project-tag.XXXXXX")"; then
        DDEV_RESOLVE_ERROR="cannot create temporary project tag in: $metadata_dir"
        return 1
    fi
    if ! printf 'schema_version=1\nmodel=%s\n' "$model" > "$temporary_file"; then
        rm -f -- "$temporary_file"
        DDEV_RESOLVE_ERROR="cannot write temporary project tag in: $metadata_dir"
        return 1
    fi
    if ! mv -f -- "$temporary_file" "$tag_file"; then
        rm -f -- "$temporary_file"
        DDEV_RESOLVE_ERROR="cannot publish project tag: $tag_file"
        return 1
    fi
}

ddev_resolve_run_project() {
    local script_dir="$1"
    local base="$2"
    local target="$3"
    local candidate
    local resolved_base
    local resolved_candidate
    local resolved_pwd
    local local_model=""
    local local_tag_file
    local model

    DDEV_PROJECT_DIR=""
    DDEV_PROJECT_MODEL=""
    DDEV_CANDIDATE_PATHS=()
    DDEV_RESOLVE_ERROR=""
    DDEV_RESOLVE_AMBIGUOUS=0

    if [[ -z "$target" ]]; then
        resolved_candidate="$(readlink -m -- "$PWD")"
        if [[ ! -d "$resolved_candidate" || ! -r "$resolved_candidate" ]]; then
            DDEV_RESOLVE_ERROR="current directory is not a readable project directory: $resolved_candidate"
            return 1
        fi
        if ! ddev_read_project_tag "$resolved_candidate" "$script_dir"; then
            return 1
        fi
        DDEV_PROJECT_DIR="$resolved_candidate"
        DDEV_PROJECT_MODEL="$DDEV_TAG_MODEL"
        return 0
    fi

    if [[ "$target" == /* ]]; then
        resolved_candidate="$(readlink -m -- "$target")"
        if [[ ! -d "$resolved_candidate" || ! -r "$resolved_candidate" ]]; then
            DDEV_RESOLVE_ERROR="absolute target must be an existing readable directory: $resolved_candidate"
            return 1
        fi
        if ! ddev_read_project_tag "$resolved_candidate" "$script_dir"; then
            return 1
        fi
        DDEV_PROJECT_DIR="$resolved_candidate"
        DDEV_PROJECT_MODEL="$DDEV_TAG_MODEL"
        return 0
    fi

    if [[ "$base" != /* || ! -d "$base" ]]; then
        DDEV_RESOLVE_ERROR="project base must be an existing absolute directory: $base"
        return 1
    fi
    if ! ddev_cli_validate_relative_target "$target"; then
        return 1
    fi
    if ! ddev_cli_load_models "$script_dir"; then
        return 1
    fi

    resolved_base="$(readlink -m -- "$base")"
    resolved_pwd="$(readlink -m -- "$PWD")"

    for model in "${DDEV_MODELS[@]}"; do
        case "$resolved_pwd" in
            "${resolved_base}/${model}"|"${resolved_base}/${model}/"*)
                local_model="$model"
                break
                ;;
        esac
    done

    candidate="${resolved_pwd}/${target}"
    if [[ ! -d "$candidate" ]]; then
        DDEV_RESOLVE_ERROR="target '$target' does not exist under the current directory: $candidate"
        return 1
    fi
    resolved_candidate="$(readlink -m -- "$candidate")"
    case "$resolved_candidate" in
        "${resolved_pwd}/"*) ;;
        *)
            DDEV_RESOLVE_ERROR="local target resolves outside the current directory: $candidate"
            return 1
            ;;
    esac
    if [[ ! -r "$resolved_candidate" ]]; then
        DDEV_RESOLVE_ERROR="local target is not a readable directory: $resolved_candidate"
        return 1
    fi

    local_tag_file="${resolved_candidate}/.docker-dev/project-tag"
    if [[ -e "$local_tag_file" || -L "$local_tag_file" ]]; then
        if ! ddev_read_project_tag "$resolved_candidate" "$script_dir"; then
            return 1
        fi
        if [[ -n "$local_model" && "$DDEV_TAG_MODEL" != "$local_model" ]]; then
            DDEV_RESOLVE_ERROR="project tag model '$DDEV_TAG_MODEL' does not match current model directory '$local_model': $resolved_candidate"
            return 1
        fi
        DDEV_PROJECT_MODEL="$DDEV_TAG_MODEL"
    elif [[ -n "$local_model" ]]; then
        if ! ddev_cli_is_managed_model "$script_dir" "$local_model"; then
            return 1
        fi
        DDEV_PROJECT_MODEL="$local_model"
    else
        DDEV_RESOLVE_ERROR="project tag is missing and the model cannot be inferred from the current directory: $local_tag_file"
        return 1
    fi

    DDEV_PROJECT_DIR="$resolved_candidate"
}

ddev_run_model_operation() {
    local script_dir="$1"
    local project_dir="$2"
    local model="$3"
    local image_name="$4"
    local container_name="$5"
    local operation="$6"
    shift 6

    local bin_dir
    local script
    local filename
    local phase
    local index
    local found_build=0
    local found_run=0
    local -a scripts=()
    local -a phases=()
    local -a requested_phases=()
    local -a container_cmd=("$@")

    DDEV_RESOLVE_ERROR=""
    if ! ddev_cli_find_model_dir "$script_dir" "$model"; then
        return 1
    fi
    bin_dir="${DDEV_MODEL_DIR}/bin"

    case "$operation" in
        build) requested_phases=(setup build) ;;
        run) requested_phases=(setup run) ;;
        run-only) requested_phases=(run) ;;
        *)
            DDEV_RESOLVE_ERROR="unknown model operation: $operation"
            return 1
            ;;
    esac

    if [[ ! -d "$bin_dir" ]]; then
        DDEV_RESOLVE_ERROR="model pipeline directory not found: $bin_dir"
        return 1
    fi

    while IFS= read -r -d '' script; do
        scripts+=("$script")
    done < <(
        find "$bin_dir" -maxdepth 1 -type f \
            -regextype posix-extended \
            -regex '.*/[0-9]+\..*\.sh' \
            -print0 \
        | sort -z -V
    )

    if ((${#scripts[@]} == 0)); then
        DDEV_RESOLVE_ERROR="no numbered pipeline scripts found in: $bin_dir"
        return 1
    fi

    for script in "${scripts[@]}"; do
        filename="${script##*/}"
        filename="${filename,,}"
        case "$filename" in
            *setup*|*volume*) phase=setup ;;
            *build*) phase=build ;;
            *run*) phase=run ;;
            *)
                DDEV_RESOLVE_ERROR="cannot classify pipeline script '$script' as setup, build, or run"
                return 1
                ;;
        esac
        phases+=("$phase")
        if [[ "$phase" == build ]]; then
            found_build=1
        elif [[ "$phase" == run ]]; then
            found_run=1
        fi
    done

    if [[ "$operation" == build ]]; then
        if [[ "$found_build" -eq 0 ]]; then
            DDEV_RESOLVE_ERROR="no build script found for model '$model'"
            return 1
        fi
    fi
    if [[ "$operation" == run || "$operation" == run-only ]]; then
        if [[ "$found_run" -eq 0 ]]; then
            DDEV_RESOLVE_ERROR="no run script found for model '$model'"
            return 1
        fi
    fi

    for requested_phase in "${requested_phases[@]}"; do
        for index in "${!scripts[@]}"; do
            [[ "${phases[index]}" == "$requested_phase" ]] || continue
            script="${scripts[index]}"
            if [[ ! -x "$script" ]]; then
                DDEV_RESOLVE_ERROR="pipeline script is not executable: $script"
                return 1
            fi

            printf '[pipeline] Running %s\n' "${script##*/}"
            if "$script" \
                "$project_dir" \
                "$image_name" \
                "$container_name" \
                "${container_cmd[@]}"; then
                :
            else
                local script_status=$?
                DDEV_RESOLVE_ERROR="pipeline script failed (${script_status}): $script"
                return "$script_status"
            fi
        done
    done
}
