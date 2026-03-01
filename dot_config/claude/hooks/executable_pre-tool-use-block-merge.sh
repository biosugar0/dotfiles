#!/bin/bash
# PreToolUse hook: Block git merge commands (bypass-proof)

input=$(cat)

command=$(echo "$input" | jq -r '.tool_input.command // empty')

# git merge / gh pr merge をブロック（git mergetool等は許可）
if echo "$command" | grep -qE '^(git merge( |$)|gh pr merge( |$))'; then
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: "git merge / gh pr merge はブロックされている。"
    }
  }'
fi

exit 0
