#!/bin/bash
# PreToolUse hook: git merge / gh pr merge をブロックする guardrail（Claude の誤操作防止）。
# 検出: 行頭/区切り(;&|()直後の起動、git -C/-c/--no-pager 等の global option、gh -R/--repo prefix、
#       複合コマンド・subshell・コマンド置換経由。完全な sandbox ではなく best-effort。
# 対象外(意図的): 先頭の環境変数代入(VAR=x git merge) — Claude が生成しない adversarial 形。

input=$(cat)

command=$(echo "$input" | jq -r '.tool_input.command // empty')

# git merge / gh pr merge をブロック（git mergetool等は許可）
if echo "$command" | grep -qE '(^|[;&|(] *)(git( +(-[Cc]|--git-dir|--work-tree|--namespace|--exec-path)([= ]+[^ ]+)?| +(--no-pager|--paginate|--bare|-p|-P))* +merge( |$)|gh( +(-R|--repo)[= ]+[^ ]+)? +pr +merge( |$))'; then
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: "git merge / gh pr merge はブロックされている。"
    }
  }'
fi

exit 0
