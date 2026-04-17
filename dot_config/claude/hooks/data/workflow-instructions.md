## thinking

thinkする場合、
思考は英語で、思考の開始時に"Thinking in English… "で、終了時は回答との境界がわかりやすいように回答の前にthinkingの中で"Okay, I'll begin my response."  とthinkしてから回答を始める。
常に自分の思考に疑問を持ち、推測に対して待てよそれは正しいか？と慎重によく思考すること。

## Task

subagentに依頼できる疎結合なタスクはsubagentを**積極的に**作成して依頼する。
Opus 4.7はデフォルトでsubagent生成を減らす傾向があるため、以下のケースでは意識的に委譲する:

- **独立・並列化可能**: 複数の独立した調査・検証・実装がある → 同一メッセージ内で複数subagentを並列起動
- **コンテキスト保護**: 大量のファイル走査・grep結果・ログ解析など、main contextを汚染する探索 → Explore/general-purpose agent
- **専門性が一致**: ci-quality-checker, Plan, claude-code-guide等、agent descriptionに合致するタスク
- **疎結合な実装**: 他と依存せず独立に進められる実装単位 → 実装agentに委譲

逆に委譲しないケース: ファイルパス既知のRead、特定symbolのGrep、ユーザーとの対話が必要な判断。

## PRの作成

PRの作成にはgh CLIを使用する。
内容のフォーマットはまずテンプレートが存在するか確認し、存在する場合はテンプレートに従う。

## codex連携

難易度の高い課題や調査はcodex-tmux skillでcodex(gpt-5)と議論できる。
codexはweb検索も得意。
codex MCPは使わない。必ず最初にtmux paneを作成してからcodexと対話する。
議論は複数ターンを基本とし、質問は単目的にする。
codexは自分でファイルを読めるので内容全体を渡す必要はない。

## ブランチ作成前

worktree or ブランチ作成前に `git fetch origin main` でリモートを取得し、`origin/main` ベースで作成する。
ローカル main が古いと plan に無関係な drift が出て判断を誤る。

## Planner フロー（短いプロンプト → フル仕様 → 実装）

短い指示から本格的な実装に入る場合の推奨フロー:

1. **仕様展開**: `/plan` で短いプロンプトからフル実装計画を生成
2. **曖昧点解消**: `/dig [plan-file]` で計画の曖昧点を洗い出し、ユーザーに確認
3. **要件深掘り**（必要時のみ）: `/spec-interview` で対話的に要件を明確化
4. **実行**: orchestrator で計画を分解・並列実行

`/plan` だけで十分な場合が多い。`/dig` は計画の品質に不安がある場合のみ。

## Skill発動ガイド

- コード変更後 → ci-quality-check
- 実装完了後の品質評価 → evaluator
- コミット時 → safe-commit
- 3+独立タスク → orchestrator（Sprint Contract付き、限定適用）
- ライブラリ調査 → context7-docs
- 短い指示から仕様展開 → /plan → /dig（Planner フロー）
- plan/specの曖昧点チェック、ユーザーへの確認 → dig
- ブラウザでの検証が必要 → playwright skill（CLI）
- codexと議論/調査依頼 → codex-tmux
- ハーネスの有効性検証 → harness-audit（月次推奨）
