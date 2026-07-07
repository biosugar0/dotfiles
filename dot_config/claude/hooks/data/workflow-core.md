## Workflow core（圧縮版）
- 疎結合なタスクは subagent に積極委譲。general-purpose は codex-worker に自動ルーティングされる
- 外部入力を読むタスクは `[hardened]`、codex に書かせるタスクは `[write:<slug>]` をマーカーで明示
- codex の結果は proposal。検証は親 Claude が自分で実行したコマンド出力のみ
- PR 作成前に codex レビュー必須。PR は gh CLI で draft 作成、マージは人間に依頼
- ブランチ/worktree 作成前に `git fetch origin main` し origin/main ベースで作る
- skill 発動: コード変更後→ci-quality-check / コミット→safe-commit / 完了主張前→verify
- test/lint/build は `ai-run-check -- <cmd>` 経由で実行
- 詳細ルールは数ターン毎にフル再注入される。詳細が必要なら `~/.config/claude/hooks/data/workflow-instructions.md` を読む
