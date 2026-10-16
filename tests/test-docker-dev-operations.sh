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

env ORG="$ORG" HOME="$HOME" PATH="$PATH" \
    "$SCRIPT_DIR/docker-dev.sh" build --lang Python --target basic -y \
    >"${TEST_ROOT}/build.out" 2>&1 ||
    fail "build command failed: $(cat "${TEST_ROOT}/build.out")"

[[ -f "${PROJECT_DIR}/.docker-dev/project-tag" ]] ||
    fail "successful build did not write a project tag"
[[ "$(cat "${PROJECT_DIR}/.docker-dev/project-tag")" == $'schema_version=1\nlang=Python' ]] ||
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
[[ "$(cat "${DEFAULT_PROJECT}/.docker-dev/project-tag")" == $'schema_version=1\nlang=Python' ]] ||
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
grep -q 'Project Type   : Bun' "${TEST_ROOT}/local-priority.out" ||
    fail "local project language was not inferred from current language directory"

: > "$FAKE_LOG"
rm -f "${FAKE_IMAGES}/dev.python"
env ORG="$ORG" HOME="$HOME" PATH="$PATH" \
    "$SCRIPT_DIR/docker-dev.sh" build --lang Python --target with-run -x -y \
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
    "$SCRIPT_DIR/docker-dev.sh" build --lang Python --target failed-build -x -y \
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
printf 'Y' | env ORG="$ORG" HOME="$HOME" PATH="$PATH" \
    "$SCRIPT_DIR/docker-dev.sh" "--target=${PROJECT_DIR}" \
    >"${TEST_ROOT}/legacy.out" 2>&1 ||
    fail "legacy invocation failed: $(cat "${TEST_ROOT}/legacy.out")"
grep -q '^run ' "$FAKE_LOG" || fail "legacy invocation no longer ran the full pipeline"
grep -q 'Image dev.python already exists' "${TEST_ROOT}/legacy.out" ||
    fail "legacy invocation did not preserve its image reuse behavior"

printf 'docker-dev operation integration tests passed\n'
