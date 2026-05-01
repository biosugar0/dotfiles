# codex-tmux: tmux経由でcodex CLIと対話

tmux paneを分割してcodex(gpt-5)をinteractive modeで起動し、対話する。
codex MCPは使わない。必ずこの手順でtmux経由で対話すること。

## 前提条件

- tmux内で動作していること（`$TMUX`が設定されていること）
- `cage`コマンドが利用可能であること
- `codex`コマンドが利用可能であること

## pane命名規則

paneにはタイトルを付けて名前で管理する。pane IDは変数に保持しつつ、タイトルで識別可能にする。

- **命名形式**: `codex-<topic>` （例: `codex-auth-design`, `codex-perf-investigation`）
- タイトルは `select-pane -T` で設定する
- 既存のcodex paneを再利用する場合、タイトルで検索して特定する

### 既存paneの検索

```bash
# タイトルでcodex paneを検索
tmux list-panes -F '#{pane_id} #{pane_title}' | grep '^codex-'
```

## 手順

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
PANE_KEY=$(printf '%s' "$TMUX_PANE" | tr -c 'A-Za-z0-9' '_')
STATE_FILE="${XDG_STATE_HOME:-$HOME/.local/state}/codex-tmux/state-${PANE_KEY}.env"
mkdir -p "$(dirname "$STATE_FILE")"

# 位置出力（debug / 事故時の追跡効率化）
echo "[codex-tmux] self: $(tmux display-message -p -t "$TMUX_PANE" 'session=#{session_name} window=#{window_index}:#{window_name} pane=#{pane_index} (#{pane_id})')"
echo "[codex-tmux] PARENT_WIN=$PARENT_WIN"
echo "[codex-tmux] STATE_FILE=$STATE_FILE"
```

### Step 1: pane作成 + codex起動

**重要: 先にzsh paneを作成し、send-keysでcodexを起動する。**
split-windowに直接コマンドを渡すと、引用符のネストやプロンプト内の特殊文字でシェル展開が壊れ、paneが即座に閉じる。

```bash
# プロンプトをファイルに書き出し
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
touch "/tmp/.codex-review-done--${_repo}--${_branch}--${_hash}"
```

### Step 6: 終了

議論が完了したらpaneを閉じて一時ファイルを削除する。

```bash
PANE_KEY=$(printf '%s' "$TMUX_PANE" | tr -c 'A-Za-z0-9' '_')
tmux kill-pane -t "$CODEX_PANE"
rm -f /tmp/codex-prompt.txt "${XDG_STATE_HOME:-$HOME/.local/state}/codex-tmux/state-${PANE_KEY}.env"
```

## 注意事項

- 質問は単目的にする（1つの質問に1つのテーマ）
- codexはステートレスではない（interactive modeではセッションが維持される）
- codexは自分でファイルを読めるので、ファイル内容全体を渡す必要はない
- 議論は複数ターンを基本とする
- web検索が必要な場合もcodexに依頼できる
- 結果読み取りには必ず`tmux capture-pane -p`を使う（ログファイルはエスケープシーケンスが混入するため使わない）
- paneタイトルはトピックがわかる名前にする（`codex-<topic>` 形式）
