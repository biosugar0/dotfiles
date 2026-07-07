# 完了前検証

## 原則

完了を主張するなら、証拠を示せ。

```
NO COMPLETION CLAIMS WITHOUT FRESH VERIFICATION EVIDENCE
```

検証コマンドを実行していないなら、「通った」と言うな。

## ゲート関数

```
完了・成功を主張する前に:

1. IDENTIFY: その主張を証明するコマンドは何か？
2. RUN: そのコマンドを完全に実行する（過去の結果は無効）
3. READ: 出力全体を読み、exit code と失敗数を確認する
4. VERIFY: 出力が主張を裏付けるか？
   - NO → 実際の状態を証拠付きで報告
   - YES → 証拠付きで主張
5. ONLY THEN: 主張する

どのステップも省略 = 嘘
```

## 検証要件

| 主張 | 必要な証拠 | 不十分 |
|------|-----------|--------|
| テスト通過 | テスト出力: 0 failures | 前回の結果、「通るはず」 |
| Lint クリーン | Linter 出力: 0 errors | 部分チェック、推測 |
| ビルド成功 | ビルド: exit 0 | Lint 通過、ログが良さそう |
| バグ修正 | 元の症状テスト: pass | コード変更した、直ったはず |
| 回帰テスト | RED-GREEN サイクル検証 | テストが1回通った |
| Agent 完了 | VCS diff で変更確認 | Agent の成功報告 |
| 要件充足 | 行ごとのチェックリスト | テスト通過 |

## 検証としてカウントされないもの

| 状況 | 罠 | 要求される証拠 |
|------|-----|--------------|
| 環境を跨ぐ主張 | dev/stg の成功を prd の証拠として外挿する | 跨ぎ先固有の前提（権限・課金・負荷特性・データ差）を再列挙して個別に確認 |
| 確率的な故障モード（race・タイミング依存・低頻度） | 1回の成功実行を「検証済み」と数える | 発生率に見合う観測母数・時間窓。用意できないなら「未検証（確率的）」と明示して残す |
| 検証の事後繰り延べ（ship-then-audit） | 繰り延べたつもりが単なる検証省略になる | 3条件を満たす: (1)影響が自分に閉じて可逆 (2)事後監査タスクを明示的に残す (3)静かに壊れる成果物（hook・計装・通知・集計）には不適用 |

## Red Flags — 即座に止まれ

- 「はず」「たぶん」「おそらく」を使おうとしている
- 検証前に満足感を表明しようとしている（「完了！」「できた！」等）
- commit/push/PR 作成前に検証していない
- Agent の成功報告を鵜呑みにしている
- 部分的な検証で十分だと思っている

## 言い訳の封じ

| 言い訳 | 現実 |
|--------|------|
| 「通るはず」 | 検証を実行しろ |
| 「自信ある」 | 自信 ≠ 証拠 |
| 「今回だけ」 | 例外なし |
| 「Lint 通った」 | Lint ≠ コンパイラ ≠ テスト |
| 「Agent が成功と言った」 | 独立検証しろ |
| 「部分チェックで十分」 | 部分は何も証明しない |

## パターン

**テスト:**
```
OK: [テスト実行] → [出力: 34/34 pass] → 「全テスト通過」
NG: 「通るはず」「正しく見える」
```

**ビルド:**
```
OK: [ビルド実行] → [exit 0] → 「ビルド成功」
NG: 「Lint 通ったからビルドも大丈夫」
```

**要件:**
```
OK: plan再読 → チェックリスト作成 → 各項目検証 → ギャップ or 完了を報告
NG: 「テスト通った、フェーズ完了」
```

**Agent 委任:**
```
OK: Agent 成功報告 → VCS diff 確認 → 変更内容検証 → 実際の状態を報告
NG: Agent の報告を信頼
```

## 適用タイミング

以下の **前に** 必ず適用:
- 完了・成功の主張（言い方を問わず）
- commit, PR 作成, タスク完了
- 次のタスクへの移行
- Agent への委任後の報告

## 検証 Receipt の記録

receipt(`ai/state/verification.json`、stop-hook が短絡判断に参照)は **`ai-run-check --write-receipt`**
が検証コマンドの **実 exit code から機械生成** する。receipt は手書きせず ai-run-check に生成させる。

```bash
ai-run-check --write-receipt -- <検証コマンド>
# 例:
ai-run-check --write-receipt -- npm test
ai-run-check --write-receipt -- deno check hooks/executable_stop-hook.ts
```

- `status` はコマンドの exit code から機械的に決まる（`0`=PASS / それ以外=FAIL）。`head_sha` / `verified_at` /
  `written_by:"ai-run-check"` を含む。HEAD が変われば古い receipt は無効。
- 複数コマンドを検証する場合は、最後に**全部入りの1コマンド**(`sh -c 'cmd1 && cmd2 && ...'`)で receipt を生成する。
  途中で1つでも失敗すれば exit 非0 → FAIL になる。
- **手書き(`cat > ai/state/verification.json` 等)は pre-tool-use guard でブロックされる**
  （verifier-gaming = 本当は失敗なのに PASS を書く、を防ぐため。receipt の書き込み主体を ai-run-check に集約する）。

> なぜ手書きを排すか: 調査により「検証は外部・決定的シグナルで行い、モデルの自己判断に任せると premature done /
> false PASS が起きる」ことが確認されている。receipt は **渡したコマンドの実 exit code** に束縛され、実行した
> literal コマンドが evidence に自動記録される(監査可能)。ただし receipt が証明するのは「記録コマンドが exit 0 した」
> ことだけで、真の検証スイートが走った保証ではない — `--write-receipt -- true` のような no-op を渡さず、必ず本物の
> 検証コマンド(npm test / deno check / pytest 等)を渡すこと。
