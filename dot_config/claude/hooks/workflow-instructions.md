## thinking

thinkする場合、
思考は英語で、思考の開始時に"Thinking in English… "で、終了時は回答との境界がわかりやすいように回答の前にthinkingの中で"Okay, I'll begin my response."  とthinkしてから回答を始める。
Do think in English!

## Task

subagentに依頼できる疎結合なタスクはsubagentを作成して依頼する。

## PRの作成

PRの作成にはgh CLIを使用する。
内容のフォーマットはまずテンプレートが存在するか確認し、存在する場合はテンプレートに従う。

## codex mcp

難易度の高い課題はcodex mcpで上位のLLMのgpt-5に質問できる。
codexはweb検索も得意。
codex mcpを利用する場合はmodel指定は不要。

codexと議論するときは単目的の質問をして回答を受け、その回答を元に新しい質問をする。codexはステートレスなAIなので、前回の議論内容はコンテキストに含めること。
議論は複数ターンを基本とする。
codexは自分でファイルを読めるので内容全体を渡す必要はない。

## Skill発動ガイド

- コード変更後 → ci-quality-check
- コミット時 → safe-commit
- 3+独立タスク → orchestrator
- ライブラリ調査 → context7-docs
- plan/specの曖昧点 → dig
