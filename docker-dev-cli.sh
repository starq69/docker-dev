#!/usr/bin/env bash

ddev_cli_usage() {
    cat <<'USAGE'
Usage:
    docker-dev build [--model <model>] [--target <target>] [-x] [-y]
  docker-dev run [--target <target>]
    docker-dev tag --model <model> [--target <directory>]
    docker-dev info --tag

Commands:
  build  Prepare and build a project; -x also requests a run.
  run    Run a project without an implicit build.

Options:
    --model <model>   Optional for build; required by tag. Must be managed.
  --lang <lang>     Legacy alias for --model.
  --target <target> Project target.
  -x                Also run after build.
  -y                Skip the build confirmation prompt.
  -h, --help        Show this help.
USAGE
}

ddev_cli_build_usage() {
    cat <<'USAGE'
Usage: docker-dev build [--model <model>] [--target <target>] [-x] [-y]
USAGE
}

ddev_cli_run_usage() {
    cat <<'USAGE'
Usage: docker-dev run [--target <target>]
USAGE
}

ddev_cli_tag_usage() {
    cat <<'USAGE'
Usage: docker-dev tag --model <model> [--target <directory>]
USAGE
}

ddev_cli_info_usage() {
    cat <<'USAGE'
Usage: docker-dev info --tag
USAGE
}

ddev_cli_parse() {
    DDEV_OPERATION=legacy
    DDEV_MODEL=""
    DDEV_TARGET=""
    DDEV_BUILD_AND_RUN=0
    DDEV_ASSUME_YES=0
    DDEV_SHOW_HELP=0
    DDEV_INFO_TAG=0
    DDEV_PARSE_ERROR=""

    case "${1-}" in
        build|run|tag|info)
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
                if [[ "$DDEV_OPERATION" != build && "$DDEV_OPERATION" != tag ]]; then
                    DDEV_PARSE_ERROR="--model is only valid with build or tag"
                    return 2
                fi
                if [[ "$1" == --lang && "$DDEV_OPERATION" == tag ]]; then
                    DDEV_PARSE_ERROR="--lang is not supported with tag; use --model"
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
                if [[ "$DDEV_OPERATION" != build && "$DDEV_OPERATION" != tag ]]; then
                    DDEV_PARSE_ERROR="--model is only valid with build or tag"
                    return 2
                fi
                if [[ "$1" == --lang=* && "$DDEV_OPERATION" == tag ]]; then
                    DDEV_PARSE_ERROR="--lang is not supported with tag; use --model"
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
                if [[ "$DDEV_OPERATION" == info ]]; then
                    DDEV_PARSE_ERROR="--target is not valid with info"
                    return 2
                fi
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
                if [[ "$DDEV_OPERATION" == info ]]; then
                    DDEV_PARSE_ERROR="--target is not valid with info"
                    return 2
                fi
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
            --tag)
                if [[ "$DDEV_OPERATION" != info ]]; then
                    DDEV_PARSE_ERROR="--tag is only valid with info"
                    return 2
                fi
                if ((DDEV_INFO_TAG)); then
                    DDEV_PARSE_ERROR="--tag may be specified only once"
                    return 2
                fi
                DDEV_INFO_TAG=1
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

    if [[ "$DDEV_OPERATION" == tag && "$DDEV_SHOW_HELP" -eq 0 && -z "$DDEV_MODEL" ]]; then
        DDEV_PARSE_ERROR="tag requires --model"
        return 2
    fi
    if [[ "$DDEV_OPERATION" == info && "$DDEV_SHOW_HELP" -eq 0 && "$DDEV_INFO_TAG" -ne 1 ]]; then
        DDEV_PARSE_ERROR="info requires --tag"
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

ddev_path_is_within() {
    local path="$1"
    local parent="$2"

    if [[ "$parent" == / ]]; then
        [[ "$path" == /* ]]
    else
        [[ "$path" == "$parent" || "$path" == "$parent/"* ]]
    fi
}

ddev_read_instance_tag() {
    local instance_dir="$1"
    local script_dir="$2"
    local metadata_dir="${instance_dir}/.docker-dev"
    local tag_file="${metadata_dir}/instance-tag"
    local line
    local schema_version=""
    local model=""
    local seen_schema=0
    local seen_model=0

    DDEV_TAG_MODEL=""
    DDEV_RESOLVE_ERROR=""

    if [[ -L "$metadata_dir" || ! -d "$metadata_dir" ]]; then
        DDEV_RESOLVE_ERROR="instance metadata directory is missing or invalid: $metadata_dir"
        return 1
    fi
    if [[ -L "$tag_file" || ! -f "$tag_file" || ! -r "$tag_file" ]]; then
        DDEV_RESOLVE_ERROR="instance tag is missing or is not a readable regular file: $tag_file"
        return 1
    fi

    while IFS= read -r line || [[ -n "$line" ]]; do
        case "$line" in
            schema_version=*)
                if ((seen_schema)); then
                    DDEV_RESOLVE_ERROR="duplicate schema_version in instance tag: $tag_file"
                    return 1
                fi
                schema_version="${line#schema_version=}"
                seen_schema=1
                ;;
            model=*)
                if ((seen_model)); then
                    DDEV_RESOLVE_ERROR="duplicate model in instance tag: $tag_file"
                    return 1
                fi
                model="${line#model=}"
                seen_model=1
                ;;
            *)
                DDEV_RESOLVE_ERROR="invalid field in instance tag: $tag_file"
                return 1
                ;;
        esac
    done < "$tag_file"

    if ((!seen_schema || !seen_model)) || [[ -z "$schema_version" || -z "$model" ]]; then
        DDEV_RESOLVE_ERROR="instance tag must contain non-empty schema_version and model fields: $tag_file"
        return 1
    fi
    if [[ "$schema_version" != 1 ]]; then
        DDEV_RESOLVE_ERROR="unsupported instance tag schema_version '$schema_version': $tag_file"
        return 1
    fi
    if ! ddev_cli_is_managed_model "$script_dir" "$model"; then
        DDEV_RESOLVE_ERROR="instance tag refers to ${DDEV_RESOLVE_ERROR}: $tag_file"
        return 1
    fi

    DDEV_TAG_MODEL="$model"
}

ddev_write_instance_tag() {
    local instance_dir="$1"
    local model="$2"
    local script_dir="$3"
    local metadata_dir="${instance_dir}/.docker-dev"
    local tag_file="${metadata_dir}/instance-tag"
    local temporary_file

    DDEV_RESOLVE_ERROR=""
    if ! ddev_cli_is_managed_model "$script_dir" "$model"; then
        return 1
    fi
    if [[ ! -d "$instance_dir" || ! -w "$instance_dir" ]]; then
        DDEV_RESOLVE_ERROR="instance directory must exist and be writable: $instance_dir"
        return 1
    fi
    if [[ -L "$metadata_dir" || ( -e "$metadata_dir" && ! -d "$metadata_dir" ) ]]; then
        DDEV_RESOLVE_ERROR="instance metadata path is not a real directory: $metadata_dir"
        return 1
    fi
    if [[ ! -d "$metadata_dir" ]] && ! mkdir -p -- "$metadata_dir"; then
        DDEV_RESOLVE_ERROR="cannot create instance metadata directory: $metadata_dir"
        return 1
    fi
    if [[ -e "$tag_file" || -L "$tag_file" ]]; then
        DDEV_RESOLVE_ERROR="instance tag already exists: $tag_file"
        return 1
    fi

    if ! temporary_file="$(mktemp -- "${metadata_dir}/.instance-tag.XXXXXX")"; then
        DDEV_RESOLVE_ERROR="cannot create temporary instance tag in: $metadata_dir"
        return 1
    fi
    if ! printf 'schema_version=1\nmodel=%s\n' "$model" > "$temporary_file"; then
        rm -f -- "$temporary_file"
        DDEV_RESOLVE_ERROR="cannot write temporary instance tag in: $metadata_dir"
        return 1
    fi
    if ! mv -n -- "$temporary_file" "$tag_file"; then
        rm -f -- "$temporary_file"
        DDEV_RESOLVE_ERROR="cannot publish instance tag: $tag_file"
        return 1
    fi
    if [[ -e "$temporary_file" ]]; then
        rm -f -- "$temporary_file"
        DDEV_RESOLVE_ERROR="instance tag already exists: $tag_file"
        return 1
    fi
}

ddev_resolve_instance_context() {
    local script_dir="$1"
    local base="$2"
    local start_dir="$3"
    local resolved_base
    local resolved_start
    local current_dir
    local relative_path
    local legacy_model
    local tag_file

    DDEV_INSTANCE_MODEL=""
    DDEV_INSTANCE_DIR=""
    DDEV_INSTANCE_SOURCE=""
    DDEV_RESOLVE_ERROR=""

    resolved_base="$(readlink -m -- "$base")"
    resolved_start="$(readlink -m -- "$start_dir")"
    if ! ddev_path_is_within "$resolved_start" "$resolved_base"; then
        return 0
    fi

    current_dir="$resolved_start"
    while :; do
        tag_file="${current_dir}/.docker-dev/instance-tag"
        if [[ -e "$tag_file" || -L "$tag_file" ]]; then
            if ! ddev_read_instance_tag "$current_dir" "$script_dir"; then
                return 1
            fi
            DDEV_INSTANCE_MODEL="$DDEV_TAG_MODEL"
            DDEV_INSTANCE_DIR="$current_dir"
            DDEV_INSTANCE_SOURCE=instance-tag
            return 0
        fi
        [[ "$current_dir" == "$resolved_base" ]] && break
        current_dir="$(dirname -- "$current_dir")"
    done

    if [[ "$resolved_start" != "$resolved_base" ]]; then
        relative_path="${resolved_start#"${resolved_base%/}"/}"
        legacy_model="${relative_path%%/*}"
        if [[ -d "${resolved_base}/${legacy_model}" ]] && \
            ddev_cli_is_managed_model "$script_dir" "$legacy_model"; then
            DDEV_INSTANCE_MODEL="$legacy_model"
            DDEV_INSTANCE_DIR="${resolved_base}/${legacy_model}"
            DDEV_INSTANCE_SOURCE=legacy-root
        fi
    fi
}

ddev_resolve_project_model() {
    local script_dir="$1"
    local base="$2"
    local project_dir="$3"
    local explicit_model="$4"
    local allow_instance_context="$5"
    local project_tag_file="${project_dir}/.docker-dev/project-tag"
    local project_model=""

    DDEV_PROJECT_MODEL=""
    DDEV_MODEL_SOURCE=""
    DDEV_RESOLVE_ERROR=""

    if [[ -e "$project_tag_file" || -L "$project_tag_file" ]]; then
        if ! ddev_read_project_tag "$project_dir" "$script_dir"; then
            return 1
        fi
        project_model="$DDEV_TAG_MODEL"
    fi

    if [[ "$allow_instance_context" == 1 ]]; then
        if ! ddev_resolve_instance_context "$script_dir" "$base" "$project_dir"; then
            return 1
        fi
    else
        DDEV_INSTANCE_MODEL=""
        DDEV_INSTANCE_DIR=""
        DDEV_INSTANCE_SOURCE=""
    fi

    if [[ -n "$project_model" && -n "$DDEV_INSTANCE_MODEL" &&
          "$project_model" != "$DDEV_INSTANCE_MODEL" ]]; then
        DDEV_RESOLVE_ERROR="project tag model '$project_model' does not match instance model '$DDEV_INSTANCE_MODEL': $project_dir"
        return 1
    fi
    if [[ -n "$explicit_model" ]]; then
        if ! ddev_cli_is_managed_model "$script_dir" "$explicit_model"; then
            return 1
        fi
        if [[ -n "$project_model" && "$project_model" != "$explicit_model" ]]; then
            DDEV_RESOLVE_ERROR="explicit model '$explicit_model' does not match project tag model '$project_model': $project_dir"
            return 1
        fi
        if [[ -n "$DDEV_INSTANCE_MODEL" && "$DDEV_INSTANCE_MODEL" != "$explicit_model" ]]; then
            DDEV_RESOLVE_ERROR="explicit model '$explicit_model' does not match instance model '$DDEV_INSTANCE_MODEL': $project_dir"
            return 1
        fi
        DDEV_PROJECT_MODEL="$explicit_model"
        DDEV_MODEL_SOURCE=explicit
    elif [[ -n "$project_model" ]]; then
        DDEV_PROJECT_MODEL="$project_model"
        DDEV_MODEL_SOURCE=project-tag
    elif [[ -n "$DDEV_INSTANCE_MODEL" ]]; then
        DDEV_PROJECT_MODEL="$DDEV_INSTANCE_MODEL"
        DDEV_MODEL_SOURCE="$DDEV_INSTANCE_SOURCE"
    else
        DDEV_RESOLVE_ERROR="model cannot be inferred from project tag, instance tag, or managed project root: $project_dir"
        return 1
    fi
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
    local explicit_model="$3"
    local target="$4"
    local resolved_base
    local resolved_project
    local resolved_pwd
    local target_root
    local allow_instance_context=1

    DDEV_PROJECT_DIR=""
    DDEV_PROJECT_MODEL=""
    DDEV_RESOLVE_ERROR=""

    if [[ "$base" != /* ]]; then
        DDEV_RESOLVE_ERROR="project base must be an absolute directory: $base"
        return 1
    fi
    resolved_base="$(readlink -m -- "$base")"
    resolved_pwd="$(readlink -m -- "$PWD")"

    if [[ -n "$explicit_model" ]] && ! ddev_cli_is_managed_model "$script_dir" "$explicit_model"; then
        return 1
    fi

    if [[ -z "$target" ]]; then
        resolved_project="$resolved_pwd"
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
        if ! ddev_resolve_project_model "$script_dir" "$resolved_base" "$resolved_pwd" "$explicit_model" 1; then
            return 1
        fi
        if [[ "$DDEV_INSTANCE_SOURCE" == instance-tag ]]; then
            target_root="$DDEV_INSTANCE_DIR"
        else
            target_root="${resolved_base}/${DDEV_PROJECT_MODEL}"
        fi
        resolved_project="$(readlink -m -- "${target_root}/${target}")"
        case "$resolved_project" in
            "${target_root}/"*) ;;
            *)
                DDEV_RESOLVE_ERROR="target resolves outside its project root: $target"
                return 1
                ;;
        esac
    fi

    if ! ddev_resolve_project_model \
        "$script_dir" "$resolved_base" "$resolved_project" "$explicit_model" "$allow_instance_context"; then
        return 1
    fi

    DDEV_PROJECT_DIR="$resolved_project"
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

    DDEV_PROJECT_DIR=""
    DDEV_PROJECT_MODEL=""
    DDEV_RESOLVE_ERROR=""

    if [[ -z "$target" ]]; then
        resolved_candidate="$(readlink -m -- "$PWD")"
        if [[ ! -d "$resolved_candidate" || ! -r "$resolved_candidate" ]]; then
            DDEV_RESOLVE_ERROR="current directory is not a readable project directory: $resolved_candidate"
            return 1
        fi
        if ! ddev_resolve_project_model "$script_dir" "$base" "$resolved_candidate" "" 1; then
            return 1
        fi
        DDEV_PROJECT_DIR="$resolved_candidate"
        return 0
    fi

    if [[ "$target" == /* ]]; then
        resolved_candidate="$(readlink -m -- "$target")"
        if [[ ! -d "$resolved_candidate" || ! -r "$resolved_candidate" ]]; then
            DDEV_RESOLVE_ERROR="absolute target must be an existing readable directory: $resolved_candidate"
            return 1
        fi
        if ! ddev_resolve_project_model "$script_dir" "$base" "$resolved_candidate" "" 1; then
            return 1
        fi
        DDEV_PROJECT_DIR="$resolved_candidate"
        return 0
    fi

    if [[ "$base" != /* || ! -d "$base" ]]; then
        DDEV_RESOLVE_ERROR="project base must be an existing absolute directory: $base"
        return 1
    fi
    if ! ddev_cli_validate_relative_target "$target"; then
        return 1
    fi
    resolved_base="$(readlink -m -- "$base")"
    resolved_pwd="$(readlink -m -- "$PWD")"

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

    if ! ddev_resolve_project_model "$script_dir" "$resolved_base" "$resolved_candidate" "" 1; then
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
