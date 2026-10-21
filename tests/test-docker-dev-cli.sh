#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "${SCRIPT_DIR}/docker-dev-cli.sh"

assert_parse() {
    local expected_status="$1"
    local expected_operation="$2"
    local expected_model="$3"
    local expected_target="$4"
    local expected_x="$5"
    local expected_y="$6"
    shift 6

    local actual_status=0
    ddev_cli_parse "$@" || actual_status=$?

    if [[ "$actual_status" != "$expected_status" ||
          "$DDEV_OPERATION" != "$expected_operation" ||
          "$DDEV_MODEL" != "$expected_model" ||
          "$DDEV_TARGET" != "$expected_target" ||
          "$DDEV_BUILD_AND_RUN" != "$expected_x" ||
          "$DDEV_ASSUME_YES" != "$expected_y" ]]; then
        printf 'FAIL: args:' >&2
        printf ' %q' "$@" >&2
        printf '\n  status=%s operation=%s model=%s target=%s x=%s y=%s error=%s\n' \
            "$actual_status" "$DDEV_OPERATION" "$DDEV_MODEL" "$DDEV_TARGET" \
            "$DDEV_BUILD_AND_RUN" "$DDEV_ASSUME_YES" "$DDEV_PARSE_ERROR" >&2
        exit 1
    fi
}

assert_parse 2 "" "" "" 0 0
assert_parse 2 "" "" "" 0 0 --target=Python/foo
assert_parse 2 "" "" "" 0 0 --penv=QA
assert_parse 0 build "" foo/bar 0 0 build --target foo/bar
assert_parse 0 build Python foo/bar 1 1 build --model Python --target foo/bar -x -y
assert_parse 0 build Python foo/bar 0 0 build --model=Python --target=foo/bar
assert_parse 0 build Perl "" 0 0 build --lang Perl
assert_parse 0 run "" foo/bar 0 0 run --target foo/bar
assert_parse 0 run "" "" 0 0 run
assert_parse 0 build "" "" 0 0 build --help
assert_parse 0 tag Bun instance-dir 0 0 tag --model Bun --target instance-dir
assert_parse 0 tag Bun "" 0 0 tag --model=Bun
assert_parse 0 info "" "" 0 0 info --tag
[[ "$DDEV_INFO_TAG" -eq 1 ]] || { printf 'FAIL: info --tag was not parsed\n' >&2; exit 1; }

assert_parse 2 build Python "" 0 0 build --model Python --lang Perl
assert_parse 2 build Python "" 0 0 build --model Python --x
assert_parse 2 build "" "" 0 0 build --penv QA
assert_parse 2 run "" "" 0 0 run --model Python
assert_parse 2 run "" "" 0 0 run -x
assert_parse 2 build Python "" 0 0 build --model Python --target=
assert_parse 2 tag "" "" 0 0 tag
assert_parse 2 info "" "" 0 0 info
assert_parse 2 info "" "" 0 0 info --tag --target foo

printf 'docker-dev CLI parser tests passed\n'
