#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf -- "$TEST_ROOT"' EXIT

FAKE_BIN="${TEST_ROOT}/bin"
FAKE_IMAGES="${TEST_ROOT}/images"
FAKE_LOG="${TEST_ROOT}/docker.log"
ORG="${TEST_ROOT}/org"
HOME="${TEST_ROOT}/home"
export ORG HOME FAKE_IMAGES FAKE_LOG

mkdir -p "$FAKE_BIN" "$FAKE_IMAGES" "$ORG/REP" "$HOME"
cat > "${FAKE_BIN}/docker" <<'DOCKER'
#!/usr/bin/env bash
printf '%q ' "$@" >> "$FAKE_LOG"
printf '\n' >> "$FAKE_LOG"

case "$1" in
    info)
        exit 0
        ;;
    inspect)
        if [[ "$2" == --type=image && -f "${FAKE_IMAGES}/$3" ]]; then
            exit 0
        fi
        exit 1
        ;;
    volume)
        exit 0
        ;;
    build)
        if [[ "${DDEV_TEST_FAIL_BUILD:-0}" == 1 ]]; then
            exit 1
        fi
        while (($#)); do
            if [[ "$1" == -t ]]; then
                touch "${FAKE_IMAGES}/$2"
                break
            fi
            shift
        done
        exit 0
        ;;
    ps)
        exit 0
        ;;
    rm|run)
        exit 0
        ;;
    *)
        exit 0
        ;;
esac
DOCKER
chmod +x "${FAKE_BIN}/docker"
export PATH="${FAKE_BIN}:${PATH}"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

PROJECT_BASE="${ORG}/REP/DEV"
PROJECT_DIR="${PROJECT_BASE}/Python/basic"
INSTANCE_DIR="${PROJECT_BASE}/python-team"
mkdir -p "$INSTANCE_DIR"
env ORG="$ORG" HOME="$HOME" PATH="$PATH" \
    "$SCRIPT_DIR/docker-dev.sh" tag --model Python --target "$INSTANCE_DIR" \
    >"${TEST_ROOT}/tag.out" 2>&1 ||
    fail "tag command failed: $(cat "${TEST_ROOT}/tag.out")"
[[ "$(cat "${INSTANCE_DIR}/.docker-dev/instance-tag")" == $'schema_version=1\nmodel=Python' ]] ||
    fail "tag command wrote unexpected instance tag content"

set +e
env ORG="$ORG" HOME="$HOME" PATH="$PATH" \
    "$SCRIPT_DIR/docker-dev.sh" tag --model Bun --target "$INSTANCE_DIR" \
    >"${TEST_ROOT}/tag-existing.out" 2>&1
status=$?
set -e
[[ "$status" -ne 0 ]] || fail "tag command silently overwrote an instance tag"
grep -q 'instance tag already exists' "${TEST_ROOT}/tag-existing.out" ||
    fail "existing instance tag error was not explicit"

(
    cd "$INSTANCE_DIR"
    env ORG="$ORG" HOME="$HOME" PATH="$PATH" \
        "$SCRIPT_DIR/docker-dev.sh" info --tag >"${TEST_ROOT}/info.out" 2>&1
) || fail "info --tag failed: $(cat "${TEST_ROOT}/info.out")"
grep -q 'Effective model: Python (instance-tag)' "${TEST_ROOT}/info.out" ||
    fail "info --tag did not report the instance model"

(
    cd "$INSTANCE_DIR"
    env ORG="$ORG" HOME="$HOME" PATH="$PATH" \
        "$SCRIPT_DIR/docker-dev.sh" build --target inferred -y \
        >"${TEST_ROOT}/build-inferred.out" 2>&1
) || fail "build without --model did not infer the instance model: $(cat "${TEST_ROOT}/build-inferred.out")"
[[ "$(cat "${INSTANCE_DIR}/inferred/.docker-dev/project-tag")" == $'schema_version=1\nmodel=Python' ]] ||
    fail "model-inferred build did not write the expected project tag"

mkdir -p "${INSTANCE_DIR}/legacy-no-project-tag"
: > "$FAKE_LOG"
(
    cd "$INSTANCE_DIR"
    printf 'Y' | env ORG="$ORG" HOME="$HOME" PATH="$PATH" \
        "$SCRIPT_DIR/docker-dev.sh" run --target legacy-no-project-tag \
        >"${TEST_ROOT}/run-instance-inferred.out" 2>&1
) || fail "run did not infer the model from its enclosing instance: $(cat "${TEST_ROOT}/run-instance-inferred.out")"
grep -q '^run ' "$FAKE_LOG" || fail "run with inferred model did not start a container"
if grep -q '^build ' "$FAKE_LOG"; then
    fail "run with inferred model performed a build"
fi
[[ ! -e "${INSTANCE_DIR}/legacy-no-project-tag/.docker-dev/project-tag" ]] ||
    fail "run wrote a project tag for a legacy project"

: > "$FAKE_LOG"
set +e
(
    cd "$INSTANCE_DIR"
    env ORG="$ORG" HOME="$HOME" PATH="$PATH" \
        "$SCRIPT_DIR/docker-dev.sh" build --model Bun --target mismatch -y \
        >"${TEST_ROOT}/build-mismatch.out" 2>&1
)
status=$?
set -e
[[ "$status" -ne 0 ]] || fail "build accepted a model conflicting with its instance tag"
grep -q 'does not match instance model' "${TEST_ROOT}/build-mismatch.out" ||
    fail "model conflict diagnostic was not explicit"
[[ ! -s "$FAKE_LOG" ]] || fail "model conflict reached Docker before failing"

mkdir -p "${INSTANCE_DIR}/project-tag-mismatch/.docker-dev" \
    "${INSTANCE_DIR}/project-tag-malformed/.docker-dev"
printf 'schema_version=1\nmodel=Bun\n' \
    > "${INSTANCE_DIR}/project-tag-mismatch/.docker-dev/project-tag"
printf 'schema_version=99\nmodel=Python\n' \
    > "${INSTANCE_DIR}/project-tag-malformed/.docker-dev/project-tag"
for invalid_project in project-tag-mismatch project-tag-malformed; do
    : > "$FAKE_LOG"
    set +e
    (
        cd "$INSTANCE_DIR"
        env ORG="$ORG" HOME="$HOME" PATH="$PATH" \
            "$SCRIPT_DIR/docker-dev.sh" build --target "$invalid_project" -y \
            >"${TEST_ROOT}/${invalid_project}.out" 2>&1
    )
    status=$?
    set -e
    [[ "$status" -ne 0 ]] || fail "build accepted $invalid_project"
    [[ ! -s "$FAKE_LOG" ]] || fail "build with $invalid_project reached Docker before failing"
done
grep -q 'does not match instance model' "${TEST_ROOT}/project-tag-mismatch.out" ||
    fail "project tag mismatch diagnostic was not explicit"
grep -q 'unsupported project tag schema_version' "${TEST_ROOT}/project-tag-malformed.out" ||
    fail "malformed project tag diagnostic was not explicit"

EXTERNAL_ROOT="${TEST_ROOT}/external"
EXTERNAL_PROJECT="${EXTERNAL_ROOT}/tagged-project"
EXTERNAL_NO_TAG="${EXTERNAL_ROOT}/untagged-project"
mkdir -p "${EXTERNAL_ROOT}/.docker-dev" "$EXTERNAL_PROJECT/.docker-dev" "$EXTERNAL_NO_TAG"
printf 'schema_version=1\nmodel=Bun\n' > "${EXTERNAL_ROOT}/.docker-dev/instance-tag"
printf 'schema_version=1\nmodel=Perl\n' > "$EXTERNAL_PROJECT/.docker-dev/project-tag"
env ORG="$ORG" HOME="$HOME" PATH="$PATH" \
    "$SCRIPT_DIR/docker-dev.sh" build --target "$EXTERNAL_PROJECT" -y \
    >"${TEST_ROOT}/build-external-tagged.out" 2>&1 ||
    fail "external absolute target did not use its project tag: $(cat "${TEST_ROOT}/build-external-tagged.out")"
grep -q 'Project Model  : Perl' "${TEST_ROOT}/build-external-tagged.out" ||
    fail "external absolute target used its ancestor instance tag"

: > "$FAKE_LOG"
set +e
env ORG="$ORG" HOME="$HOME" PATH="$PATH" \
    "$SCRIPT_DIR/docker-dev.sh" build --target "$EXTERNAL_NO_TAG" -y \
    >"${TEST_ROOT}/build-external-no-model.out" 2>&1
status=$?
set -e
[[ "$status" -ne 0 ]] || fail "external target inferred a model from an ancestor instance tag"
grep -q 'model cannot be inferred' "${TEST_ROOT}/build-external-no-model.out" ||
    fail "external target without a project tag did not explain model inference failure"
[[ ! -s "$FAKE_LOG" ]] || fail "external target without a model reached Docker"

rm -f "${FAKE_IMAGES}/dev.python"
: > "$FAKE_LOG"
env ORG="$ORG" HOME="$HOME" PATH="$PATH" \
    "$SCRIPT_DIR/docker-dev.sh" build --model Python --target basic -y \
    >"${TEST_ROOT}/build.out" 2>&1 ||
    fail "build command failed: $(cat "${TEST_ROOT}/build.out")"

[[ -f "${PROJECT_DIR}/.docker-dev/project-tag" ]] ||
    fail "successful build did not write a project tag"
[[ "$(cat "${PROJECT_DIR}/.docker-dev/project-tag")" == $'schema_version=1\nmodel=Python' ]] ||
    fail "build wrote unexpected project tag content"
grep -q '^build ' "$FAKE_LOG" || fail "build command did not build an image"
if grep -q '^run ' "$FAKE_LOG"; then
    fail "build without -x unexpectedly ran the container"
fi

DEFAULT_PROJECT="${TEST_ROOT}/default-build"
mkdir -p "$DEFAULT_PROJECT"
(
    cd "$DEFAULT_PROJECT"
    env ORG="$ORG" HOME="$HOME" PATH="$PATH" \
        "$SCRIPT_DIR/docker-dev.sh" build --lang Python -y \
        >"${TEST_ROOT}/build-default-target.out" 2>&1
) || fail "build without --target did not use the current directory: $(cat "${TEST_ROOT}/build-default-target.out")"
[[ "$(cat "${DEFAULT_PROJECT}/.docker-dev/project-tag")" == $'schema_version=1\nmodel=Python' ]] ||
    fail "build without --target did not tag the current directory"

: > "$FAKE_LOG"
(
    cd "${PROJECT_BASE}/Python"
    printf 'Y' | env ORG="$ORG" HOME="$HOME" PATH="$PATH" \
        "$SCRIPT_DIR/docker-dev.sh" run --target basic \
        >"${TEST_ROOT}/run.out" 2>&1
) || fail "run command failed: $(cat "${TEST_ROOT}/run.out")"
grep -q '^run ' "$FAKE_LOG" || fail "run command did not run a container"
if grep -q '^build ' "$FAKE_LOG"; then
    fail "run command implicitly built an image"
fi

mkdir -p "${PROJECT_BASE}/Perl/basic/.docker-dev"
printf 'schema_version=1\nlang=Perl\n' > "${PROJECT_BASE}/Perl/basic/.docker-dev/project-tag"
: > "$FAKE_LOG"
set +e
env ORG="$ORG" HOME="$HOME" PATH="$PATH" \
    "$SCRIPT_DIR/docker-dev.sh" run --target basic \
    >"${TEST_ROOT}/missing-local-target.out" 2>&1
status=$?
set -e
[[ "$status" -ne 0 ]] || fail "run succeeded for a target absent from the current directory"
grep -q 'does not exist under the current directory' "${TEST_ROOT}/missing-local-target.out" ||
    fail "missing local target diagnostic was not explicit"
[[ ! -s "$FAKE_LOG" ]] || fail "missing local target contacted Docker or searched globally"

mkdir -p "${PROJECT_BASE}/Bun/bar"
: > "$FAKE_LOG"
(
    cd "${PROJECT_BASE}/Bun"
    touch "${FAKE_IMAGES}/dev.bun"
    printf 'Y' | env ORG="$ORG" HOME="$HOME" PATH="$PATH" \
        "$SCRIPT_DIR/docker-dev.sh" run --target bar \
        >"${TEST_ROOT}/local-priority.out" 2>&1
) || fail "run did not prioritize a local legacy project: $(cat "${TEST_ROOT}/local-priority.out")"
grep -q '^run ' "$FAKE_LOG" || fail "local target match did not run a container"
grep -q 'Project Model  : Bun' "${TEST_ROOT}/local-priority.out" ||
    fail "local project model was not inferred from current model directory"

: > "$FAKE_LOG"
rm -f "${FAKE_IMAGES}/dev.python"
env ORG="$ORG" HOME="$HOME" PATH="$PATH" \
    "$SCRIPT_DIR/docker-dev.sh" build --model Python --target with-run -x -y \
    >"${TEST_ROOT}/build-run.out" 2>&1 ||
    fail "build -x command failed: $(cat "${TEST_ROOT}/build-run.out")"
[[ -f "${PROJECT_BASE}/Python/with-run/.docker-dev/project-tag" ]] ||
    fail "build -x did not write project tag"
grep -q '^run ' "$FAKE_LOG" || fail "build -x did not run container"
build_line="$(grep -n '^build ' "$FAKE_LOG" | head -n 1 | cut -d: -f1)"
run_line="$(grep -n '^run ' "$FAKE_LOG" | head -n 1 | cut -d: -f1)"
[[ -n "$build_line" && -n "$run_line" && "$build_line" -lt "$run_line" ]] ||
    fail "build -x did not build before running"

: > "$FAKE_LOG"
rm -f "${FAKE_IMAGES}/dev.python"
set +e
(
    cd "${PROJECT_BASE}/Python"
    printf 'Y' | env ORG="$ORG" HOME="$HOME" PATH="$PATH" \
        "$SCRIPT_DIR/docker-dev.sh" run --target with-run \
        >"${TEST_ROOT}/missing-image.out" 2>&1
)
status=$?
set -e
[[ "$status" -ne 0 ]] || fail "run succeeded without its image"
grep -q 'not available locally' "${TEST_ROOT}/missing-image.out" ||
    fail "missing-image failure did not explain the problem"
if grep -qE '^(build|run|volume) ' "$FAKE_LOG"; then
    fail "run with missing image performed build/run side effects"
fi

rm -f "${FAKE_IMAGES}/dev.python"
: > "$FAKE_LOG"
set +e
env ORG="$ORG" HOME="$HOME" PATH="$PATH" DDEV_TEST_FAIL_BUILD=1 \
    "$SCRIPT_DIR/docker-dev.sh" build --model Python --target failed-build -x -y \
    >"${TEST_ROOT}/failed-build.out" 2>&1
status=$?
set -e
[[ "$status" -ne 0 ]] || fail "build unexpectedly succeeded with failing docker build"
[[ ! -e "${PROJECT_BASE}/Python/failed-build/.docker-dev/project-tag" ]] ||
    fail "failed build wrote a project tag"
if grep -q '^run ' "$FAKE_LOG"; then
    fail "build -x ran the container after a failed build"
fi

(
    cd "$PROJECT_DIR"
    touch "${FAKE_IMAGES}/dev.python"
    printf 'Y' | env ORG="$ORG" HOME="$HOME" PATH="$PATH" \
        "$SCRIPT_DIR/docker-dev.sh" run \
        >"${TEST_ROOT}/run-pwd.out" 2>&1
) || fail "run without --target did not use tagged current directory: $(cat "${TEST_ROOT}/run-pwd.out")"

: > "$FAKE_LOG"
set +e
env ORG="$ORG" HOME="$HOME" PATH="$PATH" \
    "$SCRIPT_DIR/docker-dev.sh" "--target=${PROJECT_DIR}" \
    >"${TEST_ROOT}/removed-legacy-invocation.out" 2>&1
status=$?
set -e
[[ "$status" -ne 0 ]] || fail "legacy invocation without a subcommand was accepted"
grep -q 'unknown command' "${TEST_ROOT}/removed-legacy-invocation.out" ||
    fail "invocation without a subcommand did not report the command error"
[[ ! -s "$FAKE_LOG" ]] || fail "legacy invocation contacted Docker"

: > "$FAKE_LOG"
set +e
env ORG="$ORG" HOME="$HOME" PATH="$PATH" \
    "$SCRIPT_DIR/docker-dev.sh" build --model Python --target "$PROJECT_DIR" --penv QA \
    >"${TEST_ROOT}/removed-penv.out" 2>&1
status=$?
set -e
[[ "$status" -ne 0 ]] || fail "--penv was accepted by build"
grep -q 'unknown argument for build: --penv' "${TEST_ROOT}/removed-penv.out" ||
    fail "removed --penv did not report an explicit parser error"
[[ ! -s "$FAKE_LOG" ]] || fail "build with removed --penv contacted Docker"

printf 'docker-dev operation integration tests passed\n'
