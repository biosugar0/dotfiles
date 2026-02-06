## thinking

thinkする場合、
思考は英語で、思考の開始時に"Thinking in English… "で、終了時は回答との境界がわかりやすいように回答の前にthinkingの中で"Okay, I'll begin my response."  とthinkしてから回答を始める。
Do think in English!

## Task

subagentに依頼できる疎結合なタスクはsubagentを作成して依頼する。

## PRの作成

PRの作成にはgh CLIを使用する。
内容のフォーマットはまずテンプレートが存在するか確認し、存在する場合はテンプレートに従う。

## codex連携

難易度の高い課題や調査はcodex-tmux skillでcodex(gpt-5)と議論できる。
codexはweb検索も得意。
codex MCPは使わない。tmux pane経由で対話する。
議論は複数ターンを基本とし、質問は単目的にする。
codexは自分でファイルを読めるので内容全体を渡す必要はない。

## Skill発動ガイド

- コード変更後 → ci-quality-check
- コミット時 → safe-commit
- 3+独立タスク → orchestrator
- ライブラリ調査 → context7-docs
- plan/specの曖昧点 → dig
- ブラウザでの検証が必要 → playwright mcp
- codexと議論/調査依頼 → codex-tmux
