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
CODEX_PANE=$(tmux split-window -v -f -d -l 30% -t "$TMUX_PANE" -P -F '#{pane_id}')

# paneにタイトルを設定（トピックに応じた名前をつける）
tmux select-pane -t "$CODEX_PANE" -T "codex-<topic>"

# repo root を解決して -c で trust_level=trusted を注入
# （worktree/サブディレクトリ起動時の "Do you trust this directory?" プロンプトを抑止）
# 注: codex の -c は dotted key の quoted segment を解釈せず生 split するため、
#     key 側は単一トークン `projects` のみにして値を inline table で渡す。
# git 外（toplevel 未解決）では override を付けない（/tmp 等の誤 auto-trust 防止）。
_codex_root=$(git rev-parse --path-format=absolute --show-toplevel 2>/dev/null || true)

if [ -n "$_codex_root" ]; then
  tmux send-keys -t "$CODEX_PANE" "cage -- codex --no-alt-screen --dangerously-bypass-approvals-and-sandbox -c 'projects={\"$_codex_root\"={trust_level=\"trusted\"}}' \"\$(cat /tmp/codex-prompt.txt)\"" Enter
else
  tmux send-keys -t "$CODEX_PANE" "cage -- codex --no-alt-screen --dangerously-bypass-approvals-and-sandbox \"\$(cat /tmp/codex-prompt.txt)\"" Enter
fi
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
# 1. paneが存在し、codexプロセスが動いているか確認
if ! tmux list-panes -F '#{pane_id}' | grep -q "^${CODEX_PANE}$"; then
  echo "ERROR: CODEX_PANE ($CODEX_PANE) が存在しない" >&2
  # paneを再作成する（Step 1からやり直す）
fi

# 2. codexが ❯ プロンプト待ち状態か確認（最終行をチェック）
last_line=$(tmux capture-pane -t "$CODEX_PANE" -p -S -3 | tail -1)
if ! echo "$last_line" | grep -q '❯'; then
  echo "WARNING: codexがプロンプト待ちではない。応答完了を待つ" >&2
  # Step 2の完了検知ループを再実行して待つ
fi
```

**禁止事項:**
- **Escapeキーを送信しない** — codexがinteractive UI（タスク選択画面等）を表示中の場合、EscapeはUIキャンセルとして消費され、後続のペースト内容が別paneに流れる原因になる
- codexが `❯` プロンプト表示になるまで待ってから送信する

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
tmux kill-pane -t "$CODEX_PANE"
rm -f /tmp/codex-prompt.txt
```

## 注意事項

- 質問は単目的にする（1つの質問に1つのテーマ）
- codexはステートレスではない（interactive modeではセッションが維持される）
- codexは自分でファイルを読めるので、ファイル内容全体を渡す必要はない
- 議論は複数ターンを基本とする
- web検索が必要な場合もcodexに依頼できる
- 結果読み取りには必ず`tmux capture-pane -p`を使う（ログファイルはエスケープシーケンスが混入するため使わない）
- paneタイトルはトピックがわかる名前にする（`codex-<topic>` 形式）
