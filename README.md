# Kanboard to Markdown

Kanboard のボードとタスク情報を Markdown に変換する Bash スクリプトです。

## 必要なもの

- Bash
- curl
- jq
- Kanboard の API ユーザー名とトークン

## 設定

設定ファイルを作成し、実行時に `--config` で指定します。

```bash
KANBOARD_URL=https://kanboard.example.com
KANBOARD_USERNAME=your-api-user
KANBOARD_API_TOKEN=your-api-token
```

API トークンを含むため、ディレクトリと設定ファイルの読み取り権限を制限します。

```bash
mkdir -p ~/.config/kanboard-md
chmod 700 ~/.config/kanboard-md
chmod 600 ~/.config/kanboard-md/config.env
```

設定ファイルは読込前に所有者とパーミッションを検査します。現在の実行ユーザーが所有していない場合や、グループまたはその他ユーザーに権限がある場合は、安全でない設定としてエラー終了します。`600` または `400` など、所有者だけが読める設定にしてください。

設定ファイルは自動探索せず、認証情報を環境変数からも読み込みません。絶対パスと相対パスのどちらも明示指定できます。

## 使い方

`kanboard-md` はサブコマンドを受け取ります。`board` と `task` では対象の ID も指定します。結果は標準出力へ出力されます。

```bash
./kanboard-md --config ~/.config/kanboard-md/config.env boards
./kanboard-md --config ~/.config/kanboard-md/config.env board <board_id>
./kanboard-md --config ~/.config/kanboard-md/config.env task <task_id>
```

## ボード一覧

`boards` サブコマンドは、利用可能なボードを有効・無効に分けて出力します。

```bash
./kanboard-md --config ~/.config/kanboard-md/config.env boards
./kanboard-md --config ~/.config/kanboard-md/config.env boards > boards.md
```

各項目にはボード ID、名前、Kanboard 上のボードへのリンク、識別子（設定されている場合）が含まれます。

```markdown
# Boards

## 有効 (1)

- #3 [Sample Project](https://kanboard.example.com/board/3)

## 無効 (0)

_ボードなし_
```

このサブコマンドは通常 `getMyProjects` を使用し、認証ユーザーが利用できるボードを取得します。Application API の `jsonrpc` ユーザーで認証している場合は `getAllProjects` を使用します。

## ボード

引数に Kanboard のボード ID を1つ指定します。

画面に表示する場合:

```bash
./kanboard-md --config ~/.config/kanboard-md/config.env board 3
```

ファイルへ保存する場合:

```bash
./kanboard-md --config ~/.config/kanboard-md/config.env board 3 > board.md
```

ボード ID は正の整数で指定する必要があります。サブコマンド、引数の数、または ID が不正な場合は Usage を表示して終了します。

```text
Usage:
  ./kanboard-md --config <file> boards
  ./kanboard-md --config <file> board <board_id>
  ./kanboard-md --config <file> task <task_id>
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
./kanboard-md --config ~/.config/kanboard-md/config.env task 63 > task-63.md
```

タスク ID は正の整数で指定する必要があります。

```text
Usage:
  ./kanboard-md --config <file> boards
  ./kanboard-md --config <file> board <board_id>
  ./kanboard-md --config <file> task <task_id>
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
