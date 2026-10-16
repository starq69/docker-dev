#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "${SCRIPT_DIR}/docker-dev-cli.sh"

assert_parse() {
    local expected_status="$1"
    local expected_operation="$2"
    local expected_lang="$3"
    local expected_target="$4"
    local expected_x="$5"
    local expected_y="$6"
    shift 6

    local actual_status=0
    ddev_cli_parse "$@" || actual_status=$?

    if [[ "$actual_status" != "$expected_status" ||
          "$DDEV_OPERATION" != "$expected_operation" ||
          "$DDEV_LANG" != "$expected_lang" ||
          "$DDEV_TARGET" != "$expected_target" ||
          "$DDEV_BUILD_AND_RUN" != "$expected_x" ||
          "$DDEV_ASSUME_YES" != "$expected_y" ]]; then
        printf 'FAIL: args:' >&2
        printf ' %q' "$@" >&2
        printf '\n  status=%s operation=%s lang=%s target=%s x=%s y=%s error=%s\n' \
            "$actual_status" "$DDEV_OPERATION" "$DDEV_LANG" "$DDEV_TARGET" \
            "$DDEV_BUILD_AND_RUN" "$DDEV_ASSUME_YES" "$DDEV_PARSE_ERROR" >&2
        exit 1
    fi
}

assert_parse 0 legacy "" "" 0 0 --target=Python/foo -i custom
assert_parse 0 build Python foo/bar 1 1 build --lang Python --target foo/bar -x -y
assert_parse 0 build Python foo/bar 0 0 build --lang=Python --target=foo/bar
assert_parse 0 run "" foo/bar 0 0 run --target foo/bar
assert_parse 0 run "" "" 0 0 run
assert_parse 0 build "" "" 0 0 build --help

assert_parse 2 build "" "" 0 0 build
[[ "$DDEV_PARSE_ERROR" == "build requires --lang" ]]
assert_parse 2 build Python "" 0 0 build --lang Python --x
assert_parse 2 run "" "" 0 0 run --lang Python
assert_parse 2 run "" "" 0 0 run -x
assert_parse 2 build Python "" 0 0 build --lang Python --target=

printf 'docker-dev CLI parser tests passed\n'
