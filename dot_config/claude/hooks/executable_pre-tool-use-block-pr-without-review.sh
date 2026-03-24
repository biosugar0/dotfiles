#!/bin/bash
# PreToolUse hook: Block gh pr create without codex review

input=$(cat)

command=$(echo "$input" | jq -r '.tool_input.command // empty')

# gh pr create をチェック（cd && gh pr create 等のパターンも検出）
if echo "$command" | grep -qE '(^|[;&|] *)gh pr create( |$)'; then
  head=$(git rev-parse --short HEAD 2>/dev/null)
  marker="/tmp/.codex-review-done-${head}"
  if [ ! -f "$marker" ]; then
    jq -n '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: "Codex reviewが未実施。先にcodex-tmux skillでレビューを受けてからPRを作成すること。"
      }
    }'
  fi
fi

exit 0
