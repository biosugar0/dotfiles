#!/bin/bash
# PreToolUse hook: Block file edits on main/master branch
# dotfilesリポジトリ等の直接main運用リポジトリは除外

cat > /dev/null  # consume stdin

branch=$(git branch --show-current 2>/dev/null) || exit 0

# main/master以外は許可
[[ "$branch" != "main" && "$branch" != "master" ]] && exit 0

# dotfilesリポジトリは除外（直接mainにpushする運用）
remote=$(git remote get-url origin 2>/dev/null || echo "")
if echo "$remote" | grep -qi "dotfiles"; then
  exit 0
fi

# mainブランチでの編集をブロック
jq -n '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: "mainブランチでの編集はブロックされた。feature branchを作成してください。"
  }
}'
