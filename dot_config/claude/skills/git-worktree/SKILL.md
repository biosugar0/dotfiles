---
name: git-worktree
description: |
  Worktree strategy router. 目的に応じて最適な手法を選択:
  - 組み込み worktree isolation (isolation: "worktree") — 使い捨てsubagent作業
  - git gtr コマンド — mainリポ操作・名前付きworktree管理

  【必須発動キーワード】以下を含む発言時は必ずこのスキルを呼び出すこと:
  - 「worktree」「ワークツリー」
  - 「mainでテスト」「mainで確認」「mainでビルド」
  - 「isolation: worktree」「--worktree」
  - 「worktreeで修正」
  - 「git gtr」

  重要:
  - 生の git worktree コマンドは使用しない
  - 手動 worktree 操作は git gtr を使用
  - Claude 組み込み worktree (isolation: "worktree", --worktree) はそのまま使用
---

Read ./INSTRUCTIONS.md and follow the instructions.
