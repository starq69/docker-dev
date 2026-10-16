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
    "${PROJECT_TOOL_ROOT}/langs/Bun" \
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
previous_directory="$PWD"
cd "${PROJECT_BASE}/Python"
assert_success ddev_resolve_run_project "$PROJECT_TOOL_ROOT" "$PROJECT_BASE" single
[[ "$DDEV_PROJECT_DIR" == "${PROJECT_BASE}/Python/single" ]] ||
    fail "run did not resolve the unique matching target"
[[ "$DDEV_PROJECT_LANG" == Python ]] || fail "run did not derive language from project tag"
cd "$previous_directory"

mkdir -p "${PROJECT_BASE}/Perl/single"
assert_success ddev_write_project_tag "${PROJECT_BASE}/Perl/single" Perl "$PROJECT_TOOL_ROOT"

assert_success ddev_resolve_run_project \
    "$PROJECT_TOOL_ROOT" "$PROJECT_BASE" "${PROJECT_BASE}/Perl/single"
[[ "$DDEV_PROJECT_LANG" == Perl ]] || fail "absolute run target did not use tag language"

mkdir -p "${PROJECT_BASE}/Bun" "${PROJECT_BASE}/Bun/bar" "${PROJECT_BASE}/Python/bar"
mkdir -p "${PROJECT_BASE}/Python/bar/.docker-dev"
printf 'schema_version=1\nlang=Python\n' > "${PROJECT_BASE}/Python/bar/.docker-dev/project-tag"
previous_directory="$PWD"
cd "${PROJECT_BASE}/Bun"
assert_success ddev_resolve_run_project "$PROJECT_TOOL_ROOT" "$PROJECT_BASE" bar
[[ "$DDEV_PROJECT_DIR" == "${PROJECT_BASE}/Bun/bar" && "$DDEV_PROJECT_LANG" == Bun ]] ||
    fail "local target did not take precedence over another language's project"
[[ ! -e "${PROJECT_BASE}/Bun/bar/.docker-dev/project-tag" ]] ||
    fail "run resolver unexpectedly wrote a legacy project tag"
cd "$previous_directory"

assert_failure_contains "does not exist under the current directory" \
    ddev_resolve_run_project "$PROJECT_TOOL_ROOT" "$PROJECT_BASE" single
previous_directory="$PWD"
cd "${PROJECT_BASE}/Python"
assert_failure_contains "does not exist under the current directory" \
    ddev_resolve_run_project "$PROJECT_TOOL_ROOT" "$PROJECT_BASE" missing
cd "$previous_directory"
assert_failure_contains "must not contain '.' or '..'" \
    ddev_resolve_run_project "$PROJECT_TOOL_ROOT" "$PROJECT_BASE" ../outside

mkdir -p "${PROJECT_BASE}/Python/no-tag"
previous_directory="$PWD"
cd "${PROJECT_BASE}/Python"
assert_success ddev_resolve_run_project "$PROJECT_TOOL_ROOT" "$PROJECT_BASE" no-tag
[[ "$DDEV_PROJECT_LANG" == Python ]] ||
    fail "legacy project without a tag did not infer its language from the current directory"
cd "$previous_directory"

mkdir -p "${TEST_ROOT}/outside/no-tag"
previous_directory="$PWD"
cd "${TEST_ROOT}/outside"
assert_failure_contains "language cannot be inferred" \
    ddev_resolve_run_project "$PROJECT_TOOL_ROOT" "$PROJECT_BASE" no-tag
cd "$previous_directory"

mkdir -p "${PROJECT_BASE}/Python/bad-tag/.docker-dev"
printf 'schema_version=2\nlang=Python\n' > "${PROJECT_BASE}/Python/bad-tag/.docker-dev/project-tag"
assert_failure_contains "unsupported project tag schema_version" \
    ddev_read_project_tag "${PROJECT_BASE}/Python/bad-tag" "$PROJECT_TOOL_ROOT"

PIPELINE_ROOT="${TEST_ROOT}/pipeline"
PIPELINE_LOG="${TEST_ROOT}/pipeline.log"
mkdir -p "${PIPELINE_ROOT}/langs/Fixture/bin"
for script_name in 20.build.sh 30.run.sh 40.setup-volumes.sh; do
    cat > "${PIPELINE_ROOT}/langs/Fixture/bin/${script_name}" <<'SCRIPT'
#!/usr/bin/env bash
printf '%s\n' "${0##*/}" >> "$DDEV_TEST_PIPELINE_LOG"
SCRIPT
    chmod +x "${PIPELINE_ROOT}/langs/Fixture/bin/${script_name}"
done

export DDEV_TEST_PIPELINE_LOG="$PIPELINE_LOG"
ddev_run_lang_operation "$PIPELINE_ROOT" "$TEST_ROOT/project" Fixture fixture-image fixture-container build
[[ "$(cat "$PIPELINE_LOG")" == $'40.setup-volumes.sh\n20.build.sh' ]] ||
    fail "build operation ran unexpected pipeline steps: $(cat "$PIPELINE_LOG")"

: > "$PIPELINE_LOG"
ddev_run_lang_operation "$PIPELINE_ROOT" "$TEST_ROOT/project" Fixture fixture-image fixture-container run
[[ "$(cat "$PIPELINE_LOG")" == $'40.setup-volumes.sh\n30.run.sh' ]] ||
    fail "run operation ran unexpected pipeline steps: $(cat "$PIPELINE_LOG")"

: > "$PIPELINE_LOG"
ddev_run_lang_operation "$PIPELINE_ROOT" "$TEST_ROOT/project" Fixture fixture-image fixture-container run-only
[[ "$(cat "$PIPELINE_LOG")" == '30.run.sh' ]] ||
    fail "run-only operation repeated setup: $(cat "$PIPELINE_LOG")"

printf 'docker-dev project resolution and tag tests passed\n'
