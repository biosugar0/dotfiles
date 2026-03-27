---
name: deslop
description: >-
  Use when: AI生成コードに余計な変更・過剰なコメント・不要な抽象化がある、slop除去、
  コード品質が気になるブランチ。
model: sonnet
user-invocable: true
allowed-tools:
  - Read
  - Edit
  - Write
  - Bash
  - Grep
  - Glob
context: fork
effort: high
---

Read ./INSTRUCTIONS.md and follow the instructions.
