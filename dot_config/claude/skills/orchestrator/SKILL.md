---
name: orchestrator
description: |
  Decompose tasks into sequential steps and parallel subtasks for efficient execution.
  Use when: 3つ以上の独立サブタスクがある、複数ファイルの並列変更、
  テスト・lint・commitの一括実行、調査と実装の段階的実行が必要な場合。

  【必須発動キーワード】以下を含む発言時は必ずこのスキルを呼び出すこと:
  - 「タスク分解」「分解して」「ステップに分けて」
  - 「並列で実行」「並列実行」「並列で」「同時に」
  - 「一括で」「まとめて実行」「まとめてやって」
  - 「orchestrator」「オーケストレーター」

  【自動発動条件】以下の状況を検出した場合も自動発動すること:
  - TODOリストに3つ以上の未完了タスクが存在する
  - ユーザーが1つの発言で3つ以上の作業を依頼している
  - plan/specに複数の実装ステップが記載されている
---

Read ./INSTRUCTIONS.md and follow the instructions.
