# Datadog pup CLI

Datadog APIのCLIラッパー。OAuth2認証で動作（DD_API_KEY不要）。

## 認証

```bash
pup auth login         # OAuth2ブラウザ認証（推奨）
pup auth status        # 認証状態確認（トークン自動リフレッシュ）
pup auth refresh       # トークンリフレッシュ（ブラウザ不要）
pup auth logout        # 認証情報クリア
pup test               # 接続テスト（設定・認証を一括確認）
```

**トークンは約1時間で期限切れ**。401/403エラー時は `pup auth refresh` → 失敗なら `pup auth login`。

### Headless/CI（ブラウザなし）

```bash
export DD_API_KEY=your-api-key
export DD_APP_KEY=your-app-key
export DD_SITE=datadoghq.com
```

## コマンドパターン

```bash
pup <domain> <action> [--flags]
pup <domain> <subgroup> <action> [--flags]
```

### グローバルフラグ

| フラグ | 説明 |
|--------|------|
| `-o json\|table\|yaml` | 出力形式（デフォルト: json） |
| `-y, --yes` | 確認プロンプトスキップ |
| `--verbose` | HTTPリクエスト詳細表示（デバッグ用） |
| `--limit N` | 結果件数制限 |

### 時間指定（--from / --to / --duration）

相対: `1h`, `30m`, `7d`, `1w`, `1M`, `"5 minutes"`, `-2h`
絶対: Unixタイムスタンプ(秒), ISO 8601
特殊: `now`

## 主要コマンド

### モニター
```bash
pup monitors list [--name="CPU" --tag="env:production" --status="Alert" --limit 10]
pup monitors get <id> [--json]
pup monitors search --query="tag:env:prod"
pup monitors create --name "High CPU" --type "metric alert" \
  --query "avg(last_5m):avg:system.cpu.user{env:prod} > 80" \
  --message "CPU high @slack-ops"
pup monitors mute --id 12345 --duration 1h
pup monitors mute --id 12345 --end "2024-01-15T18:00:00Z"
pup monitors unmute --id 12345
```
⚠️ monitors listはデフォルト最大200件。--nameはサブストリングマッチ。--tagは複数指定可。

### ログ
```bash
pup logs search --query="status:error" --from="1h"
pup logs search --query="service:api @http.status_code:500" --from="1h" --limit=100
pup logs search --query="status:error" --from="7d" --storage="flex"
pup logs search --query="@http.status_code:>=500" --from="1h" --json
pup logs aggregate --query="service:web" --from="1h" --compute="count:*" --group-by="status"
pup logs pipelines list
```
ストレージ: `indexes`(リアルタイム), `flex`(コスト最適化), `online-archives`(長期保存)。省略時は全ティア検索。
ソート: `--sort asc|desc`（デフォルト: desc=新しい順）

#### ログ検索構文

| クエリ | 意味 |
|--------|------|
| `error` | 全文検索 |
| `status:error` | タグ一致 |
| `@http.status_code:500` | 属性一致 |
| `@http.status_code:>=400` | 数値範囲 |
| `service:api AND env:prod` | ブーリアン |
| `@message:*timeout*` | ワイルドカード |

### メトリクス
```bash
pup metrics query --query="avg:system.cpu.user{*}" --from="1h"
pup metrics query --query="sum:app.requests{env:prod} by {service}" --from="4h"
pup metrics list --filter="system.*"
```

### APM / トレース
```bash
pup apm services list [--env production]
pup apm services get <name> --json
pup apm service-map --service api-gateway --json
pup apm traces list --service my-service --duration 1h
pup apm traces list --service api --min-duration 500ms --duration 1h
pup apm traces list --service api --status error --duration 1h
pup apm traces list --query "@http.url:/api/users"
pup apm traces get <trace_id> --json
pup apm retention-filters list
```

### ダッシュボード
```bash
pup dashboards list [--tags "team:platform"]
pup dashboards get --id abc-123
pup dashboards create --title "My Dashboard" --description "..." --widgets '[...]'
```

### SLO
```bash
pup slos list [--tag="service:api"]
pup slos get --id slo-123
pup slos history --id slo-123 --duration 30d
```

### Synthetics
```bash
pup synthetics list
pup synthetics results --test-id abc-123
pup synthetics trigger --test-id abc-123
```

### インシデント・オンコール
```bash
pup incidents list [--status="active"]
pup incidents get <id>
pup incidents create --title="API Down" --severity="SEV-1"
pup incidents update --id abc-123 --status stable
pup incidents resolve --id abc-123
pup on-call teams list
pup on-call schedules list
pup on-call who --team platform-team
pup cases search --query="status:open"
```

### イベント
```bash
pup events list --duration 24h
pup events list --tags "source:deploy"
pup events post --title "Deploy started" --text "v1.2.3" --tags "env:prod"
```

### ダウンタイム
```bash
pup downtime list
pup downtime create --scope "env:staging" --duration 2h --message "Maintenance"
pup downtime create --scope "env:prod" --monitor-tags "team:platform" \
  --start "2024-01-15T02:00:00Z" --end "2024-01-15T06:00:00Z"
pup downtime cancel --id 12345
```

### インフラ・セキュリティ
```bash
pup infrastructure hosts list [--filter="env:production"]
pup hosts list --limit 50
pup hosts mute --hostname web-01 --duration 1h
pup tags list
pup security rules list
pup security signals list --from="1h" [--severity critical]
pup audit-logs search --query="@action:modified"
```

### サービスカタログ
```bash
pup services list
pup services get --name payment-api
```

### ノートブック・ワークフロー
```bash
pup notebooks list
pup notebooks get --id 12345
pup workflows list
pup workflows trigger --id workflow-123 --input '{"key": "value"}'
```

### ユーザー・チーム
```bash
pup users list
pup teams list
```

## jq活用パターン

```bash
# アラート中のモニター
pup monitors list | jq '[.[] | select(.overall_state == "Alert") | {id, name, overall_state}]'

# ダッシュボード検索
pup dashboards list | jq '.dashboards[] | select(.title | contains("API"))'

# SLOブリーチ確認
pup slos list | jq '.data[] | select(.status.state == "breaching")'

# オーナーなしモニター検出
pup monitors list --json | jq '.[] | select(.tags | contains(["team:"]) | not) | {id, name}'

# ノイジーモニター（頻繁にアラート）
pup monitors list --json | jq 'sort_by(.overall_state_modified) | .[:10] | .[] | {id, name, status: .overall_state}'

# 高ボリュームログソース特定
pup logs search --query="*" --from="1h" --json | jq 'group_by(.service) | map({service: .[0].service, count: length}) | sort_by(-.count)[:10]'
```

## エラーハンドリング

| エラー | 原因 | 対処 |
|--------|------|------|
| 401 Unauthorized | トークン期限切れ | `pup auth refresh` |
| 403 Forbidden | スコープ不足 | アプリキーの権限確認 |
| 404 Not Found | ID/リソース不正 | リソースの存在確認 |
| Rate limited | リクエスト過多 | コール間にディレイ挿入 |

## DD_SITE 一覧

**デフォルトは AP1 (`ap1.datadoghq.com`) を使用する。**

| サイト | 値 |
|--------|------|
| **AP1（優先）** | `ap1.datadoghq.com` |
| US1 | `datadoghq.com` |
| US3 | `us3.datadoghq.com` |
| US5 | `us5.datadoghq.com` |
| EU1 | `datadoghq.eu` |
| US1-FED | `ddog-gov.com` |

## 注意事項

- `DD_SITE=ap1.datadoghq.com` を前提とする（サイトごとにOAuthトークンが別管理）
- 問題切り分けは `pup --verbose <command>` でHTTP詳細確認
- サブコマンド発見: `pup --help` / `pup <command> --help`
- リファレンス: `~/ghq/github.com/DataDog/pup/docs/COMMANDS.md`
