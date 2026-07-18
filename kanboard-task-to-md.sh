#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

usage() {
  echo "Usage: $0 <task_id>" >&2
}

if [[ $# -ne 1 || ! "$1" =~ ^[1-9][0-9]*$ ]]; then
  usage
  exit 1
fi

TASK_ID=$1

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

TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/kanboard-task-to-md.XXXXXX")
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

TASK_PARAMS=$(jq -cn --argjson task_id "$TASK_ID" '{task_id: $task_id}')
rpc "getTask" "$TASK_PARAMS" "$TMP_DIR/task.json"

if ! jq -e 'type == "object"' "$TMP_DIR/task.json" >/dev/null; then
  echo "Error: task $TASK_ID was not found." >&2
  exit 1
fi

PROJECT_ID=$(jq -r '.project_id' "$TMP_DIR/task.json")
PROJECT_PARAMS=$(jq -cn --argjson project_id "$PROJECT_ID" '{project_id: $project_id}')

rpc "getProjectById" "$PROJECT_PARAMS" "$TMP_DIR/project.json"
rpc "getBoard" "$PROJECT_PARAMS" "$TMP_DIR/board.json"
rpc "getAllSubtasks" "$TASK_PARAMS" "$TMP_DIR/subtasks.json"
rpc "getAllComments" "$TASK_PARAMS" "$TMP_DIR/comments.json"

jq -nr \
  --arg task_id "$TASK_ID" \
  --slurpfile task "$TMP_DIR/task.json" \
  --slurpfile project "$TMP_DIR/project.json" \
  --slurpfile board "$TMP_DIR/board.json" \
  --slurpfile subtasks "$TMP_DIR/subtasks.json" \
  --slurpfile comments "$TMP_DIR/comments.json" '
    def text:
      if . == null then "" else tostring | gsub("[\\r\\n]+"; " ") end;

    def markdown:
      if . == null then "" else tostring | gsub("\\r\\n"; "\n") | gsub("\\r"; "\n") end;

    def present:
      . != null and . != "" and . != 0 and . != "0";

    def timestamp:
      if present then tonumber | strftime("%Y-%m-%d %H:%M UTC") else null end;

    def items:
      if type == "array" then . else [] end;

    ($task[0]) as $t |
    ($project[0]) as $p |
    ($subtasks[0] | items | sort_by(.position // .id | tonumber)) as $sts |
    ($comments[0] | items | sort_by(.date_creation | tonumber)) as $cs |
    ([
      $board[0][] as $swimlane |
      $swimlane.columns[] as $column |
      ($column.tasks // [])[] |
      select((.id | tostring) == $task_id) |
      . + {
        swimlane_name: $swimlane.name,
        column_name: $column.title
      }
    ] | first // {}) as $board_task |

    "# #" + ($t.id | text) + " " + ($t.title | text),
    "",
    "- 状態: " + (if ($t.is_active | tostring) == "1" then "有効" else "完了" end),
    "- プロジェクト: " + ($p.name // ("ID: " + ($t.project_id | text)) | text),
    "- スイムレーン: " +
      (if ($board_task.swimlane_name // "") != "" then $board_task.swimlane_name
       elif ($t.swimlane_id | tostring) == "0" then ($p.default_swimlane // "Default swimlane")
       else "ID: " + ($t.swimlane_id | text) end),
    "- 列: " + ($board_task.column_name // ("ID: " + ($t.column_id | text)) | text),
    "- 担当: " +
      (if ($board_task.assignee_name // "") != "" then ($board_task.assignee_name | text)
       elif ($board_task.assignee_username // "") != "" then ($board_task.assignee_username | text)
       elif ($t.owner_id | tostring) == "0" then "未割り当て"
       else "ユーザーID: " + ($t.owner_id | text) end),
    (if ($board_task.category_name // "") != "" then
      "- カテゴリ: " + ($board_task.category_name | text)
     elif ($t.category_id | tostring) != "0" then
      "- カテゴリID: " + ($t.category_id | text)
     else empty end),
    (if ($t.reference // "") != "" then "- 参照: " + ($t.reference | text) else empty end),
    (if ($t.priority // 0 | tonumber) > 0 then "- 優先度: " + ($t.priority | text) else empty end),
    (if ($t.score // 0 | tonumber) > 0 then "- 複雑度: " + ($t.score | text) else empty end),
    (if ($t.time_estimated // 0 | tonumber) > 0 then "- 見積時間: " + ($t.time_estimated | text) + "h" else empty end),
    (if ($t.time_spent // 0 | tonumber) > 0 then "- 作業時間: " + ($t.time_spent | text) + "h" else empty end),
    (($t.date_creation | timestamp) as $date | if $date then "- 作成: " + $date else empty end),
    (($t.date_started | timestamp) as $date | if $date then "- 開始: " + $date else empty end),
    (($t.date_due | timestamp) as $date | if $date then "- 期限: " + $date else empty end),
    (($t.date_completed | timestamp) as $date | if $date then "- 完了: " + $date else empty end),
    (if ($t.url // "") != "" then "- URL: " + $t.url else empty end),
    "",
    "## 説明",
    "",
    (if ($t.description // "") != "" then ($t.description | markdown) else "_説明なし_" end),
    "",
    "## サブタスク",
    "",
    (if ($sts | length) == 0 then
      "_サブタスクなし_"
     else
      ($sts[] |
        "- [" + (if (.status | tostring) == "2" then "x" else " " end) + "] " + (.title | text) +
        (if (.status | tostring) == "1" then "（進行中）" else "" end) +
        (if (.name // "") != "" then " — 担当: " + (.name | text)
         elif (.username // "") != "" then " — 担当: " + (.username | text)
         else "" end)
      )
    end),
    "",
    "## コメント",
    "",
    (if ($cs | length) == 0 then
      "_コメントなし_"
     else
      ($cs[] |
        "### " +
          (if (.name // "") != "" then (.name | text)
           elif (.username // "") != "" then (.username | text)
           else "不明なユーザー" end) +
          ((.date_creation | timestamp) as $date | if $date then " — " + $date else "" end),
        "",
        (.comment | markdown),
        ""
      )
    end)
  '
