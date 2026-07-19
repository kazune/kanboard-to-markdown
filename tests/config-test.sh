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
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'if [[ " $* " == *" has(\"result\") "* ]]; then exit 0; fi' \
  'if [[ " $* " == *" .result "* ]]; then printf '\''[]\n'\''; fi' \
  >"$TEST_DIR/bin/jq"
chmod +x "$TEST_DIR/bin/curl" "$TEST_DIR/bin/jq"

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

# An explicitly specified relative config is sourced successfully.
mkdir -p "$TEST_DIR/relative"
printf '%s\n' \
  'touch "$CONFIG_MARKER"' \
  'KANBOARD_URL=https://relative.invalid' \
  'KANBOARD_USERNAME=relative-user' \
  'KANBOARD_API_TOKEN=relative-token' \
  >"$TEST_DIR/relative/config.env"
chmod 600 "$TEST_DIR/relative/config.env"
(
  cd "$TEST_DIR/relative"
  CONFIG_MARKER="$TEST_DIR/relative-marker" run_command config.env
) >/dev/null
[[ -e "$TEST_DIR/relative-marker" ]]

# Group-readable files are rejected before any commands in them execute.
mkdir -p "$TEST_DIR/insecure"
printf '%s\n' \
  'touch "$CONFIG_MARKER"' \
  'KANBOARD_URL=https://insecure.invalid' \
  'KANBOARD_USERNAME=insecure-user' \
  'KANBOARD_API_TOKEN=insecure-token' \
  >"$TEST_DIR/insecure/config.env"
chmod 640 "$TEST_DIR/insecure/config.env"
if CONFIG_MARKER="$TEST_DIR/insecure-marker" \
  run_command "$TEST_DIR/insecure/config.env" >/dev/null 2>&1; then
  echo "insecure config unexpectedly succeeded" >&2
  exit 1
fi
if [[ -e "$TEST_DIR/insecure-marker" ]]; then
  echo "insecure config was sourced" >&2
  exit 1
fi

# Credential environment variables are ignored in favor of the config file.
mkdir -p "$TEST_DIR/environment"
printf '%s\n' \
  'KANBOARD_URL=https://config.invalid' \
  'KANBOARD_USERNAME=config-user' \
  'KANBOARD_API_TOKEN=config-token' \
  >"$TEST_DIR/environment/config.env"
chmod 600 "$TEST_DIR/environment/config.env"
KANBOARD_URL=https://environment.invalid \
KANBOARD_USERNAME=environment-user \
KANBOARD_API_TOKEN=environment-token \
CURL_ARGS_FILE="$TEST_DIR/curl-args" \
  run_command "$TEST_DIR/environment/config.env" >/dev/null
curl_args=$(<"$TEST_DIR/curl-args")
if [[ "$curl_args" != *"config-user:config-token"* ||
      "$curl_args" != *"https://config.invalid/jsonrpc.php"* ]]; then
  echo "credential environment variables were not ignored" >&2
  exit 1
fi

# An environment variable cannot fill a value missing from the config file.
mkdir -p "$TEST_DIR/missing"
printf '%s\n' \
  'KANBOARD_URL=https://missing.invalid' \
  'KANBOARD_USERNAME=missing-user' \
  >"$TEST_DIR/missing/config.env"
chmod 600 "$TEST_DIR/missing/config.env"
if KANBOARD_API_TOKEN=environment-token \
  run_command "$TEST_DIR/missing/config.env" >/dev/null 2>&1; then
  echo "environment variable filled missing config unexpectedly" >&2
  exit 1
fi

echo "config tests passed"
