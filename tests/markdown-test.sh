#!/usr/bin/env bash
# shellcheck disable=SC2016

set -euo pipefail

PROJECT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
FIXTURE_DIR="$PROJECT_DIR/tests/fixtures"
EXPECTED_DIR="$PROJECT_DIR/tests/expected"
TEST_DIR=${TEST_DIR_OVERRIDE:-$(mktemp -d "${TMPDIR:-/tmp}/kanboard-md-markdown.XXXXXX")}

if [[ -z "${KEEP_TEST_OUTPUT:-}" ]]; then
  trap 'rm -rf "$TEST_DIR"' EXIT
fi

mkdir -p "$TEST_DIR/bin"
JQ_BIN=$(command -v jq)
export FIXTURE_DIR JQ_BIN

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'request_file=' \
  'for argument in "$@"; do' \
  '  case "$argument" in @*) request_file=${argument#@} ;; esac' \
  'done' \
  'method=$("$JQ_BIN" -r '\''.method'\'' "$request_file")' \
  'fixture="$FIXTURE_DIR/$method.json"' \
  '"$JQ_BIN" -cn --slurpfile result "$fixture" '\''{jsonrpc:"2.0",result:$result[0],error:null}'\''' \
  >"$TEST_DIR/bin/curl"
chmod +x "$TEST_DIR/bin/curl"

printf '%s\n' \
  '{' \
  '  "url": "https://kanboard.invalid",' \
  '  "username": "test-user",' \
  '  "apiToken": "test-token"' \
  '}' \
  >"$TEST_DIR/config.json"
chmod 600 "$TEST_DIR/config.json"

for command in boards board task; do
  case "$command" in
    boards) arguments=(boards) ;;
    board) arguments=(board 3) ;;
    task) arguments=(task 63) ;;
  esac

  PATH="$TEST_DIR/bin:$PATH" \
    "$PROJECT_DIR/kanboard-md" --config "$TEST_DIR/config.json" "${arguments[@]}" \
    >"$TEST_DIR/$command.md"
  diff -u "$EXPECTED_DIR/$command.md" "$TEST_DIR/$command.md"
done

echo "markdown tests passed"
