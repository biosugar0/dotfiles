#!/bin/bash
# PreToolUse hook: Block file edits on main/master branch
# 対象ファイルが属するリポジトリのブランチを判定
# dotfilesリポジトリ等の直接main運用リポジトリは除外
# リポジトリ外のファイル（plans等）は常に許可

input=$(cat)
# 発火実績を JSONL 記録(cc-harness-metrics 集計用)。lib 欠損時は no-op。
. "$(dirname "$0")/lib/harness-log.sh" 2>/dev/null || harness_log() { :; }

file_path=$(echo "$input" | jq -r '.tool_input.file_path // empty')
[ -z "$file_path" ] && exit 0

# ファイルのディレクトリを特定（未存在なら親を辿る）
file_dir=$(dirname "$file_path")
while [ ! -d "$file_dir" ] && [ "$file_dir" != "/" ]; do
  file_dir=$(dirname "$file_dir")
done

# 対象ファイルが属するリポジトリのブランチを確認
branch=$(git -C "$file_dir" branch --show-current 2>/dev/null) || exit 0

# main/master以外は許可
[[ "$branch" != "main" && "$branch" != "master" ]] && exit 0

# dotfilesリポジトリは除外（直接mainにpushする運用）
remote=$(git -C "$file_dir" remote get-url origin 2>/dev/null || echo "")
if echo "$remote" | grep -qi "dotfiles"; then
  exit 0
fi

# mainブランチでの編集をブロック
harness_log "block-main" "deny" "$file_path" "$(echo "$input" | jq -r '.session_id // empty')"
jq -n '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: "mainブランチでの編集はブロックされた。git wt <branch> でworktreeを作成して作業してください。"
  }
}'
