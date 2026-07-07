# 記憶の蒸留（distill-memory）

検証済みの教訓だけを、腐らない形（schema 付き）で残す。自由形式で書き散らさない。

## いつ蒸留するか

- **evaluator が PASS した後のみ**。蒸留前に `ai/state/workflow-gate.json` を読み、`evaluator.status == "PASS"` かつ
  `head_sha` が現在の HEAD と一致することを確認する。PASS でなければ蒸留しない（未検証の教訓は害）。
  ユーザーが明示的に「これを記録して」と指示した場合のみ例外。
- 残す価値があるのは「次に同じ判断をするとき時間を節約する」もの: ハマった罠とその回避、確定したアプローチ（なぜそれが正しいか）。

## 書かない（重要）

- 書く前に**既存 `ai/memory` のサマリと関連 repo doc を一覧**し、新規作成でなく既存 note の更新で済むか / そもそも repo に既出でないかを判断する。
- **repo や会話がすでに持っている情報**（README/コード/型に書いてあること）は書かない。
- 1 ファイルに複数の教訓を詰めない（**1 lesson / file**）。
- 重複を作らない。同じ話題の既存 note があれば**新規作成でなく更新**する。
- 誤りと判明した note は**削除**する（deprecated 化 → prune）。

## 必須 schema（`ai/memory/<slug>.md`）

冒頭に**1 行サマリ**を置き、本文は次の形式にする:

```
<1 行サマリ（このファイルが何の教訓か）>

## Rule: <name>
Status: verified | probable | deprecated
Scope: repo | package | file | local-env
Last verified: <sha or date>
Expires: <date or 条件（例: "deps の X が更新されるまで"）>
Applies when: <この教訓が適用される状況>
Do: <すべきこと>
Do not: <してはいけないこと / 罠>
Evidence: <検証したコマンド, exit, ファイル, commit>
Invalidation: <この教訓が無効になる兆候>
```

- 最初は `Status: probable` で `ai/memory/` に書く。実コマンドで再検証できたら `verified` に上げる。
- `Evidence` には**自分が実行したコマンドと結果**を書く（「自信がある」では不可。verify skill と同じ）。

## 昇格は人間承認（自動でやらない）

| 操作 | ゲート |
|---|---|
| `probable` → `verified` | **今セッションで実コマンド再検証し Evidence を更新**してから（自信でなく証拠。古い Evidence の使い回し不可） |
| `ai/memory`（local）→ committed（共有） | **人間承認必須**。エージェントは勝手に commit しない（commit は人間が safe-commit で行う。`ai/` は gitignore なので局所記憶は自動共有されない） |

committed への昇格先は用途で分ける:

- `CONTEXT.md`: **ドメイン用語の定義のみ**。実装詳細・spec・scratch は書かない。
- `docs/adr/`: **3 条件をすべて満たす決定だけ** — (1) 不可逆 (2) 文脈なしでは驚く (3) 実トレードオフがある。
- `.out-of-scope/`: 却下した機能・要望を **concept 単位**で記録（同じ議論の蒸し返し防止）。

## 衛生

- `ai/memory` が増えたら `ai-memory-prune` で「行数超過 / Expires 切れ / deprecated」の prune 候補を出し、人間が承認して削る。
- 継続作業の再開時は古い note を鵜呑みにせず `Last verified` / `Expires` を見て再検証する。
