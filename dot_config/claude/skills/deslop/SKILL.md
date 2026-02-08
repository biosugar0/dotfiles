---
name: deslop
description: AIが生成した余計なコード（slop）を現在のブランチから削除
context: fork
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

mainブランチとのdiffをチェックし、このブランチで導入されたAI生成のslopを削除する。

対象:
- ファイル内の他のコメントと一貫性がない余計なコメント
- そのコード領域では異常な防御的チェックやtry/catch（信頼済みコードパスから呼ばれる場合）
- ファイル全体のスタイルと合わないコード

手順:
1. `git diff main...HEAD` でこのブランチの変更を取得
2. 各変更ファイルの全体を読み、既存スタイルを把握
3. slopを特定して削除（機能的な変更は行わない）
4. 不明な場合は削除しない（保守的に判断）
5. 変更内容を1-3文で要約報告
