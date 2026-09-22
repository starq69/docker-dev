#!/usr/bin/env bash
#
# docker_run_extra_args <project-dir>
#
# Resolves DOCKER_RUN_EXTRA_ARGS for docker run:
#   1. already set in the environment (one-off override)  -> kept
#   2. <project-dir>/docker-run-extra-args file                      -> used
#   3. fallback                                             -> --rm -it
# The file may hold any docker run options EXCEPT --name and the image
# reference (both are generated). Lines starting with '#' are ignored.
#
docker_run_extra_args() {
    local project_dir="$1"

    if [[ -z "${DOCKER_RUN_EXTRA_ARGS:-}" && -f "${project_dir}/docker-run-extra-args" ]]; then
        local value
        value="$(grep -v '^[[:space:]]*#' "${project_dir}/docker-run-extra-args" | tr '\n' ' ')"
        [[ -n "${value//[[:space:]]/}" ]] && DOCKER_RUN_EXTRA_ARGS="$value"
    fi

    DOCKER_RUN_EXTRA_ARGS="${DOCKER_RUN_EXTRA_ARGS:---rm -it}"
}
