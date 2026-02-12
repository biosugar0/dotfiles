---
name: pup
description: "Datadog APIをCLIから操作する。モニター、ダッシュボード、ログ、メトリクス、インシデント等の確認・管理に使用。Use when: datadog,Datadog,DD,モニター,monitor,アラート,alert,ダッシュボード,dashboard,SLO,エラーバジェット,インシデント,incident,pup,traces,APM"
---

# Datadog pup CLI

Datadog APIのCLIラッパー。OAuth2認証で動作（DD_API_KEY不要）。

## 認証

```bash
pup auth status        # 認証状態確認（トークン自動リフレッシュ）
pup auth login         # 未認証時（ブラウザ認証）
pup test               # 接続テスト（設定・認証を一括確認）
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

### 時間指定（--from / --to）

相対: `1h`, `30m`, `7d`, `1w`, `1M`, `"5 minutes"`, `-2h`
絶対: Unixタイムスタンプ(秒), ISO 8601
特殊: `now`

## 主要コマンド

### モニタリング
```bash
pup monitors list [--name="CPU" --tag="env:production"]
pup monitors get <id>
pup monitors search --query="tag:env:prod"
pup dashboards list
pup slos list [--tag="service:api"]
```
⚠️ monitors listはデフォルト最大200件。--nameはサブストリングマッチ。--tagは複数指定可。

### ログ
```bash
pup logs search --query="status:error" --from="1h"
pup logs search --query="service:api @http.status_code:500" --from="1h" --limit=100
pup logs search --query="status:error" --from="7d" --storage="flex"
pup logs aggregate --query="service:web" --from="1h" --compute="count:*" --group-by="status"
```
ストレージ: `indexes`(リアルタイム), `flex`(コスト最適化), `online-archives`(長期保存)。省略時は全ティア検索。
ソート: `--sort asc|desc`（デフォルト: desc=新しい順）

### メトリクス
```bash
pup metrics query --query="avg:system.cpu.user{*}" --from="1h"
pup metrics query --query="sum:app.requests{env:prod} by {service}" --from="4h"
pup metrics list --filter="system.*"
```

### インシデント・オンコール
```bash
pup incidents list [--status="active"]
pup incidents get <id>
pup incidents create --title="API Down" --severity="SEV-1"
pup on-call teams list
pup cases search --query="status:open"
```

### APM
```bash
pup apm services list --env=production --start=<epoch> --end=<epoch>
pup apm services stats --env=production --start=<epoch> --end=<epoch>
pup apm entities list --env=production --start=<epoch> --end=<epoch>
pup apm dependencies list --env=prod --start=<epoch> --end=<epoch>
```
⚠️ APMコマンドはUnixタイムスタンプ(秒)必須。相対時間不可。`--env`必須。

### インフラ・セキュリティ
```bash
pup infrastructure hosts list [--filter="env:production"]
pup tags list
pup security rules list
pup security signals list --from="1h"
pup audit-logs search --query="@action:modified"
```

## jq活用パターン

```bash
# アラート中のモニター
pup monitors list | jq '[.[] | select(.overall_state == "Alert") | {id, name, overall_state}]'

# ダッシュボード検索
pup dashboards list | jq '.dashboards[] | select(.title | contains("API"))'

# SLOブリーチ確認
pup slos list | jq '.data[] | select(.status.state == "breaching")'
```

## 生API（pup未対応エンドポイント用）

traces等pup未実装のAPIは、keychainのOAuth2トークンで直接叩く。

### トークン取得＋ヘルパー定義

```bash
# リフレッシュ＋トークン取得＋ヘルパー定義を一括実行
pup auth status > /dev/null 2>&1 \
  && DD_TOKEN=$(security find-generic-password -s "datadog-cli" -a "oauth:${DD_SITE}" -w | jq -r '.accessToken') \
  && dd_api() { curl -s -H "Authorization: Bearer $DD_TOKEN" -H "Content-Type: application/json" "https://api.${DD_SITE}$1" "${@:2}"; }
```

### エンドポイント例

```bash
# Traces検索
dd_api "/api/v2/spans/events/search" \
  -d '{"filter":{"query":"service:xxx","from":"now-1h","to":"now"},"page":{"limit":10}}'

# APMサービス一覧（filter[env]必須）
dd_api "/api/v2/apm/services?start=$(($(date +%s)-86400))&end=$(date +%s)&filter%5Benv%5D=production"

# APMサービス統計
dd_api "/api/v2/apm/services/stats?start=$(($(date +%s)-3600))&end=$(date +%s)&filter%5Benv%5D=production"

# 任意のエンドポイント
dd_api "/api/v1/<endpoint>"
dd_api "/api/v2/<endpoint>"
```

## 注意事項

- `DD_SITE` 環境変数でサイト指定（サイトごとにOAuthトークンが別管理）
- 問題切り分けは `pup --verbose <command>` でHTTP詳細確認
- リファレンス: `pup <command> --help` / `~/ghq/github.com/DataDog/pup/docs/COMMANDS.md`
