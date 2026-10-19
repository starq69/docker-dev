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
    "${PROJECT_TOOL_ROOT}/services/Postgres" \
    "${PROJECT_TOOL_ROOT}/stacks/Web" \
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

assert_failure_contains "unknown or unmanaged model" \
    ddev_resolve_build_project "$PROJECT_TOOL_ROOT" "$PROJECT_BASE" Unknown project

assert_failure_contains "must not contain '.' or '..'" \
    ddev_resolve_build_project "$PROJECT_TOOL_ROOT" "$PROJECT_BASE" Python ../outside

assert_success ddev_resolve_build_project \
    "$PROJECT_TOOL_ROOT" "$PROJECT_BASE" Python nested/new-project
[[ "$DDEV_PROJECT_DIR" == "${PROJECT_BASE}/Python/nested/new-project" ]] ||
    fail "relative build target resolved unexpectedly: $DDEV_PROJECT_DIR"
[[ "$DDEV_PROJECT_MODEL" == Python ]] || fail "build model was not retained"

assert_success ddev_resolve_build_project \
    "$PROJECT_TOOL_ROOT" "$PROJECT_BASE" Postgres app
[[ "$DDEV_PROJECT_DIR" == "${PROJECT_BASE}/Postgres/app" &&
    "$DDEV_PROJECT_MODEL" == Postgres ]] ||
    fail "service model did not resolve as a build target"
mkdir -p "${PROJECT_BASE}/Postgres/app"
assert_success ddev_write_project_tag "${PROJECT_BASE}/Postgres/app" Postgres "$PROJECT_TOOL_ROOT"
assert_success ddev_read_project_tag "${PROJECT_BASE}/Postgres/app" "$PROJECT_TOOL_ROOT"
[[ "$DDEV_TAG_MODEL" == Postgres ]] || fail "service model tag did not round-trip"

mkdir -p "${PROJECT_BASE}/Python/absolute"
assert_success ddev_resolve_build_project \
    "$PROJECT_TOOL_ROOT" "$PROJECT_BASE" Python "${PROJECT_BASE}/Python/absolute"
[[ "$DDEV_PROJECT_DIR" == "${PROJECT_BASE}/Python/absolute" ]] ||
    fail "absolute build target resolved unexpectedly: $DDEV_PROJECT_DIR"

assert_success ddev_write_project_tag "${PROJECT_BASE}/Python/absolute" Python "$PROJECT_TOOL_ROOT"
assert_success ddev_read_project_tag "${PROJECT_BASE}/Python/absolute" "$PROJECT_TOOL_ROOT"
[[ "$DDEV_TAG_MODEL" == Python ]] || fail "tag model was not read"
[[ "$(cat "${PROJECT_BASE}/Python/absolute/.docker-dev/project-tag")" == $'schema_version=1\nmodel=Python' ]] ||
    fail "tag file has unexpected content"

INSTANCE_ROOT="${PROJECT_BASE}/bun-team"
mkdir -p "$INSTANCE_ROOT"
assert_success ddev_write_instance_tag "$INSTANCE_ROOT" Bun "$PROJECT_TOOL_ROOT"
assert_success ddev_read_instance_tag "$INSTANCE_ROOT" "$PROJECT_TOOL_ROOT"
[[ "$DDEV_TAG_MODEL" == Bun ]] || fail "instance tag did not round-trip"
[[ "$(cat "${INSTANCE_ROOT}/.docker-dev/instance-tag")" == $'schema_version=1\nmodel=Bun' ]] ||
    fail "instance tag has unexpected content"
assert_failure_contains "instance tag already exists" \
    ddev_write_instance_tag "$INSTANCE_ROOT" Bun "$PROJECT_TOOL_ROOT"

previous_directory="$PWD"
cd "$INSTANCE_ROOT"
assert_success ddev_resolve_build_project "$PROJECT_TOOL_ROOT" "$PROJECT_BASE" "" apps/hello
[[ "$DDEV_PROJECT_DIR" == "${INSTANCE_ROOT}/apps/hello" && "$DDEV_PROJECT_MODEL" == Bun ]] ||
    fail "build did not infer model/root from instance tag"
assert_failure_contains "explicit model 'Python' does not match instance model 'Bun'" \
    ddev_resolve_build_project "$PROJECT_TOOL_ROOT" "$PROJECT_BASE" Python apps/mismatch
mkdir -p "${INSTANCE_ROOT}/absolute"
assert_success ddev_resolve_build_project \
    "$PROJECT_TOOL_ROOT" "$PROJECT_BASE" "" "${INSTANCE_ROOT}/absolute"
[[ "$DDEV_PROJECT_MODEL" == Bun ]] || fail "absolute target did not infer enclosing instance model"
cd "$previous_directory"

EXTERNAL_ROOT="${TEST_ROOT}/outside"
EXTERNAL_PROJECT="${EXTERNAL_ROOT}/tagged-project"
EXTERNAL_NO_TAG="${EXTERNAL_ROOT}/untagged-project"
mkdir -p "$EXTERNAL_ROOT" "$EXTERNAL_PROJECT" "$EXTERNAL_NO_TAG"
assert_success ddev_write_instance_tag "$EXTERNAL_ROOT" Bun "$PROJECT_TOOL_ROOT"
assert_success ddev_write_project_tag "$EXTERNAL_PROJECT" Postgres "$PROJECT_TOOL_ROOT"
assert_success ddev_resolve_build_project \
    "$PROJECT_TOOL_ROOT" "$PROJECT_BASE" "" "$EXTERNAL_PROJECT"
[[ "$DDEV_PROJECT_MODEL" == Postgres ]] ||
    fail "external absolute target used an ancestor instance tag instead of its project tag"
assert_failure_contains "model cannot be inferred" \
    ddev_resolve_build_project "$PROJECT_TOOL_ROOT" "$PROJECT_BASE" "" "$EXTERNAL_NO_TAG"
assert_success ddev_resolve_build_project \
    "$PROJECT_TOOL_ROOT" "$PROJECT_BASE" Bun "$EXTERNAL_NO_TAG"
[[ "$DDEV_PROJECT_MODEL" == Bun ]] || fail "explicit model did not resolve an external absolute target"

# Existing project tags using lang= remain readable.
mkdir -p "${PROJECT_BASE}/Perl/legacy-tag/.docker-dev"
printf 'schema_version=1\nlang=Perl\n' > "${PROJECT_BASE}/Perl/legacy-tag/.docker-dev/project-tag"
assert_success ddev_read_project_tag "${PROJECT_BASE}/Perl/legacy-tag" "$PROJECT_TOOL_ROOT"
[[ "$DDEV_TAG_MODEL" == Perl ]] || fail "legacy language tag was not read as a model"

previous_directory="$PWD"
cd "${PROJECT_BASE}/Python/absolute"
assert_success ddev_resolve_build_project "$PROJECT_TOOL_ROOT" "$PROJECT_BASE" Python ""
[[ "$DDEV_PROJECT_DIR" == "${PROJECT_BASE}/Python/absolute" ]] ||
    fail "build without target did not resolve to the current directory"
assert_success ddev_resolve_run_project "$PROJECT_TOOL_ROOT" "$PROJECT_BASE" ""
[[ "$DDEV_PROJECT_DIR" == "${PROJECT_BASE}/Python/absolute" && "$DDEV_PROJECT_MODEL" == Python ]] ||
    fail "run without target did not use current directory and its tag"
cd "$previous_directory"

mkdir -p "${PROJECT_BASE}/Python/single"
assert_success ddev_write_project_tag "${PROJECT_BASE}/Python/single" Python "$PROJECT_TOOL_ROOT"
previous_directory="$PWD"
cd "${PROJECT_BASE}/Python"
assert_success ddev_resolve_run_project "$PROJECT_TOOL_ROOT" "$PROJECT_BASE" single
[[ "$DDEV_PROJECT_DIR" == "${PROJECT_BASE}/Python/single" ]] ||
    fail "run did not resolve the unique matching target"
[[ "$DDEV_PROJECT_MODEL" == Python ]] || fail "run did not derive model from project tag"
cd "$previous_directory"

mkdir -p "${PROJECT_BASE}/Perl/single"
assert_success ddev_write_project_tag "${PROJECT_BASE}/Perl/single" Perl "$PROJECT_TOOL_ROOT"

assert_success ddev_resolve_run_project \
    "$PROJECT_TOOL_ROOT" "$PROJECT_BASE" "${PROJECT_BASE}/Perl/single"
[[ "$DDEV_PROJECT_MODEL" == Perl ]] || fail "absolute run target did not use tag model"

mkdir -p "${PROJECT_BASE}/Bun" "${PROJECT_BASE}/Bun/bar" "${PROJECT_BASE}/Python/bar"
mkdir -p "${PROJECT_BASE}/Python/bar/.docker-dev"
printf 'schema_version=1\nlang=Python\n' > "${PROJECT_BASE}/Python/bar/.docker-dev/project-tag"
previous_directory="$PWD"
cd "${PROJECT_BASE}/Bun"
assert_success ddev_resolve_run_project "$PROJECT_TOOL_ROOT" "$PROJECT_BASE" bar
[[ "$DDEV_PROJECT_DIR" == "${PROJECT_BASE}/Bun/bar" && "$DDEV_PROJECT_MODEL" == Bun ]] ||
    fail "local target did not take precedence over another model's project"
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
[[ "$DDEV_PROJECT_MODEL" == Python ]] ||
    fail "legacy project without a tag did not infer its model from the current directory"
cd "$previous_directory"

mkdir -p "${TEST_ROOT}/outside/no-tag"
previous_directory="$PWD"
cd "${TEST_ROOT}/outside"
assert_failure_contains "model cannot be inferred" \
    ddev_resolve_run_project "$PROJECT_TOOL_ROOT" "$PROJECT_BASE" no-tag
cd "$previous_directory"

mkdir -p "${PROJECT_BASE}/Python/bad-tag/.docker-dev"
printf 'schema_version=2\nlang=Python\n' > "${PROJECT_BASE}/Python/bad-tag/.docker-dev/project-tag"
assert_failure_contains "unsupported project tag schema_version" \
    ddev_read_project_tag "${PROJECT_BASE}/Python/bad-tag" "$PROJECT_TOOL_ROOT"

PIPELINE_ROOT="${TEST_ROOT}/pipeline"
PIPELINE_LOG="${TEST_ROOT}/pipeline.log"
mkdir -p "${PIPELINE_ROOT}/langs/Fixture/bin"
mkdir -p "${PIPELINE_ROOT}/services/Postgres/bin" "${PIPELINE_ROOT}/stacks/Web/bin"
for model_bin in "${PIPELINE_ROOT}/langs/Fixture/bin" \
    "${PIPELINE_ROOT}/services/Postgres/bin" "${PIPELINE_ROOT}/stacks/Web/bin"; do
    for script_name in 20.build.sh 30.run.sh 40.setup-volumes.sh; do
    cat > "${model_bin}/${script_name}" <<'SCRIPT'
#!/usr/bin/env bash
printf '%s\n' "${0##*/}" >> "$DDEV_TEST_PIPELINE_LOG"
SCRIPT
    chmod +x "${model_bin}/${script_name}"
    done
done

export DDEV_TEST_PIPELINE_LOG="$PIPELINE_LOG"
ddev_run_model_operation "$PIPELINE_ROOT" "$TEST_ROOT/project" Fixture fixture-image fixture-container build
[[ "$(cat "$PIPELINE_LOG")" == $'40.setup-volumes.sh\n20.build.sh' ]] ||
    fail "build operation ran unexpected pipeline steps: $(cat "$PIPELINE_LOG")"

: > "$PIPELINE_LOG"
ddev_run_model_operation "$PIPELINE_ROOT" "$TEST_ROOT/project" Fixture fixture-image fixture-container run
[[ "$(cat "$PIPELINE_LOG")" == $'40.setup-volumes.sh\n30.run.sh' ]] ||
    fail "run operation ran unexpected pipeline steps: $(cat "$PIPELINE_LOG")"

: > "$PIPELINE_LOG"
ddev_run_model_operation "$PIPELINE_ROOT" "$TEST_ROOT/project" Fixture fixture-image fixture-container run-only
[[ "$(cat "$PIPELINE_LOG")" == '30.run.sh' ]] ||
    fail "run-only operation repeated setup: $(cat "$PIPELINE_LOG")"

ddev_run_model_operation "$PIPELINE_ROOT" "$TEST_ROOT/project" Postgres postgres-image postgres-container build
[[ "$(tail -n 2 "$PIPELINE_LOG")" == $'40.setup-volumes.sh\n20.build.sh' ]] ||
    fail "service model did not use its own pipeline"

: > "$PIPELINE_LOG"
ddev_run_model_operation "$PIPELINE_ROOT" "$TEST_ROOT/project" Web web-image web-container run-only
[[ "$(cat "$PIPELINE_LOG")" == '30.run.sh' ]] ||
    fail "stack model did not use its own pipeline"

AMBIGUOUS_ROOT="${TEST_ROOT}/ambiguous-tool"
mkdir -p "${AMBIGUOUS_ROOT}/langs/Shared" "${AMBIGUOUS_ROOT}/services/Shared"
if ddev_cli_find_model_dir "$AMBIGUOUS_ROOT" Shared; then
    fail "duplicate model names across roots were not rejected"
fi
[[ "$DDEV_RESOLVE_ERROR" == *"ambiguous model"* ]] ||
    fail "duplicate model diagnostic was not explicit: $DDEV_RESOLVE_ERROR"

TEMPLATE_ROOT="${TEST_ROOT}/template-tool"
TEMPLATE_PROJECT="${TEST_ROOT}/template-project"
mkdir -p "${TEMPLATE_ROOT}/services/Postgres/templates" "${TEMPLATE_ROOT}/.settings"
cp "${SCRIPT_DIR}/apply-templates.sh" "${TEMPLATE_ROOT}/apply-templates.sh"
cp "${SCRIPT_DIR}/docker-dev-cli.sh" "${TEMPLATE_ROOT}/docker-dev-cli.sh"
printf 'standard bashrc\n' > "${TEMPLATE_ROOT}/.settings/.bashrc"
printf '.bash_history\n' > "${TEMPLATE_ROOT}/.settings/.gitignore"
printf 'postgres template\n' > "${TEMPLATE_ROOT}/services/Postgres/templates/Dockerfile"
bash "${TEMPLATE_ROOT}/apply-templates.sh" "$TEMPLATE_PROJECT" Postgres >/dev/null
[[ "$(cat "${TEMPLATE_PROJECT}/Dockerfile")" == 'postgres template' ]] ||
    fail "service model templates were not selected from services/"

printf 'docker-dev project resolution and tag tests passed\n'
