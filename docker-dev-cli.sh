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
