---
name: codex-tmux
description: >-
  tmux pane分割でcodex CLIと対話する。難易度の高い課題の議論、調査、web検索に使用。
  Use when: codexと議論したい、調査を依頼したい、web検索が必要、難問を相談したい場面。
user-invocable: true
argument-hint: "[question]"
---

# codex-tmux: tmux経由でcodex CLIと対話

tmux paneを分割してcodex(gpt-5)をinteractive modeで起動し、対話する。
codex MCPは使わない。必ずこの手順でtmux経由で対話すること。

## 前提条件

- tmux内で動作していること（`$TMUX`が設定されていること）
- `cage`コマンドが利用可能であること
- `codex`コマンドが利用可能であること

## 手順

### Step 1: pane作成 + codex起動

**重要: 先にzsh paneを作成し、send-keysでcodexを起動する。**
split-windowに直接コマンドを渡すと、引用符のネストやプロンプト内の特殊文字でシェル展開が壊れ、paneが即座に閉じる。

```bash
# プロンプトをファイルに書き出し
cat > /tmp/codex-prompt.txt << 'PROMPT'
（ここに質問を書く）
PROMPT

# zsh pane作成（全幅水平分割、下30%）
# pane IDが出力されるので記録する
CODEX_PANE=$(tmux split-window -v -f -d -l 30% -P -F '#{pane_id}')

# send-keysでcodex起動コマンドを送信
tmux send-keys -t $CODEX_PANE "cage -- codex --no-alt-screen --dangerously-bypass-approvals-and-sandbox \"\$(cat /tmp/codex-prompt.txt)\"" Enter
```

### Step 2: 完了検知

`tmux capture-pane`の出力を5秒間隔で監視し、変化がなくなったら応答完了と判断する。

```bash
prev_content=""
while true; do
  sleep 5
  curr_content=$(tmux capture-pane -t <pane_id> -p -S -50)
  if [ "$curr_content" = "$prev_content" ] && [ -n "$curr_content" ]; then
    break
  fi
  prev_content="$curr_content"
done
```

### Step 3: 結果読み取り

```bash
tmux capture-pane -t <pane_id> -p -S -100
```

capture-paneはクリーンなテキストを返す。ログの内容を読んで、codexの応答を把握する。

### Step 4: 追加質問（multi-turn）

追加の質問がある場合、ファイル経由でsend-keysで送信する。

```bash
# 追加プロンプトをファイルに書き出し
cat > /tmp/codex-prompt.txt << 'PROMPT'
（ここに追加質問を書く）
PROMPT

# send-keysで送信（Enter2回: 1回目で入力確定、2回目で送信）
tmux send-keys -t <pane_id> "$(cat /tmp/codex-prompt.txt)" Enter Enter
```

その後、Step 2→3を繰り返して応答を読み取る。

### Step 5: 終了

議論が完了したらpaneを閉じて一時ファイルを削除する。

```bash
tmux kill-pane -t <pane_id>
rm -f /tmp/codex-prompt.txt
```

## 注意事項

- 質問は単目的にする（1つの質問に1つのテーマ）
- codexはステートレスではない（interactive modeではセッションが維持される）
- codexは自分でファイルを読めるので、ファイル内容全体を渡す必要はない
- 議論は複数ターンを基本とする
- web検索が必要な場合もcodexに依頼できる
- 結果読み取りには必ず`tmux capture-pane -p`を使う（ログファイルはエスケープシーケンスが混入するため使わない）
