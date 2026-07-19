#!/usr/bin/env bash
# shellcheck disable=SC2016

set -euo pipefail

PROJECT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/kanboard-md-rpc.XXXXXX")
trap 'rm -rf "$TEST_DIR"' EXIT

mkdir -p "$TEST_DIR/bin"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'case "$MOCK_RESPONSE" in' \
  '  invalid-json) printf '\''{not json\n'\'' ;;' \
  '  api-error) printf '\''{"jsonrpc":"2.0","error":{"message":"Denied"},"id":1}\n'\'' ;;' \
  '  invalid-rpc) printf '\''[]\n'\'' ;;' \
  '  wrong-type) printf '\''{"jsonrpc":"2.0","result":{},"error":null,"id":1}\n'\'' ;;' \
  '  missing) printf '\''{"jsonrpc":"2.0","result":false,"error":null,"id":1}\n'\'' ;;' \
  'esac' \
  >"$TEST_DIR/bin/curl"
chmod +x "$TEST_DIR/bin/curl"

printf '%s\n' \
  '{"url":"https://kanboard.invalid","username":"test-user","apiToken":"test-token"}' \
  >"$TEST_DIR/config.json"
chmod 600 "$TEST_DIR/config.json"

assert_failure() {
  local response=$1
  local expected=$2
  shift 2

  if MOCK_RESPONSE="$response" PATH="$TEST_DIR/bin:$PATH" \
    "$PROJECT_DIR/kanboard-md" --config "$TEST_DIR/config.json" "$@" \
    >"$TEST_DIR/stdout" 2>"$TEST_DIR/stderr"; then
    echo "$response unexpectedly succeeded" >&2
    exit 1
  fi

  if [[ $(<"$TEST_DIR/stderr") != *"$expected"* ]]; then
    echo "$response did not report: $expected" >&2
    exit 1
  fi
}

assert_failure invalid-json "invalid JSON response from getMyProjects" boards
assert_failure api-error "Denied" boards
assert_failure invalid-rpc "Invalid JSON-RPC response" boards
assert_failure wrong-type "expected array, got object" boards
assert_failure missing "board 3 was not found" board 3
assert_failure missing "task 63 was not found" task 63

echo "rpc tests passed"
