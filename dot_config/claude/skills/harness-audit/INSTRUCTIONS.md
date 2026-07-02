# Harness Audit — コンポーネント有効性検証

## 原則

> "every component in a harness encodes an assumption about what the model
> can't do on its own, and those assumptions are worth stress testing"

モデルが進化すれば、不要になるscaffoldingがある。
定期的に各コンポーネントの有効性を検証し、不要なものは除去する。

## 監査対象と検証方法

### Hooks
| Hook | 検証方法 | 除去候補の条件 |
|------|---------|---------------|
| stop-hook | `cc-harness-metrics` の stop-hook block rate | ブロック率 < 5% が3ヶ月続く |
| block-main | `cc-harness-metrics` で deny 回数を確認 | 発火がない（行動変化済み） |
| block-config-edit | 同上 | 発火がない |
| block-pr-without-review | `cc-harness-metrics` の deny/warn + marker file の作成頻度 | 常にreview後にPRを作成している |
| eol hook | `projects/**/*.jsonl` の PostToolUse 出力を確認 | 修正がほぼ発生しない |

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

- **主（hook 実績）**: `cc-harness-metrics` — hook 自己ログ `${XDG_STATE_HOME:-~/.local/state}/claude/harness-events.jsonl` の集計。
  transcript には hook の deny/block 決定が記録されない（hook stdout は jsonl に残らない）ため、hook 自身が
  `hooks/lib/harness-log.{sh,ts}` 経由で残すイベントが唯一の実測データ。
- **主（skill 実績）**: `~/.config/claude/projects/**/*.jsonl` — `"skill":"<name>"` の出現を rg で集計（Skill tool 呼び出し回数）
- **補助**: `ai/log/sessions/` — compact 頻度・セッション継続時間
- **組み込み**: `/insights` コマンドのセッション分析レポート

### 手順

1. `cc-harness-metrics --days 30` で hook の発火・ブロック実績を取得
2. `~/.config/claude/projects/**/*.jsonl` から skill 使用回数を集計（`rg -o '"skill":\s*"[^"]+"' | sort | uniq -c`）
3. `/insights` でセッション分析レポートを取得
4. ai/log/sessions/ は compact 頻度・セッション継続時間の補助データとして使用
5. 各skillの使用頻度と効果を分析（30日で発火 0 のコンポーネントは「直すか畳むか」を判断する）
6. レポートを生成

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
