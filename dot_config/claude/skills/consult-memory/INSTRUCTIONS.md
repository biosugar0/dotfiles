# 記憶の参照（consult-memory）

過去に検証した教訓を**必要なときだけ**読み、同じ失敗・同じ調査の繰り返しを避ける。
過剰参照は context を汚すので、小タスク・単発質問では読まない。

## 参照する場面（限定）

- 非自明なタスクの**開始時**
- **plan を書く前**
- **同じ失敗が繰り返す**とき（`ai-run-check` の警告が出た / 同種のバグに再遭遇）
- **evaluator が UNKNOWN** を返したとき
- 中断した作業の**再開前**（worklog / 該当 memory を先に読む）

読まない: 1〜2 手で終わる確定的タスク、単発の質問、すでに答えが文脈にあるとき。

## 3 層（どこを読むか）

| 層 | 場所 | 性質 |
|---|---|---|
| transient | `ai/state/*.json`（verification/workflow-gate/loop/task_contract/handoff） | 進行中の状態。常に最新 |
| personal-local | `ai/memory/*.md` | 端末ローカルの教訓（`ai/` は gitignore） |
| committed | `CONTEXT.md` / `docs/adr/` / `.out-of-scope/` | チーム共有（人間承認後のみ昇格） |

委譲した subagent や別端末はこの memory を見られない。共有が要るものは committed 層へ昇格する（distill-memory）。

## 読み方

1. まず各ファイル冒頭の**1 行サマリ**を流し読みし、関係するものだけ開く。
2. **Scope**（repo/package/file/local-env）が今の対象に合い、かつ **Applies when**（状況）が一致する note だけ採用する。
3. `Status:` を見る: **verified を優先**、`probable` は仮説として扱い検証する、`deprecated` は無視。
4. `Expires:` / `Invalidation:` を確認し、期限切れ・無効条件に該当する note は信用しない（distill-memory での prune 対象）。
5. committed 層: `CONTEXT.md`=ドメイン用語の定義、`docs/adr/`=なぜその設計か、`.out-of-scope/`=却下済みの要望（蒸し返さない）。

## 注意

- memory は**証拠ではない**。`probable` や古い note の主張は、その場のコマンド実行で検証してから使う（verify skill の哲学）。
- 読んだだけで満足しない。教訓を今のタスクの判断（plan / 仮説 / 回避策）に具体的に反映する。
