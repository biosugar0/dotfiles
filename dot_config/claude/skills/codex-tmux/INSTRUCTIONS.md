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

# send-keysでcodex起動コマンドを送信
tmux send-keys -t "$CODEX_PANE" "cage -- codex --no-alt-screen --dangerously-bypass-approvals-and-sandbox \"\$(cat /tmp/codex-prompt.txt)\"" Enter
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
_repo=$(basename "$(git rev-parse --show-toplevel 2>/dev/null)")
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
