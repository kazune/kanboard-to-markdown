# Kanboard to Markdown

Kanboard のボードとタスク情報を Markdown に変換する Bash スクリプトです。

## 必要なもの

- Bash
- curl
- jq
- Kanboard の API ユーザー名とトークン

## 設定

スクリプトと同じディレクトリに `.env` を作成します。

```bash
KANBOARD_URL=https://kanboard.example.com
KANBOARD_USERNAME=your-api-user
KANBOARD_API_TOKEN=your-api-token
```

これらの値を環境変数として設定している場合、`.env` は不要です。

API トークンを含むため、`.env` は公開リポジトリへコミットしないでください。必要に応じて読み取り権限も制限します。

```bash
chmod 600 .env
```

## 使い方

`kanboard-md` はサブコマンドと対象の ID を受け取ります。結果は標準出力へ出力されます。

```bash
./kanboard-md board <board_id>
./kanboard-md task <task_id>
```

## ボード

引数に Kanboard のボード ID を1つ指定します。

画面に表示する場合:

```bash
./kanboard-md board 3
```

ファイルへ保存する場合:

```bash
./kanboard-md board 3 > board.md
```

ボード ID は正の整数で指定する必要があります。サブコマンド、引数の数、または ID が不正な場合は Usage を表示して終了します。

```text
Usage:
  ./kanboard-md board <board_id>
  ./kanboard-md task <task_id>
```

### 出力内容

次の情報を Markdown に変換します。

- プロジェクト名、ID、状態、説明
- スイムレーン、列、列ごとのタスク数
- 有効なタスクの ID とタイトル
- 担当者、カテゴリ、期限、複雑度（設定されている場合）
- 列のタスク上限（設定されている場合）

出力例:

```markdown
# Sample Project

- プロジェクトID: 3
- 状態: 有効

## Default swimlane

### Backlog (1)

- #10 APIを実装する — 担当: user / 期限: 2026-07-31

### Done (0)

_タスクなし_
```

スクリプトは Kanboard JSON-RPC API の `getProjectById` と `getBoard` を使用します。デフォルトを含む各スイムレーンを `##`、その中の列を `###` の見出しとして出力します。

## タスク

`task` サブコマンドは、指定したタスクの詳細、サブタスク、コメントを Markdown に変換します。引数にタスク ID を1つ指定し、リダイレクトで保存します。

```bash
./kanboard-md task 63 > task-63.md
```

タスク ID は正の整数で指定する必要があります。

```text
Usage:
  ./kanboard-md board <board_id>
  ./kanboard-md task <task_id>
```

### 出力内容

次の情報を出力します。

- 状態、プロジェクト、スイムレーン、列、担当者
- カテゴリ、参照、優先度、複雑度、作業時間
- 作成日時、開始日時、期限、完了日時、タスク URL
- 説明、サブタスク、コメント

スクリプトは `getTask`、`getProjectById`、`getBoard`、`getAllSubtasks`、`getAllComments` を使用します。日時は UTC で出力します。

## 検査

構文と ShellCheck の検査は次のコマンドで実行できます。

```bash
bash -n kanboard-md
shellcheck kanboard-md
```
