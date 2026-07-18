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
  env -u KANBOARD_URL -u KANBOARD_USERNAME -u KANBOARD_API_TOKEN \
    PATH="$TEST_DIR/bin:/usr/bin:/bin" \
    "$PROJECT_DIR/kanboard-md" boards
}

# Relative XDG_CONFIG_HOME values must not cause a config file in the current
# directory to be sourced.
mkdir -p "$TEST_DIR/relative/kanboard-md"
printf '%s\n' \
  'touch "$CONFIG_MARKER"' \
  'KANBOARD_URL=https://relative.invalid' \
  'KANBOARD_USERNAME=relative-user' \
  'KANBOARD_API_TOKEN=relative-token' \
  >"$TEST_DIR/relative/kanboard-md/config.env"
chmod 600 "$TEST_DIR/relative/kanboard-md/config.env"
if (
  cd "$TEST_DIR/relative"
  CONFIG_MARKER="$TEST_DIR/relative-marker" XDG_CONFIG_HOME=. HOME='' run_command
) >/dev/null 2>&1; then
  echo "relative XDG_CONFIG_HOME unexpectedly succeeded" >&2
  exit 1
fi
if [[ -e "$TEST_DIR/relative-marker" ]]; then
  echo "relative XDG_CONFIG_HOME was sourced" >&2
  exit 1
fi

# A secure config under an absolute XDG_CONFIG_HOME is sourced successfully.
mkdir -p "$TEST_DIR/absolute/kanboard-md"
printf '%s\n' \
  'touch "$CONFIG_MARKER"' \
  'KANBOARD_URL=https://absolute.invalid' \
  'KANBOARD_USERNAME=absolute-user' \
  'KANBOARD_API_TOKEN=absolute-token' \
  >"$TEST_DIR/absolute/kanboard-md/config.env"
chmod 600 "$TEST_DIR/absolute/kanboard-md/config.env"
CONFIG_MARKER="$TEST_DIR/absolute-marker" XDG_CONFIG_HOME="$TEST_DIR/absolute" HOME='' \
  run_command >/dev/null
[[ -e "$TEST_DIR/absolute-marker" ]]

# Group-readable files are rejected before any commands in them execute.
mkdir -p "$TEST_DIR/insecure/kanboard-md"
printf '%s\n' \
  'touch "$CONFIG_MARKER"' \
  'KANBOARD_URL=https://insecure.invalid' \
  'KANBOARD_USERNAME=insecure-user' \
  'KANBOARD_API_TOKEN=insecure-token' \
  >"$TEST_DIR/insecure/kanboard-md/config.env"
chmod 640 "$TEST_DIR/insecure/kanboard-md/config.env"
if CONFIG_MARKER="$TEST_DIR/insecure-marker" XDG_CONFIG_HOME="$TEST_DIR/insecure" HOME='' \
  run_command >/dev/null 2>&1; then
  echo "insecure config unexpectedly succeeded" >&2
  exit 1
fi
if [[ -e "$TEST_DIR/insecure-marker" ]]; then
  echo "insecure config was sourced" >&2
  exit 1
fi

# Existing credential variables override values from the config, while a
# missing credential is filled from it.
mkdir -p "$TEST_DIR/priority/kanboard-md"
printf '%s\n' \
  'KANBOARD_URL=https://config.invalid' \
  'KANBOARD_USERNAME=config-user' \
  'KANBOARD_API_TOKEN=config-token' \
  >"$TEST_DIR/priority/kanboard-md/config.env"
chmod 600 "$TEST_DIR/priority/kanboard-md/config.env"
KANBOARD_URL=https://environment.invalid \
KANBOARD_USERNAME=environment-user \
XDG_CONFIG_HOME="$TEST_DIR/priority" \
HOME='' \
CURL_ARGS_FILE="$TEST_DIR/curl-args" \
PATH="$TEST_DIR/bin:/usr/bin:/bin" \
  "$PROJECT_DIR/kanboard-md" boards >/dev/null
curl_args=$(<"$TEST_DIR/curl-args")
if [[ "$curl_args" != *"environment-user:config-token"* ||
      "$curl_args" != *"https://environment.invalid/jsonrpc.php"* ]]; then
  echo "environment credentials did not take priority" >&2
  exit 1
fi

echo "config tests passed"
