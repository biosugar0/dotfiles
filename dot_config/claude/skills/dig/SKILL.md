---
name: dig
description: >-
  Clarify ambiguous points in specs/plans through structured questions and reflect decisions into the plan.
  Use when: planの確認・レビュー、仕様の詰め、要件の不明点がある、
  「これで大丈夫？」「もう少し詰めたい」「曖昧な点がある」といった場面。
user-invocable: true
argument-hint: "[plan-file]"
context: fork
allowed-tools:
  - Read
  - Write
  - Edit
  - Grep
  - Glob
  - AskUserQuestion
---

Read ./INSTRUCTIONS.md and follow the instructions.
