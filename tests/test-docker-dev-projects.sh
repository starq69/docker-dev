#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "${SCRIPT_DIR}/docker-dev-cli.sh"

TEST_ROOT="$(mktemp -d)"
trap 'rm -rf -- "$TEST_ROOT"' EXIT

PROJECT_TOOL_ROOT="${TEST_ROOT}/tool"
PROJECT_BASE="${TEST_ROOT}/REP/DEV"
mkdir -p "${PROJECT_TOOL_ROOT}/langs/Python" \
    "${PROJECT_TOOL_ROOT}/langs/Perl" \
    "${PROJECT_BASE}"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

assert_failure_contains() {
    local expected="$1"
    shift
    local status=0

    "$@" || status=$?
    if [[ "$status" -eq 0 || "$DDEV_RESOLVE_ERROR" != *"$expected"* ]]; then
        fail "expected failure containing '$expected'; status=$status error='$DDEV_RESOLVE_ERROR'"
    fi
}

assert_success() {
    "$@" || fail "expected success; error='$DDEV_RESOLVE_ERROR'"
}

assert_failure_contains "unknown or unmanaged language" \
    ddev_resolve_build_project "$PROJECT_TOOL_ROOT" "$PROJECT_BASE" Unknown project

assert_failure_contains "must not contain '.' or '..'" \
    ddev_resolve_build_project "$PROJECT_TOOL_ROOT" "$PROJECT_BASE" Python ../outside

assert_success ddev_resolve_build_project \
    "$PROJECT_TOOL_ROOT" "$PROJECT_BASE" Python nested/new-project
[[ "$DDEV_PROJECT_DIR" == "${PROJECT_BASE}/Python/nested/new-project" ]] ||
    fail "relative build target resolved unexpectedly: $DDEV_PROJECT_DIR"
[[ "$DDEV_PROJECT_LANG" == Python ]] || fail "build language was not retained"

mkdir -p "${PROJECT_BASE}/Python/absolute"
assert_success ddev_resolve_build_project \
    "$PROJECT_TOOL_ROOT" "$PROJECT_BASE" Python "${PROJECT_BASE}/Python/absolute"
[[ "$DDEV_PROJECT_DIR" == "${PROJECT_BASE}/Python/absolute" ]] ||
    fail "absolute build target resolved unexpectedly: $DDEV_PROJECT_DIR"

assert_success ddev_write_project_tag "${PROJECT_BASE}/Python/absolute" Python "$PROJECT_TOOL_ROOT"
assert_success ddev_read_project_tag "${PROJECT_BASE}/Python/absolute" "$PROJECT_TOOL_ROOT"
[[ "$DDEV_TAG_LANG" == Python ]] || fail "tag language was not read"
[[ "$(cat "${PROJECT_BASE}/Python/absolute/.docker-dev/project-tag")" == $'schema_version=1\nlang=Python' ]] ||
    fail "tag file has unexpected content"

previous_directory="$PWD"
cd "${PROJECT_BASE}/Python/absolute"
assert_success ddev_resolve_build_project "$PROJECT_TOOL_ROOT" "$PROJECT_BASE" Python ""
[[ "$DDEV_PROJECT_DIR" == "${PROJECT_BASE}/Python/absolute" ]] ||
    fail "build without target did not resolve to the current directory"
assert_success ddev_resolve_run_project "$PROJECT_TOOL_ROOT" "$PROJECT_BASE" ""
[[ "$DDEV_PROJECT_DIR" == "${PROJECT_BASE}/Python/absolute" && "$DDEV_PROJECT_LANG" == Python ]] ||
    fail "run without target did not use current directory and its tag"
cd "$previous_directory"

mkdir -p "${PROJECT_BASE}/Python/single"
assert_success ddev_write_project_tag "${PROJECT_BASE}/Python/single" Python "$PROJECT_TOOL_ROOT"
assert_success ddev_resolve_run_project "$PROJECT_TOOL_ROOT" "$PROJECT_BASE" single
[[ "$DDEV_PROJECT_DIR" == "${PROJECT_BASE}/Python/single" ]] ||
    fail "run did not resolve the unique matching target"
[[ "$DDEV_PROJECT_LANG" == Python ]] || fail "run did not derive language from project tag"

mkdir -p "${PROJECT_BASE}/Perl/single"
assert_success ddev_write_project_tag "${PROJECT_BASE}/Perl/single" Perl "$PROJECT_TOOL_ROOT"
status=0
ddev_resolve_run_project "$PROJECT_TOOL_ROOT" "$PROJECT_BASE" single || status=$?
[[ "$status" -eq 2 && "$DDEV_RESOLVE_AMBIGUOUS" -eq 1 ]] ||
    fail "expected ambiguous target status 2, got status=$status error='$DDEV_RESOLVE_ERROR'"
[[ "${#DDEV_CANDIDATE_PATHS[@]}" -eq 2 ]] || fail "ambiguity did not list both candidates"
[[ "$DDEV_RESOLVE_ERROR" == *"${PROJECT_BASE}/Python/single"* &&
   "$DDEV_RESOLVE_ERROR" == *"${PROJECT_BASE}/Perl/single"* ]] ||
    fail "ambiguity message omitted candidate paths"

assert_success ddev_resolve_run_project \
    "$PROJECT_TOOL_ROOT" "$PROJECT_BASE" "${PROJECT_BASE}/Perl/single"
[[ "$DDEV_PROJECT_LANG" == Perl ]] || fail "absolute run target did not use tag language"

assert_failure_contains "no project found" \
    ddev_resolve_run_project "$PROJECT_TOOL_ROOT" "$PROJECT_BASE" absent
assert_failure_contains "must not contain '.' or '..'" \
    ddev_resolve_run_project "$PROJECT_TOOL_ROOT" "$PROJECT_BASE" ../outside

mkdir -p "${PROJECT_BASE}/Python/no-tag"
assert_failure_contains "missing or invalid project tags" \
    ddev_resolve_run_project "$PROJECT_TOOL_ROOT" "$PROJECT_BASE" no-tag

mkdir -p "${PROJECT_BASE}/Python/bad-tag/.docker-dev"
printf 'schema_version=2\nlang=Python\n' > "${PROJECT_BASE}/Python/bad-tag/.docker-dev/project-tag"
assert_failure_contains "unsupported project tag schema_version" \
    ddev_read_project_tag "${PROJECT_BASE}/Python/bad-tag" "$PROJECT_TOOL_ROOT"

printf 'docker-dev project resolution and tag tests passed\n'
