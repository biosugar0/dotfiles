# メタ認知（着手前の前提点検）

## 原則

「内省を増やす」スキルではない。**行動する前に、外せる前提を1つ選び、失敗しうる検証を用意する**ためのもの。
十分な情報があるなら動く。点検は短く、出力は検証可能な成果物にする。

```
広い編集に進む前に: 速く決定的な pass/fail ループはあるか？
無ければ作る。作れないなら理由を述べる。— ただし編集自体は止めない。
```

## 適用タイミング

- 広い編集 / リファクタ / 設計変更の前
- 行き詰まったとき、同じ失敗が繰り返すとき（`ai-run-check` の警告が出たとき）
- 原因が不確かなまま修正に入りそうなとき

小さな確定的タスク・単発質問では使わない（過剰点検は出力を劣化させる）。

## やること（出力は検証可能な成果物のみ）

1. **feedback loop の有無**: その変更の正否を秒で判定できる決定的なコマンド（test/repro/harness）があるか。
   - 無い → まず repro/test を作る。作れないなら「なぜ作れないか」を1行で述べる。
   - confidence は自己申告でなく **loop の有無**で定義する（loop が無い＝low）。
2. **ranked hypotheses（3〜5個）**: 単一仮説への固着を避ける。各仮説に **falsifiable prediction** を付ける。
   - 形式: 「X が原因なら、Y を実行すれば Z になる（ならなければ X は否定される）」。
3. **weakest_assumption**: 一番崩れやすい前提を1つ挙げ、それを否定しにいく **disconfirming check** を選ぶ。
4. 確認したら、その check を**実行**して結果で進む。確証バイアスでなく否定を試みる。

## ⚠ 出力規律（重要・Fable 5 の reasoning_extraction footgun 回避）

- **内部推論を逐一エコー/開示しない**。「思考過程を順に説明」「chain-of-thought を見せる」系の出力はしない。
  （これを強制すると Fable 5 で refusal を誘発し Opus へ fallback する。可視化が要るなら structured thinking を使う。）
- 出すのは **検証可能な結論・根拠・不確実性**: 使う check コマンド、falsifiable prediction、確認/否定された前提。
- 仮説は「推論の語り」でなく「実行すれば真偽が決まる主張」として書く。

## ハードブロックしない（advisory）

confidence / weakest_assumption / loop quality は **警告・nudge のみ**。Edit は止めない（自己申告は突破され儀式化する）。

実際に止まるのは **客観的ゲートだけ**:
- 無検証の完了/commit/PR 主張（`verify` skill + stop-hook）
- evaluator が BLOCKED
- `ai-run-check` の同一失敗が上限回（戦略変更まで）
- secrets / main / 破壊的操作（既存 gate）
- worktree の未承認統合（`codex-worker-apply`）

理由: confidence は実装中に変動し自己申告は不確実。害が最大化する「無検証 DONE」は done-gate が客観的に止める。
だから Edit を confidence で止めるより、done-gate + anti-loop に集約する。

## task_contract への記録（任意・advisory）

`ai/state/task_contract.json` があれば次を追記してよい（無ければ作らなくてよい）:

```
confidence: "low|medium|high"          # loop の有無で定義
weakest_assumption: "<崩れやすい前提>"
disconfirming_check: "<それを否定しにいくコマンド/手順>"
evidence: ["<実行したcheckと結果>"]
strategy_reset_required: false         # 同一失敗ループに入ったら true
```

これらは進行の補助記録であって、Edit のブロック条件ではない。
