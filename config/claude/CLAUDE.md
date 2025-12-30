## 計画・Specファイル（全プロジェクト共通）

すべての計画・specは `~/.config/claude/plans/` に保存。

- `/spec-interview` で作成したspecがここに保存される
- 実装時は `@~/.config/claude/plans/YYYY-MM-DD-xxx.md` で参照
- プロジェクトをまたいで同じspec/planを使い回せる

**重要**: 「planを読んで」「specを確認して」「計画を見て」等の指示があった場合は、まず `~/.config/claude/plans/` 内のファイル一覧を確認すること。

## 調査など

Serena MCPを活用する。

## 作業方針

常に抜け漏れがないかをチェックし、慎重に作業を進めること。
タスクは細かく分割し、タスクごとにsubagentを作成して実行する。

## 長期実行エージェント

複数セッションにまたがる大規模タスクでは `long-running-agent` skill が自動発動する。
セッション引き継ぎはhooksが自動管理（PreCompact/SessionStart）。

## Fetch

Fetchする際にはfetch MCP, もしくはreadability MCPを使用する。

## プロジェクト内AIディレクトリ

`ai/log/sessions/` - セッション引き継ぎファイル（hookが自動生成）

## ライブラリドキュメント

ライブラリ使用方法の回答時は `context7-docs` skill が自動発動し、Context7 MCPで最新ドキュメントを参照する。

## 変更後のチェック

コードを変更後にはci-quality-checker agentによるチェックを行う。

## PRの作成

PRの作成にはgh CLIを使用する。
内容のフォーマットはまずテンプレートが存在するか確認し、存在する場合はテンプレートに従う。

## セッション引き継ぎ

- **自動保存**: PreCompact hookでコンテキスト満杯時に自動保存される
- **手動保存**: `/save-session`で詳細な引き継ぎ情報を作成可能（重要な決定事項がある場合）
