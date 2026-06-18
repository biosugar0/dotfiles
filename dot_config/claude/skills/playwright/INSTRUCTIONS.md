# Playwright CLI ブラウザ操作ガイド

ブラウザ操作は Playwright CLI（`@playwright/cli`）を Bash ツール経由で実行する。
MCP ではなく CLI を使う理由: **トークン消費が約1/4**（MCP は DOM スナップショットや Base64 画像がコンテキストに載るため肥大化する。CLI はファイルに保存してパスだけ返す）。

## 起動モード

### 通常モード（新規ブラウザ）

ログイン不要なサイトや新規セッションで使う。

```bash
playwright-cli open https://example.com
```

### Extension Attach モード（普段使い Chrome に拡張経由で接続）※推奨

**ログイン済みの Chrome セッションを利用する場合はこれを第一選択にする。**
Playwright Extension 経由で普段使いの Chrome にそのまま attach する。CDP WebSocket ハンドシェイクをバイパスするため、Chrome のバージョンや remote debugging の設定状態に依存せず安定して接続できる。

**事前準備（初回のみ）**: Chrome Web Store から [Playwright Extension](https://chromewebstore.google.com/detail/playwright-extension/mmlmfjhmonkocbjadbfplnigmagldckm) をインストール。

```bash
playwright-cli attach --extension=chrome
```

- `attach --extension=chrome` は **バックグラウンド実行**（Bash の `run_in_background=true`）
- 接続後のコマンドは **`-s=chrome` でセッション指定**が必要（例: `playwright-cli -s=chrome goto <url>`）
- `close` は CLI セッションのみ切断し、Chrome 本体は起動したまま

**エージェントからの実行手順**:

1. `attach --extension=chrome` を **バックグラウンド実行**
2. `playwright-cli list` で `browser-type: chrome (attached)` を確認
3. 以降のコマンドは `-s=chrome` を付与: `playwright-cli -s=chrome goto <url>`
4. 終了時: `playwright-cli -s=chrome close`

### CDP Attach モード（フォールバック）

Extension が使えない環境向け。**Chrome 136+ の remote debugging 仕様変更により `<ws connected>` 後のプロトコル初期化で hang するケースがある**（Chrome 149 で確認済み）。この問題が発生したら Extension モードに切り替えること。

**事前準備**: Chrome で `chrome://inspect/#remote-debugging` を開き、「Allow remote debugging for this browser instance」を ON にする（Chrome 144+ 必須）。

```bash
playwright-cli attach --cdp=chrome
```

対応チャンネル: `chrome`, `chrome-beta`, `chrome-dev`, `chrome-canary`, `msedge`, `msedge-beta`, `msedge-dev`, `msedge-canary`。
任意の CDP エンドポイントに繋ぐ場合は `--cdp=http://localhost:9222` のように URL を渡す。

- 初回接続時（および Chrome 再起動後・許可失効後）に Chrome 側で許可ダイアログが出る → 許可
- `close` は CLI セッションのみ切断し、Chrome 本体は起動したまま
- 接続中は「Chrome is being controlled by automated test software」バナーが表示される

**エージェントからの実行手順（attach はセッション維持のため blocking）**:

1. `attach --cdp=chrome` は **必ずバックグラウンド実行**（Bash の `run_in_background=true`）。foreground だと hang に見える
2. `playwright-cli list` で `browser-type: chrome (attached)` を確認
3. `(no browsers)` のままなら bg 出力の Call log を読んで切り分け:
   - `<ws connected>` まで到達して timeout → **Chrome 136+ の CDP 初期化 hang**。Extension モード (`--extension=chrome`) に切り替える
   - `<ws connecting>` まで出て停止 → **初回ダイアログ未承認 / 許可失効**。ユーザーに Chrome で Allow してもらい、再度 bg 実行
   - `DevToolsActivePort file not found` → **ブラウザ未起動 / トグル OFF / Chrome 144 未満**。ブラウザ起動 + トグル ON を依頼
4. **channel-name attach** の診断目的で `curl http://localhost:9222/json/version` を使わない。Chrome 144+ では 404 が正常で誤診の元
5. CDP タイムアウトは環境変数 `PLAYWRIGHT_MCP_CDP_TIMEOUT` で制御可能（デフォルト 30000ms、0 で無効化）

**重要**: `attach --cdp=chrome` は **chrome の全タブ** の console event を listening する。session 切れの SaaS や切断状態 telemetry など `console.error` を秒間数百件以上発火するタブが他に開いていると、playwright-cli の event loop が詰まり page-level 操作が無限 hang する。詳細は末尾「hang 時の対処」参照。

### Persistent モード（セッション永続化）

初回ログインのみ手動で行い、以降はセッションを保持する場合。

```bash
playwright-cli open --headed --persistent --profile <name> https://example.com
```

## Quick Start

```bash
# 新規ブラウザ
playwright-cli open https://example.com
playwright-cli snapshot
playwright-cli click e5
playwright-cli fill e12 "検索ワード"
playwright-cli screenshot
playwright-cli close

# 普段使い Chrome に attach（推奨）
playwright-cli attach --extension=chrome   # bg 実行
playwright-cli -s=chrome goto https://example.com
playwright-cli -s=chrome snapshot
playwright-cli -s=chrome screenshot
playwright-cli -s=chrome close
```

## コマンドリファレンス

### Core

```bash
playwright-cli open [url]               # ブラウザを開く
playwright-cli attach --extension=chrome # 普段使い Chrome に拡張経由で接続（推奨）
playwright-cli attach --cdp=chrome      # 普段使い Chrome に CDP 接続（フォールバック）
playwright-cli attach [name]            # 起動中の Playwright ブラウザに attach
playwright-cli detach                   # attach 中のブラウザから切断（ブラウザは残る）
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

### Open / Attach パラメータ

```bash
playwright-cli open --browser=chrome    # 特定ブラウザを使用
playwright-cli open --persistent        # 永続プロファイルを使用
playwright-cli open --profile=<path>    # カスタムプロファイルディレクトリ
playwright-cli open --headed            # ヘッド付きモード（ブラウザ表示）
playwright-cli open --config=file.json  # 設定ファイル (.playwright/cli.config.json)
playwright-cli close                    # ブラウザを閉じる
playwright-cli delete-data              # セッションのユーザーデータを削除
playwright-cli config-print             # 有効な設定の確認
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

`--filename` 未指定時は `.playwright-cli/` にタイムスタンプ付きファイルが自動生成される。`--filename=` は **cwd 相対**のため、`.playwright-cli/` 配下に置きたいときは `--filename=.playwright-cli/foo.yml` のように prefix を付ける（prefix 無しだと cwd 直下に散らかる）。

### Sessions

```bash
playwright-cli -s=name <cmd>            # 名前付きセッションでコマンド実行
playwright-cli -s=name close            # 名前付きブラウザを停止
playwright-cli -s=name delete-data      # 名前付きセッションのデータ削除
playwright-cli list                     # 全セッション一覧
playwright-cli close-all                # 全ブラウザを閉じる
playwright-cli kill-all                 # 全ブラウザプロセスを強制終了
```

## 接続モードの選択フロー

ログイン済み Chrome を利用したい場合の優先順位:

1. **Extension Attach** (`--extension=chrome`): 第一選択。Chrome バージョン非依存で安定
2. **CDP Attach** (`--cdp=chrome`): Extension が使えない環境向け。Chrome 136+ で hang する場合あり
3. **Persistent** (`--persistent --profile`): attach 不可で新規ブラウザが必要な場合

CDP Attach で `<ws connected>` 後にタイムアウトしたら、**即座に Extension モードに切り替える**（リトライしても改善しない）。

## 実行時の行動ルール

1. **snapshot → 操作の繰り返し**: ページ操作は必ず `snapshot` で要素参照を取得してから行う。参照なしで操作しない
2. **スクリーンショットはファイル経由**: `screenshot` で保存し、Read ツールで画像を確認する。コンテキストに Base64 を載せない
3. **操作後は状態確認**: クリックや入力後は `snapshot` か `screenshot` で結果を確認する
4. **認証状態の保存**: ログインが必要なサイトでは `state-save` で認証状態を保存し、次回は `state-load` で復元する
5. **終了時は必ず `close`**: ブラウザを開いたら必ず閉じる。ゾンビプロセスが残った場合は `kill-all` で対処
6. **eval で効率的にデータ取得**: テキスト内容の取得は `eval` で JavaScript を実行する方が snapshot より効率的

## hang 時の対処（CDP Attach 限定）

CDP Attach (`--cdp=chrome`) 使用時に特定のコマンドが返らないときの切り分けと対処。**Extension Attach (`--extension=chrome`) ではこの問題は発生しない**。

### 症状: page-level 操作が hang、screenshot だけ通る傾向

- `snapshot` / `eval` / `goto` / `tab-list` / `tab-new` / `run-code` が無限に応答しない
- 一方 `screenshot` は比較的通りやすい (console event 処理を踏みにくい操作経路のため)
- timeout 系 option を渡しても効かない (event loop 自体がブロックされている場合)

`screenshot のみ通る` は確定根拠ではないが、強いシグナル。下記の診断と合わせて判断。

#### 原因

attach 中の chrome の **どこかのタブ** が `console.error` を大量発火しており、playwright-cli の console event listener が詰まっている。典型的には認証が切れた SaaS、切断状態 telemetry を持つ Web app、無限 retry する API endpoint など。

#### 診断

```bash
find .playwright-cli -maxdepth 1 -name 'console-*.log' -type f | wc -l
du -ch .playwright-cli/console-*.log 2>/dev/null | tail -1
```

短時間で数十〜数百ファイル / MB 級の蓄積、または単一ファイルの異常な肥大があれば疑い濃厚 (CLI は tab/navigation 単位で同一 log に追記する場合があるため、1 ファイルだけ巨大化するケースもある)。中身を見れば flood 元の URL も特定できる:

```bash
grep -hoE 'https?://[^[:space:]]+' .playwright-cli/console-*.log 2>/dev/null | sort -u | head
```

#### 対処

1. Chrome 上で該当タブを **手で閉じる** (kill 不要、Chrome 操作のみ)
2. 数秒で queue 中の操作が一斉解消する
3. CDP 接続は維持されるので **再 attach 不要**

### hang したコマンドだけを安全に kill

attach プロセスを温存したまま、stuck な個別コマンドだけ落とす。**Bash tool が把握している該当ジョブ ID / PID を直接 kill するのが最も安全**。

```bash
# 該当 PID を特定 (出力を目視確認してから個別に kill)
pgrep -lf 'playwright-cli <stuck-cmd>'
# 得た PID を 1 件ずつ
kill <PID>
```

`xargs -r kill` のような一括処理は避ける: macOS/BSD `xargs` は `-r` 非互換、また同一 `<stuck-cmd>` を実行中の別 workspace / session を巻き込む恐れがある。`playwright-cli list` で `chrome (attached)` が残っていれば成功。

attach `--cdp=chrome` 中に避けるべき操作 (NG):

- `playwright-cli kill-all`
- `pkill -9 playwright-cli`
- attach プロセス自体の kill

→ playwright-cli 側の CDP セッションが切れる。次回 attach が必要となり、環境によっては Chrome 側の `chrome://inspect/#remote-debugging` Allow ダイアログ再承認も求められる。`open` / `--persistent` モードのゾンビ整理に対しては `kill-all` は引き続き有効 (この衝突回避は attach `--cdp` セッション中のみの制約)。

### CDP 承認のライフサイクル

- attach プロセス (`attach --cdp=chrome`、bg 実行) が生存している間は接続維持。Chrome 承認は通常そのまま使われる
- attach プロセスが終了 / kill されると再 attach 必要。Chrome の許可状態が失効していれば併せて再承認を求められる
- 個別コマンド (snapshot / eval 等) は別プロセス。これらを kill しても attach は無事
