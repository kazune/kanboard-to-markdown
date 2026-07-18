#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

usage() {
  echo "Usage: $0 <board_id>" >&2
}

if [[ $# -ne 1 || ! "$1" =~ ^[1-9][0-9]*$ ]]; then
  usage
  exit 1
fi

BOARD_ID=$1

# 環境変数が未設定の場合は、スクリプトと同じ場所の .env を読み込む。
if [[ -f "$SCRIPT_DIR/.env" ]] &&
   [[ -z "${KANBOARD_URL:-}" || -z "${KANBOARD_USERNAME:-}" || -z "${KANBOARD_API_TOKEN:-}" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/.env"
  set +a
fi

: "${KANBOARD_URL:?KANBOARD_URL is required}"
: "${KANBOARD_USERNAME:?KANBOARD_USERNAME is required}"
: "${KANBOARD_API_TOKEN:?KANBOARD_API_TOKEN is required}"

for command_name in curl jq; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Error: $command_name is required." >&2
    exit 1
  fi
done

TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/kanboard-to-md.XXXXXX")
trap 'rm -rf "$TMP_DIR"' EXIT

rpc() {
  local method=$1
  local params=$2
  local destination=$3
  local request_file="$TMP_DIR/request.json"
  local response_file="$TMP_DIR/response.json"

  jq -n \
    --arg method "$method" \
    --argjson params "$params" \
    '{jsonrpc: "2.0", method: $method, id: 1, params: $params}' \
    >"$request_file"

  curl -fsS \
    -u "$KANBOARD_USERNAME:$KANBOARD_API_TOKEN" \
    -H "Content-Type: application/json" \
    --data-binary "@$request_file" \
    "${KANBOARD_URL%/}/jsonrpc.php" \
    >"$response_file"

  if ! jq -e 'has("result") and (.error == null)' "$response_file" >/dev/null; then
    echo "Kanboard API error in $method:" >&2
    jq -r 'if .error then (.error.message // (.error | tostring)) else "Invalid JSON-RPC response" end' \
      "$response_file" >&2
    exit 1
  fi

  jq '.result' "$response_file" >"$destination"
}

PARAMS=$(jq -cn --argjson project_id "$BOARD_ID" '{project_id: $project_id}')
rpc "getProjectById" "$PARAMS" "$TMP_DIR/project.json"
rpc "getBoard" "$PARAMS" "$TMP_DIR/board.json"

render_markdown() {
  jq -nr \
    --slurpfile project "$TMP_DIR/project.json" \
    --slurpfile board "$TMP_DIR/board.json" '
      def text:
        if . == null then "" else tostring | gsub("[\\r\\n]+"; " ") end;

      def due_date:
        if . == null or . == "" or . == 0 or . == "0" then null
        elif type == "number" then strftime("%Y-%m-%d")
        elif test("^[0-9]+$") then tonumber | strftime("%Y-%m-%d")
        else text
        end;

      ($project[0]) as $p |
      ($board[0]) as $swimlanes |

      "# " + ($p.name | text),
      "",
      "- プロジェクトID: " + ($p.id | text),
      "- 状態: " + (if ($p.is_active | tostring) == "1" then "有効" else "無効" end),
      (if ($p.description // "") != "" then
        "- 説明: " + ($p.description | text)
       else empty end),
      "",
      ($swimlanes[] |
        . as $swimlane |
        "## " + ($swimlane.name | text),
        "",
        ($swimlane.columns | sort_by(.position | tonumber)[] |
          . as $column |
          (($column.tasks // []) | sort_by(.position | tonumber)) as $column_tasks |
          "### " + ($column.title | text) + " (" + ($column_tasks | length | tostring) + ")",
          (if (($column.task_limit // 0) | tonumber) > 0 then
            "",
            "タスク上限: " + ($column.task_limit | text)
           else empty end),
          "",
          (if ($column_tasks | length) == 0 then
            "_タスクなし_"
           else
            ($column_tasks[] |
              . as $task |
              ([
                (if ($task.assignee_name // "") != "" then "担当: " + ($task.assignee_name | text)
                 elif ($task.assignee_username // "") != "" then "担当: " + ($task.assignee_username | text)
                 else empty end),
                (if ($task.category_name // "") != "" then "カテゴリ: " + ($task.category_name | text) else empty end),
                (($task.date_due | due_date) as $due | if $due then "期限: " + $due else empty end),
                (if ($task.score // 0 | tonumber) > 0 then "複雑度: " + ($task.score | text) else empty end)
              ] | join(" / ")) as $meta |
              "- #" + ($task.id | text) + " " + ($task.title | text) +
              (if $meta != "" then " — " + $meta else "" end)
            )
          end),
          ""
        )
      )
    '
}

render_markdown
