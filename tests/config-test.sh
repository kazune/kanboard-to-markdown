#!/usr/bin/env bash
# shellcheck disable=SC2016

set -euo pipefail

PROJECT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/kanboard-md-test.XXXXXX")
trap 'rm -rf "$TEST_DIR"' EXIT

mkdir -p "$TEST_DIR/bin"

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'if [[ -n "${CURL_ARGS_FILE:-}" ]]; then printf '\''%s\n'\'' "$*" >"$CURL_ARGS_FILE"; fi' \
  'printf '\''{"result":[],"error":null}\n'\''' \
  >"$TEST_DIR/bin/curl"
chmod +x "$TEST_DIR/bin/curl"

run_command() {
  PATH="$TEST_DIR/bin:/usr/bin:/bin" \
    "$PROJECT_DIR/kanboard-md" --config "$1" boards
}

# --config is required.
if PATH="$TEST_DIR/bin:/usr/bin:/bin" \
  "$PROJECT_DIR/kanboard-md" boards >/dev/null 2>&1; then
  echo "command without --config unexpectedly succeeded" >&2
  exit 1
fi

# An explicitly specified relative JSON config is loaded successfully.
mkdir -p "$TEST_DIR/relative"
printf '%s\n' \
  '{' \
  '  "url": "https://relative.invalid",' \
  '  "username": "relative-user",' \
  '  "apiToken": "relative-token"' \
  '}' \
  >"$TEST_DIR/relative/config.json"
chmod 600 "$TEST_DIR/relative/config.json"
(
  cd "$TEST_DIR/relative"
  run_command config.json
) >/dev/null

# Group-readable files are rejected.
mkdir -p "$TEST_DIR/insecure"
printf '%s\n' \
  '{"url":"https://insecure.invalid","username":"insecure-user","apiToken":"insecure-token"}' \
  >"$TEST_DIR/insecure/config.json"
chmod 640 "$TEST_DIR/insecure/config.json"
if run_command "$TEST_DIR/insecure/config.json" >/dev/null 2>&1; then
  echo "insecure config unexpectedly succeeded" >&2
  exit 1
fi

# Shell syntax is rejected as data and never executed.
mkdir -p "$TEST_DIR/shell"
printf '%s\n' \
  'touch "$CONFIG_MARKER"' \
  'KANBOARD_URL=https://shell.invalid' \
  >"$TEST_DIR/shell/config.json"
chmod 600 "$TEST_DIR/shell/config.json"
if CONFIG_MARKER="$TEST_DIR/shell-marker" \
  run_command "$TEST_DIR/shell/config.json" >/dev/null 2>&1; then
  echo "shell config unexpectedly succeeded" >&2
  exit 1
fi
if [[ -e "$TEST_DIR/shell-marker" ]]; then
  echo "shell config was executed" >&2
  exit 1
fi

# Credential environment variables are ignored in favor of the config file.
mkdir -p "$TEST_DIR/environment"
printf '%s\n' \
  '{"url":"https://config.invalid","username":"config-user","apiToken":"config-token"}' \
  >"$TEST_DIR/environment/config.json"
chmod 600 "$TEST_DIR/environment/config.json"
KANBOARD_URL=https://environment.invalid \
KANBOARD_USERNAME=environment-user \
KANBOARD_API_TOKEN=environment-token \
CURL_ARGS_FILE="$TEST_DIR/curl-args" \
  run_command "$TEST_DIR/environment/config.json" >/dev/null
curl_args=$(<"$TEST_DIR/curl-args")
if [[ "$curl_args" != *"config-user:config-token"* ||
      "$curl_args" != *"https://config.invalid/jsonrpc.php"* ]]; then
  echo "credential environment variables were not ignored" >&2
  exit 1
fi

# An environment variable cannot fill a value missing from the config file.
mkdir -p "$TEST_DIR/missing"
printf '%s\n' \
  '{"url":"https://missing.invalid","username":"missing-user"}' \
  >"$TEST_DIR/missing/config.json"
chmod 600 "$TEST_DIR/missing/config.json"
if KANBOARD_API_TOKEN=environment-token \
  run_command "$TEST_DIR/missing/config.json" >/dev/null 2>&1; then
  echo "environment variable filled missing config unexpectedly" >&2
  exit 1
fi

echo "config tests passed"
