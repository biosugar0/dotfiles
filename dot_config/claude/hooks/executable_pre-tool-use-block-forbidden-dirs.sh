#!/bin/bash
# PreToolUse hook: Block staging/committing forbidden directories
# 禁止ディレクトリ: ai/, .serena/

input=$(cat)

command=$(echo "$input" | jq -r '.tool_input.command // empty')
[ -z "$command" ] && exit 0

# git add/commit 以外はスルー
echo "$command" | grep -qE '^git (add|commit)' || exit 0

# 明示的な禁止パスを検出
if echo "$command" | grep -qE '(^|\s)(ai/|\.serena/)'; then
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: "禁止ディレクトリ(ai/, .serena/)はステージ・コミットできない。"
    }
  }'
  exit 0
fi

# git add . / git add -A / git add --all をブロック（暗黙的な禁止ファイル混入防止）
if echo "$command" | grep -qE 'git add\s+(\.|--all|-A|:/)(\s|$)'; then
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: "\"git add .\" / \"git add -A\" は禁止。ファイルを個別に指定すること。"
    }
  }'
  exit 0
fi

# git commit -a / git commit -am をブロック
if echo "$command" | grep -qE 'git commit\s+.*-[a-zA-Z]*a'; then
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: "\"git commit -a\" は禁止。git addでファイルを個別にステージすること。"
    }
  }'
  exit 0
fi

exit 0
