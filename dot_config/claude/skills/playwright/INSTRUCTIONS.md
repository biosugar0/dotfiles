# Playwright CLI ブラウザ操作ガイド

ブラウザ操作は Playwright CLI（`@playwright/cli`）を Bash ツール経由で実行する。
MCP ではなく CLI を使う理由: **トークン消費が約1/4**（MCP は DOM スナップショットや Base64 画像がコンテキストに載るため肥大化する。CLI はファイルに保存してパスだけ返す）。

## 起動モード

### 通常モード（新規ブラウザ）

ログイン不要なサイトや新規セッションで使う。

```bash
playwright-cli open https://example.com
```

### Attach モード（普段使い Chrome に CDP 接続）※推奨

**ログイン済みの Chrome セッションを利用する場合はこれを第一選択にする（v0.1.8+）。**
拡張機能不要で、普段使いの Chrome / Edge にそのまま attach する。

**事前準備（初回のみ）**: Chrome で `chrome://inspect/#remote-debugging` を開き、「Allow remote debugging for this browser instance」を ON にする（Chrome 144+ 必須）。

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
2. 5〜20 秒待ってから `playwright-cli list` で `browser-type: chrome (attached)` を確認
3. `(no browsers)` のままなら bg 出力の Call log を読んで切り分け（3 分岐）:
   - `<ws connecting>` まで出て停止 → DevToolsActivePort は読めている。**初回ダイアログ未承認 / Chrome 再起動後の許可失効** が濃厚。ユーザーに Chrome をフォアグラウンド化 → `chrome://inspect/#remote-debugging` トグルが ON であること確認 → 表示されているダイアログを Allow してもらう（エージェント側からはダイアログ操作不可）。承認後は bg プロセスが既に Error 終了している可能性があるため `attach --cdp=chrome` を再度 bg 実行してから `list` で確認し直す
   - `DevToolsActivePort file not found`、または `<ws preparing> reading ...DevToolsActivePort` は出るが `<ws connecting>` まで進まない → **対象ブラウザ未起動 / channel 指定ミス / `chrome://inspect/#remote-debugging` トグル OFF / Chrome または Edge 144 未満**。ブラウザ起動 + トグル ON を依頼、144 未満なら Extension モードへフォールバック
   - `<ws preparing> reading ...DevToolsActivePort` 自体が無い → CLI version / unsupported platform / channel-name attach ではない前段の問題。`playwright-cli --version` で 0.1.8+ を確認
4. **channel-name attach**（`--cdp=chrome` など）の診断目的で `curl http://localhost:9222/json/version` を使わない。Chrome 144+ の browser-instance remote debugging では 404 が正常で誤診の元。ただし `--cdp=http://localhost:9222` のように旧来の CDP endpoint URL に接続するケースでは `/json/version/` が正当な応答確認手段なので区別すること
5. この dotfiles の cage `claude-code` preset 配下では動作確認済み: Chrome user data dir と localhost WebSocket が preset で常時許可されているため追加許可不要（別 preset / 別 sandbox ではこの限りではない）

**重要**: `attach --cdp=chrome` は **chrome の全タブ** の console event を listening する。session 切れの SaaS や切断状態 telemetry など `console.error` を秒間数百件以上発火するタブが他に開いていると、playwright-cli の event loop が詰まり page-level 操作 (`snapshot` / `eval` / `goto` / `tab-list` / `tab-new` / `run-code`) が無限 hang する。`screenshot` のみ通る症状なら確実に該当。**attach 前に retry が頻発しているタブを閉じる** こと。詳細・診断手順は末尾「hang 時の対処」参照。

### Extension モード（Playwright MCP Bridge 拡張経由）

`attach --cdp` が使えない環境（Chrome 144 未満、chrome://inspect トグル利用不可）向けのフォールバック。

```bash
PLAYWRIGHT_MCP_EXTENSION_TOKEN=$(playwright-ext-token) playwright-cli open --extension
```

`playwright-ext-token` は Chrome の LevelDB からトークンを自動抽出。トークン取得失敗時は拡張の設定画面 (`chrome-extension://mmlmfjhmonkocbjadbfplnigmagldckm/status.html`) で確認。`close` で Chrome 本体は閉じない。

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
playwright-cli attach [name]            # 起動中の Playwright ブラウザに attach
playwright-cli attach --cdp=chrome      # 普段使い Chrome に CDP 接続 (v0.1.8+)
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

## 実行時の行動ルール

1. **snapshot → 操作の繰り返し**: ページ操作は必ず `snapshot` で要素参照を取得してから行う。参照なしで操作しない
2. **スクリーンショットはファイル経由**: `screenshot` で保存し、Read ツールで画像を確認する。コンテキストに Base64 を載せない
3. **操作後は状態確認**: クリックや入力後は `snapshot` か `screenshot` で結果を確認する
4. **認証状態の保存**: ログインが必要なサイトでは `state-save` で認証状態を保存し、次回は `state-load` で復元する
5. **終了時は必ず `close`**: ブラウザを開いたら必ず閉じる。ゾンビプロセスが残った場合は `kill-all` で対処
6. **eval で効率的にデータ取得**: テキスト内容の取得は `eval` で JavaScript を実行する方が snapshot より効率的

## hang 時の対処

特定のコマンドが返らないときの切り分けと対処。

### 症状: page-level 操作が hang、screenshot だけ通る

- `snapshot` / `eval` / `goto` / `tab-list` / `tab-new` / `run-code` が無限に応答しない
- 一方 `screenshot` (browser-level CDP 直叩き) は通る
- timeout 系 option を渡しても効かない (event loop 自体がブロックされているため)

#### 原因

attach 中の chrome の **どこかのタブ** が `console.error` を大量発火しており、playwright-cli の console event listener が詰まっている。典型的には認証が切れた SaaS、切断状態 telemetry を持つ Web app、無限 retry する API endpoint など。

#### 診断

```bash
ls .playwright-cli/console-*.log | wc -l
du -sh .playwright-cli/
```

短時間で数十〜数百ファイル / MB 級の蓄積があれば確定。中身を見れば flood 元の URL も特定できる:

```bash
grep -hoE 'https?://[^[:space:]]+' .playwright-cli/console-*.log | sort -u | head
```

#### 対処

1. Chrome 上で該当タブを **手で閉じる** (kill 不要、Chrome 操作のみ)
2. 数秒で queue 中の操作が一斉解消する
3. CDP 接続は維持されるので **再 attach 不要**

### hang したコマンドだけを安全に kill

attach プロセスを温存したまま、stuck な個別コマンドだけ落とす:

```bash
pgrep -lf "playwright-cli <stuck-cmd>" | awk '{print $1}' | xargs -r kill
```

`playwright-cli list` で `chrome (attached)` が残っていれば成功。

絶対やってはいけない (NG):

- `playwright-cli kill-all`
- `pkill -9 playwright-cli`
- attach プロセス自体の kill

→ Chrome 側の CDP 承認が失効し、再度 `chrome://inspect/#remote-debugging` の Allow ダイアログ承認をユーザーに依頼することになる。

### CDP 承認のライフサイクル

- attach プロセス (`attach --cdp=chrome`、bg 実行) が生存している間は Chrome 承認維持
- attach プロセスが終了 / kill されると次回 attach で再承認必要
- 個別コマンド (snapshot / eval 等) は別プロセス。これらを kill しても attach は無事
