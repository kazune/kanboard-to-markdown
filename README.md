# Kanboard to Markdown

Kanboard のボード情報を取得し、列ごとのタスク一覧を Markdown に変換する Bash スクリプトです。

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

引数に Kanboard のボード ID を1つ指定します。結果は標準出力へ出力されます。

```bash
./kanboard-to-md.sh <board_id>
```

画面に表示する場合:

```bash
./kanboard-to-md.sh 3
```

ファイルへ保存する場合:

```bash
./kanboard-to-md.sh 3 > board.md
```

ボード ID は正の整数で指定する必要があります。引数がない、引数が複数ある、または値が不正な場合は Usage を表示して終了します。

```text
Usage: ./kanboard-to-md.sh <board_id>
```

## 出力内容

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

## 検査

構文と ShellCheck の検査は次のコマンドで実行できます。

```bash
bash -n kanboard-to-md.sh
shellcheck kanboard-to-md.sh
```
