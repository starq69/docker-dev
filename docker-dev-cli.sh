#!/usr/bin/env bash

ddev_cli_usage() {
    cat <<'USAGE'
Usage:
  docker-dev build --lang <lang> [--target <target>] [-x] [-y]
  docker-dev run [--target <target>]

Commands:
  build  Prepare and build a project; -x also requests a run.
  run    Run a project without an implicit build.

Options:
  --lang <lang>     Required by build.
  --target <target> Project target.
  -x                Also run after build.
  -y                Skip the build confirmation prompt.
  -h, --help        Show this help.
USAGE
}

ddev_cli_build_usage() {
    cat <<'USAGE'
Usage: docker-dev build --lang <lang> [--target <target>] [-x] [-y]
USAGE
}

ddev_cli_run_usage() {
    cat <<'USAGE'
Usage: docker-dev run [--target <target>]
USAGE
}

ddev_cli_parse() {
    DDEV_OPERATION=legacy
    DDEV_LANG=""
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
            --lang)
                if [[ "$DDEV_OPERATION" != build ]]; then
                    DDEV_PARSE_ERROR="--lang is only valid with build"
                    return 2
                fi
                if (($# < 2)) || [[ -z "$2" ]]; then
                    DDEV_PARSE_ERROR="--lang requires a non-empty value"
                    return 2
                fi
                if [[ -n "$DDEV_LANG" ]]; then
                    DDEV_PARSE_ERROR="--lang may be specified only once"
                    return 2
                fi
                DDEV_LANG="$2"
                shift 2
                ;;
            --lang=*)
                if [[ "$DDEV_OPERATION" != build ]]; then
                    DDEV_PARSE_ERROR="--lang is only valid with build"
                    return 2
                fi
                if [[ -z "${1#--lang=}" ]]; then
                    DDEV_PARSE_ERROR="--lang requires a non-empty value"
                    return 2
                fi
                if [[ -n "$DDEV_LANG" ]]; then
                    DDEV_PARSE_ERROR="--lang may be specified only once"
                    return 2
                fi
                DDEV_LANG="${1#--lang=}"
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

    if [[ "$DDEV_OPERATION" == build && "$DDEV_SHOW_HELP" -eq 0 && -z "$DDEV_LANG" ]]; then
        DDEV_PARSE_ERROR="build requires --lang"
        return 2
    fi
}

ddev_cli_load_languages() {
    local script_dir="$1"
    local lang_dir="${script_dir}/langs"

    DDEV_LANGUAGES=()
    if [[ ! -d "$lang_dir" ]]; then
        DDEV_RESOLVE_ERROR="language directory not found: $lang_dir"
        return 1
    fi

    mapfile -t DDEV_LANGUAGES < <(
        find "$lang_dir" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort
    )
    if ((${#DDEV_LANGUAGES[@]} == 0)); then
        DDEV_RESOLVE_ERROR="no managed languages found in: $lang_dir"
        return 1
    fi
}

ddev_cli_is_managed_language() {
    local script_dir="$1"
    local lang="$2"

    [[ "$lang" =~ ^[A-Za-z0-9_-]+$ && -d "${script_dir}/langs/${lang}" ]]
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
    local lang="$3"
    local target="$4"
    local resolved_base
    local resolved_project

    DDEV_PROJECT_DIR=""
    DDEV_PROJECT_LANG=""
    DDEV_RESOLVE_ERROR=""

    if ! ddev_cli_is_managed_language "$script_dir" "$lang"; then
        DDEV_RESOLVE_ERROR="unknown or unmanaged language: $lang"
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
        resolved_project="$(readlink -m -- "${resolved_base}/${lang}/${target}")"
        case "$resolved_project" in
            "${resolved_base}/${lang}/"*) ;;
            *)
                DDEV_RESOLVE_ERROR="target resolves outside the language project directory: $target"
                return 1
                ;;
        esac
    fi

    DDEV_PROJECT_DIR="$resolved_project"
    DDEV_PROJECT_LANG="$lang"
}

ddev_read_project_tag() {
    local project_dir="$1"
    local script_dir="$2"
    local metadata_dir="${project_dir}/.docker-dev"
    local tag_file="${metadata_dir}/project-tag"
    local line
    local schema_version=""
    local lang=""
    local seen_schema=0
    local seen_lang=0

    DDEV_TAG_LANG=""
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
            lang=*)
                if ((seen_lang)); then
                    DDEV_RESOLVE_ERROR="duplicate lang in project tag: $tag_file"
                    return 1
                fi
                lang="${line#lang=}"
                seen_lang=1
                ;;
            *)
                DDEV_RESOLVE_ERROR="invalid field in project tag: $tag_file"
                return 1
                ;;
        esac
    done < "$tag_file"

    if ((!seen_schema || !seen_lang)) || [[ -z "$schema_version" || -z "$lang" ]]; then
        DDEV_RESOLVE_ERROR="project tag must contain non-empty schema_version and lang fields: $tag_file"
        return 1
    fi
    if [[ "$schema_version" != 1 ]]; then
        DDEV_RESOLVE_ERROR="unsupported project tag schema_version '$schema_version': $tag_file"
        return 1
    fi
    if ! ddev_cli_is_managed_language "$script_dir" "$lang"; then
        DDEV_RESOLVE_ERROR="project tag refers to an unknown or unmanaged language '$lang': $tag_file"
        return 1
    fi

    DDEV_TAG_LANG="$lang"
}

ddev_write_project_tag() {
    local project_dir="$1"
    local lang="$2"
    local script_dir="$3"
    local metadata_dir="${project_dir}/.docker-dev"
    local tag_file="${metadata_dir}/project-tag"
    local temporary_file

    DDEV_RESOLVE_ERROR=""

    if ! ddev_cli_is_managed_language "$script_dir" "$lang"; then
        DDEV_RESOLVE_ERROR="cannot write project tag for unknown or unmanaged language: $lang"
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
    if ! printf 'schema_version=1\nlang=%s\n' "$lang" > "$temporary_file"; then
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
    local local_lang=""
    local local_tag_file
    local lang

    DDEV_PROJECT_DIR=""
    DDEV_PROJECT_LANG=""
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
        DDEV_PROJECT_LANG="$DDEV_TAG_LANG"
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
        DDEV_PROJECT_LANG="$DDEV_TAG_LANG"
        return 0
    fi

    if [[ "$base" != /* || ! -d "$base" ]]; then
        DDEV_RESOLVE_ERROR="project base must be an existing absolute directory: $base"
        return 1
    fi
    if ! ddev_cli_validate_relative_target "$target"; then
        return 1
    fi
    if ! ddev_cli_load_languages "$script_dir"; then
        return 1
    fi

    resolved_base="$(readlink -m -- "$base")"
    resolved_pwd="$(readlink -m -- "$PWD")"

    for lang in "${DDEV_LANGUAGES[@]}"; do
        case "$resolved_pwd" in
            "${resolved_base}/${lang}"|"${resolved_base}/${lang}/"*)
                local_lang="$lang"
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
        if [[ -n "$local_lang" && "$DDEV_TAG_LANG" != "$local_lang" ]]; then
            DDEV_RESOLVE_ERROR="project tag language '$DDEV_TAG_LANG' does not match current language directory '$local_lang': $resolved_candidate"
            return 1
        fi
        DDEV_PROJECT_LANG="$DDEV_TAG_LANG"
    elif [[ -n "$local_lang" ]]; then
        DDEV_PROJECT_LANG="$local_lang"
    else
        DDEV_RESOLVE_ERROR="project tag is missing and the language cannot be inferred from the current directory: $local_tag_file"
        return 1
    fi

    DDEV_PROJECT_DIR="$resolved_candidate"
}

ddev_run_lang_operation() {
    local script_dir="$1"
    local project_dir="$2"
    local lang="$3"
    local image_name="$4"
    local container_name="$5"
    local operation="$6"
    shift 6

    local bin_dir="${script_dir}/langs/${lang}/bin"
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

    case "$operation" in
        build) requested_phases=(setup build) ;;
        run) requested_phases=(setup run) ;;
        run-only) requested_phases=(run) ;;
        *)
            DDEV_RESOLVE_ERROR="unknown language operation: $operation"
            return 1
            ;;
    esac

    if [[ ! -d "$bin_dir" ]]; then
        DDEV_RESOLVE_ERROR="language pipeline directory not found: $bin_dir"
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
            DDEV_RESOLVE_ERROR="no build script found for language '$lang'"
            return 1
        fi
    fi
    if [[ "$operation" == run || "$operation" == run-only ]]; then
        if [[ "$found_run" -eq 0 ]]; then
            DDEV_RESOLVE_ERROR="no run script found for language '$lang'"
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
