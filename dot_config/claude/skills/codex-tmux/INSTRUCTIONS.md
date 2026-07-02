# codex-tmux: tmux経由でcodex CLIと対話

tmux paneを分割してcodex(gpt-5)をinteractive modeで起動し、対話する。
codex MCPは使わない。必ずこの手順で対話すること（バックエンドは下記判定に従い tmux または Herdr）。

## バックエンド判定

`HERDR_ENV=1` かつ Herdr サーバーが running のときのみ **Herdr バックエンド**を使う。
それ以外は従来どおり **tmux バックエンド**（本書の既存手順 Step 0〜6）を使う。

```bash
if [ "${HERDR_ENV:-}" = "1" ] \
   && herdr status server --json 2>/dev/null | grep -q '"running":true'; then
  CODEX_BACKEND=herdr   # → 「Herdr バックエンド対応表」の H-Step 0〜6 を使う
else
  CODEX_BACKEND=tmux    # → 既存手順（Step 0〜6）を使う
fi
echo "[codex-tmux] backend=$CODEX_BACKEND"
```

注: `herdr status server` はサーバー停止時も exit 0 を返すため、終了コードではなく
`--json` 出力の `"running":true` で判定すること。

## 前提条件

- tmux バックエンド時: tmux内で動作していること（`$TMUX`が設定されていること）
- Herdr バックエンド時: `HERDR_ENV=1` かつ `$HERDR_PANE_ID` が設定されていること
- `cage`コマンドが利用可能であること
- `codex`コマンドが利用可能であること

## pane命名規則

paneにはタイトルを付けて名前で管理する。pane IDは変数に保持しつつ、タイトルで識別可能にする。

- **命名形式**: `codex-<topic>` （例: `codex-auth-design`, `codex-perf-investigation`）
- タイトルは `select-pane -T` で設定する（Herdr バックエンドでは `herdr pane rename`）
- 既存のcodex paneを再利用する場合、タイトルで検索して特定する

### 既存paneの検索

```bash
# タイトルでcodex paneを検索
tmux list-panes -F '#{pane_id} #{pane_title}' | grep '^codex-'

# Herdr バックエンド時: label で検索
herdr pane list | grep -F 'codex-'
```

## 手順（tmux バックエンド）

Herdr バックエンド時は後述の「Herdr バックエンド対応表」の H-Step 0〜6 を使う。

### Step 0: 位置確認と PARENT_WIN 固定（必須・split 前の境界チェック）

split 前に「自分が今どこにいるか」を必ず出力し、PARENT_WIN を確定して以後全ステップで参照する。
`$TMUX_PANE` が空 / stale なら fail-fast。これを飛ばすと、空 pane id を `-t ""` に渡してアクティブな別 window に着地する事故が起きる。

```bash
# pre-flight: 必須環境変数と pane id の生存確認
[ -n "$TMUX" ] && [ -n "$TMUX_PANE" ] \
  || { echo "[guard:not-in-tmux] not in tmux (TMUX/TMUX_PANE empty)" >&2; return 1 2>/dev/null || exit 1; }
tmux list-panes -a -F '#{pane_id}' | grep -Fqx -- "$TMUX_PANE" \
  || { echo "[guard:stale-tmux-pane] TMUX_PANE=$TMUX_PANE is stale" >&2; return 1 2>/dev/null || exit 1; }

# 親 window を確定（以後の全ステップでこの値を参照）
PARENT_WIN=$(tmux display-message -p -t "$TMUX_PANE" '#{session_id}:#{window_id}')

# state file 置き場（sandbox/cage 跨ぎでも残る場所、$N 形式の値破壊を防ぐ書き方は後述）
# 注: STATE_FILE は呼び出し元 pane (= $TMUX_PANE) ごとに分離する。単一ファイルだと
# 複数 codex-tmux セッション並走時に last-writer-wins で別 pane の state を読み取り、
# 追加質問が他 codex pane に paste されてしまう事故が起きる。
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/codex-tmux"
PANE_KEY=$(printf '%s' "$TMUX_PANE" | tr -c 'A-Za-z0-9' '_')
STATE_FILE="$STATE_DIR/state-${PANE_KEY}.env"
mkdir -p "$STATE_DIR"

# stale state file の掃除（7日超のみ）
# 注1: STATE_DIR は上で必ず HOME 配下に fallback 済み。XDG_STATE_HOME 未設定で
#      `/codex-tmux` を触る事故を防ぐため、ここでも -n / -d でガードする。
# 注2: -mtime +7 は、24h+ 生きている長時間 pane の state を誤って消さないため。
#      短期 cleanup が欲しい場合でも +1 まで下げない（state-missing 事故になる）。
# 注3: pane 自体は kill しない。人が読んでいる Codex pane を消すのは不可逆で危険。
#      hook を増やすより、Step 0 で skill 単体に cleanup を閉じる方が依存が少ない。
[ -n "$STATE_DIR" ] && [ -d "$STATE_DIR" ] \
  && find "$STATE_DIR" -type f -name 'state-*.env' -mtime +7 -delete 2>/dev/null || true

# 位置出力（debug / 事故時の追跡効率化）
echo "[codex-tmux] self: $(tmux display-message -p -t "$TMUX_PANE" 'session=#{session_name} window=#{window_index}:#{window_name} pane=#{pane_index} (#{pane_id})')"
echo "[codex-tmux] PARENT_WIN=$PARENT_WIN"
echo "[codex-tmux] STATE_FILE=$STATE_FILE"
```

### Step 1: pane作成 + codex起動

**重要: 先にzsh paneを作成し、send-keysでcodexを起動する。**
split-windowに直接コマンドを渡すと、引用符のネストやプロンプト内の特殊文字でシェル展開が壊れ、paneが即座に閉じる。

**PR レビュー目的の場合のみ**: skill 同梱の adversarial-review テンプレート
（`~/.config/claude/skills/codex-tmux/templates/adversarial-review.md`）を
プロンプト先頭に prepend する。skeptic 視点・attack surface・finding bar が
固定化され、レビュー出力の質が安定する。
通常のセカンドオピニオンや設計相談には使わない（議論を硬直させるため）。

```bash
# プロンプトをファイルに書き出し
# PR レビュー時は冒頭に adversarial テンプレを差し込む:
#   cat ~/.config/claude/skills/codex-tmux/templates/adversarial-review.md > /tmp/codex-prompt.txt
#   cat >> /tmp/codex-prompt.txt << 'PROMPT'
#   ...レビュー対象とフォーカス...
#   PROMPT
cat > /tmp/codex-prompt.txt << 'PROMPT'
（ここに質問を書く）
PROMPT

# Claude Code自身のpaneの下に分割（全幅水平分割、下30%）
# $TMUX_PANE でClaude Codeが動作しているpaneをターゲットにする
CODEX_PANE=$(tmux split-window -v -f -d -l 30% -t "$TMUX_PANE" -P -F '#{pane_id}') \
  || { echo "[guard:split-failed] tmux split-window が失敗 — abort" >&2; return 1 2>/dev/null || exit 1; }

# post-verify: split が PARENT_WIN に着地したか必ず確認する。
# 必ず select-pane / send-keys 前に検証すること。送信後だと、たとえ別 window に
# 着地していても codex 起動コマンドと初回 prompt が他 pane に流れて副作用が残る。
CHILD_WIN=$(tmux display-message -p -t "$CODEX_PANE" '#{session_id}:#{window_id}')
if [ "$CHILD_WIN" != "$PARENT_WIN" ]; then
  tmux kill-pane -t "$CODEX_PANE" 2>/dev/null
  echo "[guard:wrong-window] split landed in $CHILD_WIN, expected $PARENT_WIN — aborted" >&2
  return 1 2>/dev/null || exit 1
fi

# paneにタイトルを設定（トピックに応じた名前をつける）
tmux select-pane -t "$CODEX_PANE" -T "codex-<topic>"

# repo root を解決して -c で trust_level=trusted を注入
# （worktree/サブディレクトリ起動時の "Do you trust this directory?" プロンプトを抑止）
#
# 注1: codex の -c は dotted key の quoted segment を解釈せず生 split するため、
#      key 側は単一トークン `projects` のみにして値を inline table で渡す。
# 注2: Codex 本体の trust lookup は linked worktree を main repo root に正規化する
#      ため、`--show-toplevel`（worktree root）ではなく `--git-common-dir` の親
#      （main repo の `.git` の親 = main repo root）を trust target にする。
#      bare repo / submodule / custom GIT_DIR / 非 git は intentionally no override
#      （Codex 側の filesystem ベース trust 解決と揃わないので保守的に fallback）。
# 既知制約: repo root path に `'`, `"`, `\` が含まれると shell/TOML quoting が破綻
#           （一般的な repo path では踏まない）。
_git_common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)
if [ -n "$_git_common" ] && [ "$(basename "$_git_common")" = ".git" ]; then
  _codex_root=$(dirname "$_git_common")
else
  _codex_root=""
fi

if [ -n "$_codex_root" ]; then
  tmux send-keys -t "$CODEX_PANE" "cage -- codex --no-alt-screen --dangerously-bypass-approvals-and-sandbox -c 'projects={\"$_codex_root\"={trust_level=\"trusted\"}}' \"\$(cat /tmp/codex-prompt.txt)\"" Enter
else
  tmux send-keys -t "$CODEX_PANE" "cage -- codex --no-alt-screen --dangerously-bypass-approvals-and-sandbox \"\$(cat /tmp/codex-prompt.txt)\"" Enter
fi

# state を永続化（multi-turn の context loss / bash プロセス跨ぎに耐える）
# Step 4 以降で source して CODEX_PANE / PARENT_WIN / PARENT_PANE を復元する。
#
# 重要: tmux の #{session_id} は $N 形式（例: $11）。`KEY=$VAL` 形式で書き出すと
# 値リテラルに `$11` が含まれ、再 source 時に shell が positional parameter として
# 展開して値が破壊される。必ず single-quote で書き出すこと（printf '%s' で safe）。
# 注: ここで「safe」と言えるのは保存値が pane_id (%N) / session_id ($N) / window_id (@N)
# のように single-quote 内で literal 扱いできる ASCII 構成に限られる前提。任意文字列を
# この形式で書き出すと '...' エスケープが破綻するので、その場合は別途 escape が必要。
{
  printf "CODEX_PANE='%s'\n" "$CODEX_PANE"
  printf "PARENT_WIN='%s'\n" "$PARENT_WIN"
  printf "PARENT_PANE='%s'\n" "$TMUX_PANE"
} > "$STATE_FILE"
```

### Step 2: 完了検知

`tmux capture-pane`の出力を5秒間隔で監視し、変化がなくなったら応答完了と判断する。

```bash
prev_content=""
while true; do
  sleep 5
  curr_content=$(tmux capture-pane -t "$CODEX_PANE" -p -S -50)
  if [ "$curr_content" = "$prev_content" ] && [ -n "$curr_content" ]; then
    break
  fi
  prev_content="$curr_content"
done
```

### Step 3: 結果読み取り

```bash
tmux capture-pane -t "$CODEX_PANE" -p -S -100
```

capture-paneはクリーンなテキストを返す。ログの内容を読んで、codexの応答を把握する。

### Step 4: 追加質問（multi-turn）

追加の質問がある場合、`load-buffer` + `paste-buffer` で安全に送信する。
**`send-keys "$(cat ...)"` は使わない。** 改行や特殊文字でEnterが欠落する原因になる。

#### 送信前ガード（必須）

送信前に以下を**必ず**確認する。確認せずにpaste-bufferすると、codexのinteractive UI状態ではテキストがシェルのstdinに流れ、意図しないpaneで実行される。

```bash
# 0. state を復元（bash プロセス跨ぎ / context loss 耐性）
# STATE_FILE は Step 0 と同じ式で再定義（別 bash プロセスから呼ばれるケースに対応）。
# pane 単位に分離された state file を読む前に、必ず古い env var を unset する。
# unset しないと、state file が無くても既存 shell の CODEX_PANE / PARENT_WIN が残っていれば
# state-missing 検知をすり抜け、古い (=別の) codex pane に paste する事故が起きる。
unset CODEX_PANE PARENT_WIN PARENT_PANE
PANE_KEY=$(printf '%s' "$TMUX_PANE" | tr -c 'A-Za-z0-9' '_')
STATE_FILE="${XDG_STATE_HOME:-$HOME/.local/state}/codex-tmux/state-${PANE_KEY}.env"
[ -r "$STATE_FILE" ] \
  || { echo "[guard:state-missing] state file ($STATE_FILE) 不在 — Step 1 からやり直し" >&2; return 1 2>/dev/null || exit 1; }
source "$STATE_FILE"
[ -n "$CODEX_PANE" ] && [ -n "$PARENT_WIN" ] \
  || { echo "[guard:state-invalid] state file の中身が不完全 — Step 1 からやり直し" >&2; return 1 2>/dev/null || exit 1; }

# 1. pane がグローバルに存在するか（-a で全 session/window を走査、scope 暗黙依存を避ける）
tmux list-panes -a -F '#{pane_id}' | grep -Fqx -- "$CODEX_PANE" \
  || { echo "[guard:pane-missing] CODEX_PANE ($CODEX_PANE) が存在しない — Step 1 からやり直し" >&2; return 1 2>/dev/null || exit 1; }

# 2. pane がまだ PARENT_WIN にいるか（move-pane 等で他 window に流れていないか明示確認）
CUR_WIN=$(tmux display-message -p -t "$CODEX_PANE" '#{session_id}:#{window_id}')
[ "$CUR_WIN" = "$PARENT_WIN" ] \
  || { echo "[guard:pane-moved] CODEX_PANE が $CUR_WIN に移動済み (期待 $PARENT_WIN) — abort" >&2; return 1 2>/dev/null || exit 1; }

# 3. codex がプロンプト待ち状態か（glyph は版により ❯ または › のいずれか）
# プロンプト復帰前に paste-buffer すると codex の interactive UI に文字列が流れて
# 意図しない動作を引き起こすため、ここで必ず abort する。Step 2 の完了検知ループを
# 再実行して `[❯›]` を確認できる状態にしてから本ガードをやり直すこと。
last_line=$(tmux capture-pane -t "$CODEX_PANE" -p -S -3 | tail -1)
if ! echo "$last_line" | grep -qE '[❯›]'; then
  echo "[guard:not-ready] codexがプロンプト待ちではない — abort (Step 2 の完了検知ループを回してから本ガードをやり直し)" >&2
  return 1 2>/dev/null || exit 1
fi
```

**禁止事項:**
- **Escapeキーを送信しない** — codexがinteractive UI（タスク選択画面等）を表示中の場合、EscapeはUIキャンセルとして消費され、後続のペースト内容が別paneに流れる原因になる
- codexが `❯` または `›` プロンプト表示になるまで待ってから送信する

#### 送信

```bash
# 追加プロンプトをファイルに書き出し
cat > /tmp/codex-prompt.txt << 'PROMPT'
（ここに追加質問を書く）
PROMPT

# tmuxバッファ経由で貼り付け（改行・特殊文字を安全に送信）
tmux load-buffer /tmp/codex-prompt.txt
tmux paste-buffer -t "$CODEX_PANE"

# 貼り付け完了を待ってからEnterで送信
sleep 0.3
tmux send-keys -t "$CODEX_PANE" Enter
tmux send-keys -t "$CODEX_PANE" Enter
```

その後、Step 2→3を繰り返して応答を読み取る。

### Step 5: レビューマーカー作成

PRレビュー目的でcodexと議論した場合、完了マーカーを作成する。
これがないと `gh pr create` がhookでブロックされる。

```bash
_repo=$(git remote get-url origin 2>/dev/null | sed 's/\.git$//;s|.*/||')
_branch=$(git branch --show-current 2>/dev/null)
_hash=$(git rev-parse --short HEAD 2>/dev/null)
# branch 内の "/" は "_" に置換（slash 入りブランチ名でパスが破綻するため）。
# block-pr-without-review hook のチェック側と同じ置換規則を保つこと。
touch "/tmp/.codex-review-done--${_repo}--${_branch//\//_}--${_hash}"
```

### Step 6: 終了

議論が完了したらpaneを閉じて一時ファイルを削除する。

```bash
PANE_KEY=$(printf '%s' "$TMUX_PANE" | tr -c 'A-Za-z0-9' '_')
tmux kill-pane -t "$CODEX_PANE"
rm -f /tmp/codex-prompt.txt "${XDG_STATE_HOME:-$HOME/.local/state}/codex-tmux/state-${PANE_KEY}.env"
```

## Herdr バックエンド対応表

`CODEX_BACKEND=herdr` のときは、既存の tmux 手順（Step 0〜6）の代わりに以下の H-Step 0〜6 を使う。
tmux 手順は削除しない（両バックエンド併存）。Step 5（レビューマーカー）はバックエンド非依存で共通。

tmux 操作と Herdr CLI の対応:

| tmux | Herdr |
|---|---|
| `$TMUX` / `$TMUX_PANE` の生存確認 | `HERDR_ENV=1` と `$HERDR_PANE_ID`（生存確認は `herdr pane get`） |
| `tmux split-window -v -f -d -l 30% -t "$TMUX_PANE" -P -F '#{pane_id}'` | `herdr pane split "$HERDR_PANE_ID" --direction down --ratio 0.3 --no-focus`（JSON の `result.pane.pane_id` を抽出） |
| `tmux select-pane -t <pane> -T <title>` | `herdr pane rename <pane_id> <title>` |
| `tmux send-keys -t <pane> "<cmd>" Enter`（コマンド起動） | `herdr pane run <pane_id> "<cmd>"`（テキスト+Enter を1リクエストで送る） |
| `tmux load-buffer` + `paste-buffer` + `send-keys Enter`（追加質問） | `herdr pane send-text <pane_id> "<text>"` → `herdr pane send-keys <pane_id> Enter`（複数行もそのまま send-text できる。バッファ経由は不要） |
| `tmux capture-pane` の5秒ポーリングによる完了検知 | `herdr wait output <pane_id> --match '<完了マーカーの正規表現>' --regex --timeout <ms>`（blocking。ポーリングループ自体を廃止） |
| `tmux capture-pane -t <pane> -p -S -100`（内容取得） | `herdr pane read <pane_id> --source recent-unwrapped --lines 100` |
| `tmux kill-pane -t <pane>` | `herdr pane close <pane_id>` |
| state ファイルのキー（tmux pane id） | Herdr pane id（`$HERDR_PANE_ID`）で同じ命名規則（`state-<PANE_KEY>.env`） |

### H-Step 0: 位置確認（必須・split 前の境界チェック）

```bash
# pre-flight: 必須環境変数と pane id の生存確認
[ "${HERDR_ENV:-}" = "1" ] && [ -n "$HERDR_PANE_ID" ] \
  || { echo "[guard:not-in-herdr] not in herdr (HERDR_ENV/HERDR_PANE_ID empty)" >&2; return 1 2>/dev/null || exit 1; }
herdr pane get "$HERDR_PANE_ID" >/dev/null 2>&1 \
  || { echo "[guard:stale-herdr-pane] HERDR_PANE_ID=$HERDR_PANE_ID is stale" >&2; return 1 2>/dev/null || exit 1; }

# state file 置き場。キーは tmux pane id の代わりに Herdr pane id を使う。
# 分離の理由・命名の流儀は tmux 版 Step 0 と同一（呼び出し元 pane ごとに分離）。
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/codex-tmux"
PANE_KEY=$(printf '%s' "$HERDR_PANE_ID" | tr -c 'A-Za-z0-9' '_')
STATE_FILE="$STATE_DIR/state-${PANE_KEY}.env"
mkdir -p "$STATE_DIR"

# stale state file の掃除（7日超のみ。ガードの理由は tmux 版 Step 0 の注1〜3を参照）
[ -n "$STATE_DIR" ] && [ -d "$STATE_DIR" ] \
  && find "$STATE_DIR" -type f -name 'state-*.env' -mtime +7 -delete 2>/dev/null || true

echo "[codex-tmux] backend=herdr self=$HERDR_PANE_ID"
echo "[codex-tmux] STATE_FILE=$STATE_FILE"
```

注: tmux 版の PARENT_WIN / wrong-window 検証は「空 pane id を `-t ""` に渡すとアクティブな
別 window に着地する」tmux 固有の事故対策。Herdr の split は pane id を明示指定し、空なら
上の pre-flight で fail-fast するため、window 着地検証は不要。

### H-Step 1: pane作成 + codex起動

tmux 版 Step 1 と同じく、先に shell pane を作成してから codex を起動する。
PR レビュー時の adversarial テンプレート prepend も tmux 版 Step 1 と同じ。

```bash
# プロンプトをファイルに書き出し（PR レビュー時のテンプレ差し込みは tmux 版 Step 1 参照）
cat > /tmp/codex-prompt.txt << 'PROMPT'
（ここに質問を書く）
PROMPT

# Claude Code 自身の pane の下に分割（下30%、フォーカスは移さない）
# 出力は JSON。result.pane.pane_id を python3 で抽出する
CODEX_PANE=$(herdr pane split "$HERDR_PANE_ID" --direction down --ratio 0.3 --no-focus \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["result"]["pane"]["pane_id"])') \
  && [ -n "$CODEX_PANE" ] \
  || { echo "[guard:split-failed] herdr pane split が失敗 — abort" >&2; return 1 2>/dev/null || exit 1; }

# pane にタイトルを設定（トピックに応じた名前をつける）
herdr pane rename "$CODEX_PANE" "codex-<topic>"

# repo root を解決して -c で trust_level=trusted を注入
# （導出ロジック・注意点・既知制約は tmux 版 Step 1 と同一）
_git_common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)
if [ -n "$_git_common" ] && [ "$(basename "$_git_common")" = ".git" ]; then
  _codex_root=$(dirname "$_git_common")
else
  _codex_root=""
fi

# codex 起動。`herdr pane run` はテキスト+Enter を1リクエストで送る
if [ -n "$_codex_root" ]; then
  herdr pane run "$CODEX_PANE" "cage -- codex --no-alt-screen --dangerously-bypass-approvals-and-sandbox -c 'projects={\"$_codex_root\"={trust_level=\"trusted\"}}' \"\$(cat /tmp/codex-prompt.txt)\""
else
  herdr pane run "$CODEX_PANE" "cage -- codex --no-alt-screen --dangerously-bypass-approvals-and-sandbox \"\$(cat /tmp/codex-prompt.txt)\""
fi

# state を永続化（single-quote 書き出しの理由・前提は tmux 版 Step 1 参照）
{
  printf "CODEX_BACKEND='herdr'\n"
  printf "CODEX_PANE='%s'\n" "$CODEX_PANE"
  printf "PARENT_PANE='%s'\n" "$HERDR_PANE_ID"
} > "$STATE_FILE"
```

### H-Step 2: 完了検知

`herdr wait output` でプロンプト復帰（`❯` または `›`）を blocking で待つ。
tmux 版の5秒ポーリングループは不要。

```bash
# timeout は ms。長い調査を依頼した場合は延ばす
herdr wait output "$CODEX_PANE" --match '[❯›]' --regex --timeout 600000 \
  || { echo "[guard:wait-timeout] codex 応答待ちがタイムアウト" >&2; return 1 2>/dev/null || exit 1; }
```

注: codex 起動直後や作業中も入力枠のグリフが画面に残っていて早期マッチすることがある。
その場合でも H-Step 4 の送信前ガード（最終行判定）で弾かれるので、少し待ってから
wait を再実行して待ち直すこと。

### H-Step 3: 結果読み取り

```bash
herdr pane read "$CODEX_PANE" --source recent-unwrapped --lines 100
```

`pane read` はクリーンなテキストを返す（tmux 版の `capture-pane -p` に相当）。

### H-Step 4: 追加質問（multi-turn）

#### 送信前ガード（必須）

```bash
# 0. state を復元（unset → source の理由は tmux 版 Step 4 参照）
unset CODEX_BACKEND CODEX_PANE PARENT_PANE
PANE_KEY=$(printf '%s' "$HERDR_PANE_ID" | tr -c 'A-Za-z0-9' '_')
STATE_FILE="${XDG_STATE_HOME:-$HOME/.local/state}/codex-tmux/state-${PANE_KEY}.env"
[ -r "$STATE_FILE" ] \
  || { echo "[guard:state-missing] state file ($STATE_FILE) 不在 — H-Step 1 からやり直し" >&2; return 1 2>/dev/null || exit 1; }
source "$STATE_FILE"
[ "$CODEX_BACKEND" = "herdr" ] && [ -n "$CODEX_PANE" ] \
  || { echo "[guard:state-invalid] state file の中身が不完全 — H-Step 1 からやり直し" >&2; return 1 2>/dev/null || exit 1; }

# 1. pane が存在するか
herdr pane get "$CODEX_PANE" >/dev/null 2>&1 \
  || { echo "[guard:pane-missing] CODEX_PANE ($CODEX_PANE) が存在しない — H-Step 1 からやり直し" >&2; return 1 2>/dev/null || exit 1; }

# 2. codex がプロンプト待ち状態か（glyph は版により ❯ または › のいずれか）
# pane 末尾は空行になり得る（実測）ため、最後の「非空行」を判定対象にする
last_line=$(herdr pane read "$CODEX_PANE" --source recent-unwrapped --lines 5 \
  | grep -v '^[[:space:]]*$' | tail -1)
if ! echo "$last_line" | grep -qE '[❯›]'; then
  echo "[guard:not-ready] codexがプロンプト待ちではない — abort (H-Step 2 の wait を回してからやり直し)" >&2
  return 1 2>/dev/null || exit 1
fi
```

**禁止事項**は tmux 版 Step 4 と同じ（Escape キーを送信しない。プロンプト待ちになるまで送信しない）。

#### 送信

```bash
# 追加プロンプトをファイルに書き出し
cat > /tmp/codex-prompt.txt << 'PROMPT'
（ここに追加質問を書く）
PROMPT

# send-text は複数行・特殊文字をそのまま送れる（tmux のバッファ経由は不要）
herdr pane send-text "$CODEX_PANE" "$(cat /tmp/codex-prompt.txt)"

# 反映を待ってから Enter で送信
sleep 0.3
herdr pane send-keys "$CODEX_PANE" Enter
herdr pane send-keys "$CODEX_PANE" Enter
```

その後、H-Step 2→3 を繰り返して応答を読み取る。

### H-Step 5: レビューマーカー作成

バックエンド非依存。tmux 版 Step 5 をそのまま実行する。

### H-Step 6: 終了

```bash
PANE_KEY=$(printf '%s' "$HERDR_PANE_ID" | tr -c 'A-Za-z0-9' '_')
herdr pane close "$CODEX_PANE"
rm -f /tmp/codex-prompt.txt "${XDG_STATE_HOME:-$HOME/.local/state}/codex-tmux/state-${PANE_KEY}.env"
```

## フォールバック: codex が使えない場合

以下のいずれかで codex との対話が成立しない場合、**PR レビューは `/code-review xhigh` に切り替える**。
codex の復旧を待たず、検知した時点で自動でフォールバックすること。

- どちらのバックエンドも使えない（`$TMUX` 未設定かつ Herdr バックエンド判定が不成立）、または `codex` / `cage` コマンドが無い
- Step 0 の pre-flight guard / Step 1 の split・codex 起動が失敗する（Herdr バックエンドでは H-Step 0 / H-Step 1 の失敗）
- codex 側の rate limit・認証エラー・応答タイムアウト（Step 2 / H-Step 2 の完了検知が一定時間進まない）
- ユーザーが明示的に code-review でのレビューを指示

### 手順

1. `/code-review xhigh` を実行し、指摘に対応する（対応方針が立つ／指摘ゼロに収束するまで）。
2. レビュー完了後、code-review 用の完了マーカーを生成する。
   block-pr-without-review hook はこのマーカーも codex マーカーと同等に PR ゲート通過として認める。

```bash
_repo=$(git remote get-url origin 2>/dev/null | sed 's/\.git$//;s|.*/||')
_branch=$(git branch --show-current 2>/dev/null)
_hash=$(git rev-parse --short HEAD 2>/dev/null)
# branch 内の "/" → "_" 置換は codex 版マーカー（Step 5）/ hook 側と同じ規則を保つこと。
touch "/tmp/.code-review-done--${_repo}--${_branch//\//_}--${_hash}"
```

注: マーカーは `.codex-review-done` ではなく `.code-review-done` を使う（レビュー経路を証跡で区別するため）。
PR の HEAD が変わったら、新しい hash で再度マーカーを生成すること。

## 注意事項

- 質問は単目的にする（1つの質問に1つのテーマ）
- codexはステートレスではない（interactive modeではセッションが維持される）
- codexは自分でファイルを読めるので、ファイル内容全体を渡す必要はない
- 議論は複数ターンを基本とする
- web検索が必要な場合もcodexに依頼できる
- 結果読み取りには必ず`tmux capture-pane -p`（Herdr バックエンドでは`herdr pane read`）を使う（ログファイルはエスケープシーケンスが混入するため使わない）
- paneタイトルはトピックがわかる名前にする（`codex-<topic>` 形式）
