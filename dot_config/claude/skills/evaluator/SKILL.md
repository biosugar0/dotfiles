---
name: evaluator
description: >-
  Use when: 実装完了後の品質評価、PR前の最終検証、フロントエンド/API/CLIの動作確認。
  Generator（実装者）とは独立した視点で成果物を評価し、具体的なフィードバックを返す。
user-invocable: true
argument-hint: "[対象の説明] or 省略で直近の変更を評価"
context: fork
effort: xhigh
allowed-tools:
  - Read
  - Grep
  - Glob
  - Bash
  - LSP
  - WebFetch
  - WebSearch
---

Read ./INSTRUCTIONS.md and follow the instructions.
