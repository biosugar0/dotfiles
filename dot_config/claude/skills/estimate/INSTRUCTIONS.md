# estimate: Claude Code 前提の工数見積もり

## なぜこのスキルが必要か

Claude Code に「どれくらいかかる?」と聞くと、訓練データ由来の**人間が直列で手を動かす前提**の見積もり(人日・週・ストーリーポイント)が出る。これは構造的に誤り。Claude Code は subagent / git worktree で独立タスクを並列実行でき、実装は速い。律速は実装ではなく **人間の意思決定・レビュー**と**外部依存(CI・承認・サードパーティ・デプロイ)** に移る。scarce resource は「人間の労働日数」ではなく「人間が何回クリティカルパス上で割り込むか」。

**ただし逆の歪み(AI万能視で薄く見積もる)も同じくらい危険。** 成熟した大規模コードベースの微妙な変更・曖昧仕様・レビュー往復が多い領域では AI はむしろ遅くなりうる(METR 2025 RCT: 成熟コードベースの経験者タスクで AI 利用が 19% 遅延)。DORA も「コード生成で浮いた時間は検証・監査に再配分」「throughput と instability は同時に増える」と指摘。

**このスキルの仕事は両方向の歪み(膨張と過小評価)を抑え、チェックの証跡を必ず出力に残すこと。** ガードは宣言では発火しない。出力に強制されて初めて機能する。

---

## 中心命令(必ず守る)

1. **依存 DAG を構築してから計算する。** 感覚で「だいたい N 日」と出さない。分解からしか最終値を出さない。
2. **人間の直列労働から換算しない。** "if a human did this serially in N days" は禁止句。
3. **並列 AI タスクはバッチごとの max を取る。合計しない。** ただし overhead は別途加算する(Step 6)。
4. **AI critical path は AI 作業時間のみ。** 仕様決定・契約承認・CI/deploy 待ち・レビュー・外部API・権限・fix pass は **すべてゲート**であり、Step 7 で別計上する。**同じ項目を AI critical path とゲートの両方に入れない(二重計上の禁止)。**
5. **AI実行時間・人間ゲート・外部ゲート・rework予備を毎回分離表示し、Guard scan / Batch math / Risk adjustment を出力に必ず含める。**

---

## 実行手順

### Step 1: 完了状態を固定する(デフォルトを逃げ道にしない)

完了の定義で見積もりは激変する。**target ごとに含めるゲートが違う**ことに注意:

| target | 含むもの | 含まないもの |
|---|---|---|
| `PR-ready` | 実装 + テスト + CI green、レビュー提出可能 | **人間レビュー・review fix・承認**(これらは merge-ready 側) |
| `merge-ready` | PR-ready + 人間レビュー往復 + 承認 | デプロイ |
| `deployed` | merge-ready + デプロイ + 本番反映 | リリース告知 |
| `released` | deployed + 段階リリース + 告知 | — |

- 指定がなければ **`PR-ready`** を仮定し明示する。
- ユーザーが「いつ使える」「いつリリース」「本番でいつ」と聞いたら **`deployed` / `released`** で見積もる。
- target によって何が変わるか大きい場合は PR-ready と deployed を**両方**併記する。

### Step 2: agent task atom に分解する(粒度を固定)

1 agent が 1 worktree で完結できる粒度に割る。**目安: 1 atom = 30〜60 分以内で成果物と acceptance check を持つ**。60 分超は分割、10 分未満が多数なら統合する(overhead が支配的になり過小評価/管理破綻を招く)。

**例外 — 探索/調査タスク**: 分解前に深さが読めない作業(原因調査・設計検討)は分割せず **timeboxed spike** として扱う(例: 30〜60m の spike → 結果を見て次を決める)。spike は本質的に逐次で並列化できないため、並列 atom を捏造しない。

各 atom が必ず持つ項目: `task_id` / `deliverable` / `touched areas` / `acceptance check` / `required input` / `produces output` / `merge/review risk`

### Step 3: 独立性を判定する

**並列化可能**(すべて満たす方向): 受け入れ条件が局所的に検証できる / 他 task の未確定出力を待たない / 変更対象が別モジュール、または共有インターフェースが先に固定 / merge order に意味がない or 衝突が機械的に解消可能 / テストを個別に走らせられる。

**並列化不可 or 次バッチ送り**(いずれか該当): A の結果で B の仕様が変わる / API・schema・型・データモデルの契約が未確定 / 同じ中核ファイルを複数 task が意味的に編集 / migration・rollout・互換性の順序がある / 人間の仕様判断がないと正解を定義できない。

### Step 4: AI work DAG の edge を引く(ゲートは edge にしない)

AI critical path を計算するための DAG。**ノード = agent atom**。edge になれるのは **AI 作業ノード間の依存**だけ:

- 前段の AI 成果物を後段が入力にする
- 共有契約(API/schema/型)が確定してから依存実装が走る
- 仕様決定が済んでから実装が走る(※決定の**待ち時間**は AI work ではなくゲート → Step 7。ここでは「順序」だけを表す)

次は **edge にしない**(理由だけの偽の直列): 「人間なら順番にやる」「同じリポジトリ」「同じ機能群」「レビュー担当者が同じ」「実装量が多い」。

> CI/test/deploy 待ち・承認・レビュー・外部API・fix pass は **AI work ではなくゲート**。AI critical path には入れず Step 7 で別計上する(中心命令4)。「レビュー担当者が同じ」は AI DAG の edge ではないが、calendar 上は human capacity gate になる(Step 7)。

### Step 5: batch を組む

DAG の同じ depth の atom を同時実行バッチにする:

- **Batch 0**: interface contract のドラフト(AI が schema/API 案を出す。承認は Step 7 のゲート)
- **Batch 1**: independent implementations(独立実装を並列)
- **Batch 2**: integration / migration / cross-cutting fixes
- **Batch 3**: 自己検証 / CI fix(人間レビュー対応は merge-ready 側)

### Step 6: バッチ時間 = max + overhead(合計しない、ただし overhead は必ず足す)

**バッチ所要 = max(atom の AI 作業時間) + coordination overhead**。バッチ間のみ加算。

**coordination overhead は要素別に明示して算入する**(丸めて「+10m」で済ませない。これを怠ると 10 でも 50 agents でも「max + 少し」で薄く見える):

- **safe concurrency cap**: 同時実行上限。**目安は同時 worktree / CI runner 数で 3〜8**。無制限を前提にしない。cap を超える atom 数のバッチは複数波に分割し、波の数ぶん加算。
- **per-batch setup/context overhead**: worktree 準備・context 投入。
- **merge/integration overhead**: 並列成果物の統合コスト。
- **shared file collision**: 次に該当する atom が複数あれば衝突コストを上乗せ、または直列化する — **lockfile / migration / schema / generated files / test fixtures / shared config**。

AI 作業の atom 目安: 局所修正 数分〜20分 / 中規模実装(複数ファイル+テスト)20〜60分 / 探索 spike 30〜60分(timebox)。

### Step 7: ゲートを別列で足して最終値を出す

```
Delivery lead time
  = AI critical path        (Step 6 の AI 作業のみ, overhead 込み)
  + human gates             (仕様/契約 decision + レビュー ※target に応じて)
  + external gates          (CI / deploy / 承認 / 外部API 待ち)
  + rework reserve          (想定 fix pass)
```

**human gate の容量モデル**: human attention(判断・レビュー実時間)と human queue wait(着手までの待ち)を分ける。**レビュー・承認者が単一人物なら、複数 PR のレビュー attention を並列圧縮しない**(直列加算)。

**queue wait が不明なとき(必須ルール)**: ゼロ扱いにしない。headline P50/P90 は **queue wait を除外した assumption-scoped 値**として出し、(a) `Human gate time` 行に `queue wait: unknown` と明記、(b) `Main uncertainty` に挙げ、(c) **confidence を medium 以下に上限する**。「unknown だから合計に入れない」で薄く見せない。

**rework reserve の算入方法**: **1 fix pass = AI fix + (merge-ready 以降は人間 re-review) + CI rerun** と定義。下記 underestimation trigger 該当時は **P90 に最低 1 回分を必ず算入**。P50(中央値)にも、CI 初回失敗など高頻度の rework が見込めるなら部分算入してよい(楽観に寄せない)。

不確実性は単一値でなく **P50 / P90** で表す。

---

## 出力フォーマット

非自明なタスクは**全項目必須**。`Batch math` を成立させるため、atom 数・batch・edge・cap の分解を出力に残すこと(分解表は補足ではなく必須)。

```
Estimate
- Delivery target:      <PR-ready | merge-ready | deployed | released>(デフォルト/仮定なら明記)
- P50 / P90 wall-clock: <例: P50 2.5h / P90 4.5h>
- AI critical path:     <AI 作業のみ。例: 95m = B0 20m -> B1 50m -> B2 25m>
- Human gate time:      <decision cycles 回数 + attention; queue wait(単一レビュアーか / unknown か)>
- External gate time:   <例: CI 15-30m, approval unknown>
- Rework reserve:       <例: +1 fix pass (= AI fix + CI rerun), P90 に算入済み>
- Max parallel agents:  <例: 4 agents (B1), cap 8 内 1 波>
- Agent batches:        <Batch 0..N: atom 内訳。Max parallel agents と atom 数を一致させる>
- Critical path:        <工程フロー。例: contract -> 並列実装 -> 結合 -> CI -> PR-ready>
- Batch math:           <全バッチの max+overhead を明示。例: B0=20m / B1=max(25,30,35,40)+10=50m / B2=15+10=25m>
- Guard scan:           <self-check 全5項目 + 不変条件を1行で。例参照>
- Risk adjustment:      <該当 trigger と補正、または「非該当(根拠)」>
- Main uncertainty:     <最大の不確実要因。unknown ゲートはここに必ず挙げる>
- Confidence:           <high | medium | low>
```

**自明タスク(typo / 1行 / import 追加 等)は短縮形でよい**: `Delivery target` + `P50/P90` + `Guard scan` 1行のみ。重装備の14項目を強制しない(形骸化防止)。

**実装以外のタスク型の当て方**:
- 調査/原因究明 → timeboxed spike 主体。AI critical path は spike 長、結論は逐次依存。並列 atom を捏造しない。
- 設計/方針出し → human decision gate が支配的。AI は選択肢出しまで。
- インフラ/運用(証明書更新・IAM 変更等) → external gate(承認・反映待ち)が支配的で AI critical path ≒ 0。

---

## アンチ膨張ガード

### 禁止事項(Forbidden)

- 人日・週・ストーリーポイントを**主**単位にする
- "人間が直列でやるなら N 日" から換算する
- 独立 task の時間を**合計して** AI 実行時間にする
- 実装量の多さだけで直列制約を作る
- レビューや CI を AI critical path に混ぜる(ゲートとして別計上する)

人日を明示的に求められた場合のみ `human attention hours` として**補助併記**してよい。主単位は wall-clock のまま。

### self-check(出力前に必ず実行し、結果を `Guard scan` 行に残す)

1. 独立 AI タスクの時間を合計していないか? → バッチごとの max に置き換える
2. 「人間なら直列にやる」だけの理由で edge を作っていないか? → 削除する
3. 主単位に日・週を使っていないか? → wall-clock の時間/分に書き直す
4. CI/レビュー/承認/fix pass を AI critical path に混ぜていないか? → ゲートとして分離する
5. coordination overhead(4要素)と safe concurrency cap を算入したか? → 未算入なら追加する
6. **不変条件**: `P90 ≥ P50 ≥ AI critical path + (P50 に含めたゲート)` を満たすか? unknown ゲートがあるなら headline を assumption-scoped と明記したか?

Guard scan 例: `summed? no(max) / human-serial edge? none / unit=wall-clock / CI&review=gate not AI-path / overhead B1+10m,cap8内1波 / P50 150m≥cp95+gates40 ✓, queue wait unknown→scoped`

---

## 過小評価ガード(薄く見すぎの防止)

次の **underestimation triggers** に該当する**可能性が残るなら**(白黒つかない時点で)補正を算入する。**除外するなら根拠を `Risk adjustment` に明記**する(非対称ルール: 「微妙でない」と自己申告して逃げない):

- 成熟した大規模コードベースの微妙な変更
- 暗黙知・歴史的経緯・既存の設計判断に依存
- 仕様が曖昧、または正解がプロダクト判断
- セキュリティ・課金・認可・データ移行・互換性が絡む
- テストが薄い / CI が不安定 / 再現環境が弱い
- 変更は小さいが影響範囲が広い
- レビューで主観判断が多い

**補正は「AI実行時間を人日へ戻す」のではなく、ゲート回数と再作業パスで表す**:

- `rework reserve: +1 fix pass`(P90 算入)/ `+2 fix passes`
- `human decision cycles: +1`
- `review gate: P50 30m, P90 2h`
- `confidence: low`

---

## Worked example

> 「ユーザー設定画面にトグル設定を3つ追加して、API・DB・フロントを対応させたい。どれくらい?」

完了状態は指定なし → **PR-ready** を仮定(人間レビュー往復は含まない)。AI work DAG の edge は「DB schema / API 契約の確定 → 依存実装」のみ。契約確定の**待ち**は human gate として別計上。

```
Estimate
- Delivery target:      PR-ready (指定なしのためデフォルト仮定。merge-ready なら + レビュー往復は後述)
- P50 / P90 wall-clock: P50 2.5h / P90 4.5h  (queue wait 除外の assumption-scoped 値)
- AI critical path:     95m = B0 draft 20m -> B1 50m -> B2 25m  (AI 作業のみ)
- Human gate time:      契約承認 1 decision cycle (15-30m attention); queue wait unknown (担当者依存)
- External gate time:   CI 15-30m
- Rework reserve:       +1 fix pass (= AI fix + CI rerun), P90 に算入済み
- Max parallel agents:  4 agents (B1), cap 8 内 1 波
- Agent batches:        B0 schema+API契約ドラフト(1) / B1 migration + API + FE設定画面 + FEログインUI(4 並列) / B2 結合+e2e(1)
- Critical path:        contract確定 -> 並列実装 -> 結合 -> CI green -> PR-ready
- Batch math:           B0 = 20m / B1 = max(migration 25, API 30, FE設定 35, FEログイン 40) + 10m overhead = 50m / B2 = 15m + 10m = 25m
- Guard scan:           summed? no(max) / human-serial edge? none / unit=wall-clock / CI&review=gate not AI-path / overhead B1+10m,cap8内1波 / P50 150m ≥ cp95+gates(decision20+CI20=40)=135 ✓, queue wait unknown→scoped
- Risk adjustment:      triggers 非該当(新しめCB / テスト有 / セキュリティ非絡み)を確認 → 補正なし
- Main uncertainty:     既存設定基盤の抽象化レベル; 契約承認の queue wait (unknown)
- Confidence:           medium
```

> **merge-ready なら**: + 人間レビュー queue wait(単一レビュアーなら直列) + review fix pass 1〜2 回 → P90 に +数h、confidence を下げる。

人日換算(「3〜5人日」)に逃げず、wall-clock で、AI 作業(95m)と律速ゲート(契約確定・承認 queue)を分離し、headline が AI critical path を下回らないことを Guard scan で検証できている点に注目。
