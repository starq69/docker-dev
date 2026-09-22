#!/usr/bin/env bash
#
# docker_names [volume-prefix]
#
# Single naming authority for the toolkit. Must be sourced (by docker-dev.sh
# and by every langs/*/bin script) AFTER P_TARGET, P_TYPE, P_NAME are set.
#
# - IMAGE_NAME already set (-i option, or export)  -> kept
# - otherwise                                     -> ${P_TARGET}.${P_TYPE}
# IMAGE_NAME is always lowercased (docker repo names reject uppercase),
# CONTAINER_NAME is always derived from it. VOLUME_NAME is always derived
# from P_* (+ prefix), never from IMAGE_NAME, so an image override cannot
# orphan an existing volume.
#
docker_names() {
    local vol_prefix="${1:-}"

    IMAGE_NAME="${IMAGE_NAME:-${P_TARGET}.${P_TYPE}}"
    IMAGE_NAME="${IMAGE_NAME,,}"
    CONTAINER_NAME="${IMAGE_NAME}.${P_NAME}"

    if [[ -n "$vol_prefix" ]]; then
        VOLUME_NAME="${VOLUME_NAME:-${vol_prefix}.${P_TARGET}.${P_TYPE}.${P_NAME}}"
    fi
}
