# Harness Audit — コンポーネント有効性検証

## 原則

> "every component in a harness encodes an assumption about what the model
> can't do on its own, and those assumptions are worth stress testing"

モデルが進化すれば、不要になるscaffoldingがある。
定期的に各コンポーネントの有効性を検証し、不要なものは除去する。

除去・簡素化の判断は発火率だけで決めない。**発火率 × 重大度 × precision**
（block reason のサンプル確認で誤 block が少ないこと）を複合基準にする。
低頻度でも高重大度の安全 gate（block-merge, block-pr-without-review 等）は、
発火率が低いという理由だけでは除去候補にしない。

## 監査対象と検証方法

### Hooks
| Hook | 検証方法 | 除去候補の条件 |
|------|---------|---------------|
| stop-hook | `cc-harness-metrics` の stop-hook block rate、goal funnel、block reason サンプル | 低ブロック率が3ヶ月続き、重大度が低く、reason サンプルの precision も低い |
| block-main | `cc-harness-metrics` で deny 回数・対象コマンド・重大度を確認 | 発火がなく、保護対象の重大度も低い（安全 gate なら除外） |
| block-config-edit | 同上 | 発火がなく、保護対象の重大度も低い（安全 gate なら除外） |
| block-pr-without-review | `cc-harness-metrics` の deny/warn + marker file の作成頻度、reason サンプル | 発火率では除去しない。常にreview後にPRを作成しており、precision 低下や運用摩擦が確認された場合のみ見直す |
| eol hook | `projects/**/*.jsonl` の PostToolUse 出力を確認 | 修正頻度が低く、重大度が低く、誤修正や摩擦が上回る |

### Skills
| Skill | 検証方法 | 簡素化の条件 |
|-------|---------|-------------|
| verify | evaluator導入後、セルフチェックの追加価値を測定 | evaluatorが同等以上のカバレッジを提供 |
| orchestrator sprint粒度 | Opus 4.6でより粗い粒度でも品質維持できるか | 2-step で十分な場合が多い |

### Session Continuity
| コンポーネント | 検証方法 |
|--------------|---------|
| Haiku supplement | compact後のresume品質をsupplement有無で比較 |
| assets.json 詳細度 | 必要最小限のフィールドを特定 |

## 監査プロセス

### データソース

- **主（hook 実績）**: `cc-harness-metrics` — hook 自己ログ `$HOME/.local/state/claude/harness-events.jsonl` の集計
  （XDG_STATE_HOME は意図的に不使用。stop-hook の Deno shebang が `${HOME}` しか展開できず、
  bash/TS/集計の出力先を確実に一致させるため固定パス）。
  transcript には hook の deny/block 決定が記録されない（hook stdout は jsonl に残らない）ため、hook 自身が
  `hooks/lib/harness-log.{sh,ts}` 経由で残すイベントが唯一の実測データ。
- **主（skill 実績）**: `~/.config/claude/projects/**/*.jsonl` — `"skill":"<name>"` の出現を rg で集計（Skill tool 呼び出し回数）
- **補助**: `ai/log/sessions/` — compact 頻度・セッション継続時間
- **組み込み**: `/insights` コマンドのセッション分析レポート

### 手順

1. `cc-harness-metrics --days 30` で hook の発火・ブロック実績を取得
2. `cc-harness-metrics` の Goal funnel セクションで outcome 分布、open、平均/最大 iteration を確認
3. `block:stop_gate` の reason サンプル 5件を確認し、妥当でない誤 block は `hooks/data/stop-hook-counterexamples.md` に追記
4. `~/.config/claude/projects/**/*.jsonl` から skill 使用回数を集計（`rg -o '"skill":\s*"[^"]+"' | sort | uniq -c`）
5. `/insights` でセッション分析レポートを取得
6. ai/log/sessions/ は compact 頻度・セッション継続時間の補助データとして使用
7. 各skillの使用頻度と効果を分析（30日で発火 0 のコンポーネントも、重大度と precision を見て「直すか畳むか」を判断する）
8. stop-hook 誤判定レビュー（下記）を実施
9. レポートを生成

### stop-hook 誤判定レビュー（反例追記ループ）

judge（Haiku）の誤 block/誤 allow を反例としてプロンプトに蓄積し、precision を上げる運用。

1. `harness-events.jsonl` から stop-hook の block 決定と reason を抽出:
   `jq -r 'select(.hook=="stop-hook" and (.event|startswith("block:"))) | [.ts,.event,.detail] | @tsv' ~/.local/state/claude/harness-events.jsonl`
2. reason が不自然なもの（質問への回答済みなのに block、ユーザー判断待ちなのに block 等）は
   該当セッションの transcript で文脈を確認し、誤判定か確定する
3. 誤判定は `hooks/data/stop-hook-counterexamples.md` の Entries に 1 行追記
   （フォーマット・注入の仕組みは同ファイルのヘッダ参照。行頭 `- [YYYY-MM-DD]` の
   行だけが judge プロンプトに注入され、最新 30 件で cap）
4. 30 件超過・重複・陳腐化した entry を整理し、`chezmoi apply` で反映

### レポートフォーマット

```
## Harness Audit Report: YYYY-MM

### Hook 有効性
| Hook | 発火回数 | ブロック回数 | 有効率 | 推奨 |
|------|---------|------------|--------|------|

### Skill 使用状況
| Skill | 使用回数 | 品質向上に寄与した回数 | 推奨 |

### 簡素化提案
1. {コンポーネント}: {理由} → {アクション}
```

## 簡素化候補（データに基づいて判断）

| コンポーネント | 仮説 | 検証方法 |
|--------------|------|---------|
| `verify` | evaluator が同等カバレッジを提供する場合、冗長 | evaluator 導入後1ヶ月の品質比較 |
| stop-hook Haiku 呼び出し | Opus 4.6 は停止タイミング判断が改善 | ブロック率の推移を計測 |
| orchestrator の粒度 | Opus 4.6 ではより粗い粒度で十分 | 2-step vs 4-step の品質比較 |

## 絶対に簡素化しないもの

- block-main hook（安全性、コスト: ほぼゼロ）
- block-config-edit hook（行動矯正、コスト: ほぼゼロ）
- block-forbidden-dirs hook（データ保護）
- block-pr-without-review hook（品質ゲート）
- EOL hook（一貫性、コスト: ほぼゼロ）
