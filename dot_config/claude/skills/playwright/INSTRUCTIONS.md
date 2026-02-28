# Playwright CLI ブラウザ操作ガイド

ブラウザ操作は Playwright CLI（`@playwright/cli`）を Bash ツール経由で実行する。
MCP ではなく CLI を使う理由: **トークン消費が約1/4**（MCP は DOM スナップショットや Base64 画像がコンテキストに載るため肥大化する。CLI はファイルに保存してパスだけ返す）。

## 起動モード

### 通常モード（新規ブラウザ）

ログイン不要なサイトや新規セッションで使う。

```bash
playwright-cli open https://example.com
```

### Extension モード（既存 Chrome に接続）

**ログイン済みの Chrome セッションを利用する場合はこちらを使う。**
Chrome にインストールした Playwright MCP Bridge 拡張機能経由で、既存のログイン・Cookie・セッションをそのまま利用できる。

```bash
# トークンを自動取得して接続
PLAYWRIGHT_MCP_EXTENSION_TOKEN=$(playwright-ext-token) playwright-cli open --extension
```

`playwright-ext-token` は Chrome の LevelDB からトークンを自動抽出するスクリプト。手動取得不要。

- Chrome が起動済みで拡張機能が有効であること
- トークン取得に失敗した場合は拡張機能の設定画面 (`chrome-extension://mmlmfjhmonkocbjadbfplnigmagldckm/status.html`) で確認
- extension モードでは `close` しても Chrome 自体は閉じない（接続が切れるだけ）

### Persistent モード（セッション永続化）

初回ログインのみ手動で行い、以降はセッションを保持する場合。

```bash
playwright-cli open --headed --persistent --profile <name> https://example.com
```

## Quick Start

```bash
playwright-cli open https://example.com
playwright-cli snapshot
playwright-cli click e5
playwright-cli fill e12 "検索ワード"
playwright-cli screenshot
playwright-cli close
```

## コマンドリファレンス

### Core

```bash
playwright-cli open [url]               # ブラウザを開く
playwright-cli goto <url>               # URL に遷移
playwright-cli close                    # ブラウザを閉じる
playwright-cli type <text>              # 編集可能な要素にテキスト入力
playwright-cli click <ref> [button]     # クリック
playwright-cli dblclick <ref> [button]  # ダブルクリック
playwright-cli fill <ref> <text>        # テキスト入力
playwright-cli drag <startRef> <endRef> # ドラッグ&ドロップ
playwright-cli hover <ref>              # ホバー
playwright-cli select <ref> <val>       # ドロップダウン選択
playwright-cli upload <file>            # ファイルアップロード
playwright-cli check <ref>              # チェックボックスをオン
playwright-cli uncheck <ref>            # チェックボックスをオフ
playwright-cli snapshot                 # ページスナップショット取得
playwright-cli snapshot --filename=f    # ファイル名指定でスナップショット保存
playwright-cli eval <func> [ref]        # JavaScript 実行
playwright-cli dialog-accept [prompt]   # ダイアログを承認
playwright-cli dialog-dismiss           # ダイアログを却下
playwright-cli resize <w> <h>           # ブラウザウィンドウをリサイズ
```

### Navigation

```bash
playwright-cli go-back                  # 前のページに戻る
playwright-cli go-forward               # 次のページに進む
playwright-cli reload                   # ページをリロード
```

### Keyboard

```bash
playwright-cli press <key>              # キーを押す (Enter, Tab, ArrowDown 等)
playwright-cli keydown <key>            # キーを押し下げる
playwright-cli keyup <key>              # キーを離す
```

### Mouse

```bash
playwright-cli mousemove <x> <y>        # マウスを座標に移動
playwright-cli mousedown [button]       # マウスボタンを押す
playwright-cli mouseup [button]         # マウスボタンを離す
playwright-cli mousewheel <dx> <dy>     # マウスホイールをスクロール
```

### Save as

```bash
playwright-cli screenshot [ref]         # スクリーンショットを保存（要素指定可）
playwright-cli screenshot --filename=f  # ファイル名指定で保存
playwright-cli pdf                      # ページを PDF として保存
playwright-cli pdf --filename=page.pdf  # ファイル名指定で PDF 保存
```

### Tabs

```bash
playwright-cli tab-list                 # タブ一覧
playwright-cli tab-new [url]            # 新しいタブを開く
playwright-cli tab-close [index]        # タブを閉じる
playwright-cli tab-select <index>       # タブを切り替え
```

### Storage

```bash
playwright-cli state-save [filename]    # 認証状態を保存
playwright-cli state-load <filename>    # 認証状態を復元

# Cookies
playwright-cli cookie-list [--domain]   # Cookie 一覧
playwright-cli cookie-get <name>        # Cookie 取得
playwright-cli cookie-set <name> <val>  # Cookie 設定
playwright-cli cookie-delete <name>     # Cookie 削除
playwright-cli cookie-clear             # 全 Cookie クリア

# LocalStorage
playwright-cli localstorage-list        # localStorage 一覧
playwright-cli localstorage-get <key>   # localStorage 取得
playwright-cli localstorage-set <k> <v> # localStorage 設定
playwright-cli localstorage-delete <k>  # localStorage 削除
playwright-cli localstorage-clear       # localStorage クリア

# SessionStorage
playwright-cli sessionstorage-list      # sessionStorage 一覧
playwright-cli sessionstorage-get <k>   # sessionStorage 取得
playwright-cli sessionstorage-set <k> <v> # sessionStorage 設定
playwright-cli sessionstorage-delete <k>  # sessionStorage 削除
playwright-cli sessionstorage-clear     # sessionStorage クリア
```

### Network

```bash
playwright-cli route <pattern> [opts]   # ネットワークリクエストをモック
playwright-cli route-list               # アクティブなルート一覧
playwright-cli unroute [pattern]        # ルートを削除
```

### DevTools

```bash
playwright-cli console [min-level]      # コンソールメッセージ一覧
playwright-cli network                  # ネットワークリクエスト一覧
playwright-cli run-code <code>          # Playwright コードスニペットを実行
playwright-cli tracing-start            # トレース記録開始
playwright-cli tracing-stop             # トレース記録停止
playwright-cli video-start              # ビデオ記録開始
playwright-cli video-stop [filename]    # ビデオ記録停止
```

### Open パラメータ

```bash
playwright-cli open --browser=chrome    # 特定ブラウザを使用
playwright-cli open --extension         # ブラウザ拡張機能経由で接続
playwright-cli open --persistent        # 永続プロファイルを使用
playwright-cli open --profile=<path>    # カスタムプロファイルディレクトリ
playwright-cli open --config=file.json  # 設定ファイルを使用
playwright-cli open --headed            # ヘッド付きモード（ブラウザ表示）
playwright-cli close                    # ブラウザを閉じる
playwright-cli delete-data              # セッションのユーザーデータを削除
```

### Snapshots

各コマンド実行後、playwright-cli はブラウザ状態のスナップショットを自動的に提供する。

```bash
> playwright-cli goto https://example.com
### Page
- Page URL: https://example.com/
- Page Title: Example Domain
### Snapshot
[Snapshot](.playwright-cli/page-2026-02-14T19-22-42-679Z.yml)
```

`--filename` 未指定時はタイムスタンプ付きファイルが自動生成される。ワークフロー成果物の場合は `--filename=` を使う。

### Sessions

```bash
playwright-cli -s=name <cmd>            # 名前付きセッションでコマンド実行
playwright-cli -s=name close            # 名前付きブラウザを停止
playwright-cli -s=name delete-data      # 名前付きセッションのデータ削除
playwright-cli list                     # 全セッション一覧
playwright-cli close-all                # 全ブラウザを閉じる
playwright-cli kill-all                 # 全ブラウザプロセスを強制終了
```

## 実行時の行動ルール

1. **snapshot → 操作の繰り返し**: ページ操作は必ず `snapshot` で要素参照を取得してから行う。参照なしで操作しない
2. **スクリーンショットはファイル経由**: `screenshot` で保存し、Read ツールで画像を確認する。コンテキストに Base64 を載せない
3. **操作後は状態確認**: クリックや入力後は `snapshot` か `screenshot` で結果を確認する
4. **認証状態の保存**: ログインが必要なサイトでは `state-save` で認証状態を保存し、次回は `state-load` で復元する
5. **終了時は必ず `close`**: ブラウザを開いたら必ず閉じる。ゾンビプロセスが残った場合は `kill-all` で対処
6. **eval で効率的にデータ取得**: テキスト内容の取得は `eval` で JavaScript を実行する方が snapshot より効率的
