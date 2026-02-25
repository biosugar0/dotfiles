---
name: deslop
description: Remove AI-generated slop code from the current branch. AIが生成した余計なコード（slop）を現在のブランチから削除。
model: sonnet
user-invocable: true
allowed-tools:
  - Read
  - Edit
  - Write
  - Bash
  - Grep
  - Glob
---

Read ./INSTRUCTIONS.md and follow the instructions.
