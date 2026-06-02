---
name: estimate
description: >-
  Use when: 開発タスクの工数・見積もり・スケジュール感・ETA を聞かれた場面。
  「どれくらいかかる」「何人日」「いつ終わる」「見積もって」「ざっくりどのくらい」
  「このPR/機能/リファクタの工数」「スプリントに載るか」等。
  Claude Code は人間直列前提の膨らんだ工数(人日・週・ストーリーポイント)を出しがち。
  実際は subagent / git worktree で並列実行でき律速はゲートに移るが、成熟コードベースの微妙な変更や
  曖昧仕様では逆に薄く見積もりすぎる歪みも起きる。このスキルは見積もりを「AI実行のクリティカルパス +
  人間ゲート + 外部ゲート + rework予備」の wall-clock に分解し、膨張と過小評価の両方向を出力強制で抑える。
  見積もり・工数・期間の話題が出たら必ず発動すること。
user-invocable: true
argument-hint: "[見積もり対象のタスク/PR/機能]"
effort: high
---

Read ./INSTRUCTIONS.md and follow the instructions.
