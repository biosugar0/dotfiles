#!/bin/bash
# PreToolUse hook: git merge / gh pr merge をブロックする guardrail（Claude の誤操作防止）。
# 検出: 行頭/区切り(;&|()直後の起動、git -C/-c/--no-pager 等の global option、gh -R/--repo prefix、
#       複合コマンド・subshell・コマンド置換経由。完全な sandbox ではなく best-effort。
# 対象外(意図的): 先頭の環境変数代入(VAR=x git merge) — Claude が生成しない adversarial 形。

input=$(cat)
# 発火実績を JSONL 記録(cc-harness-metrics 集計用)。lib 欠損時は no-op。
. "$(dirname "$0")/lib/harness-log.sh" 2>/dev/null || harness_log() { :; }

command=$(echo "$input" | jq -r '.tool_input.command // empty')

# git merge / gh pr merge をブロック（git mergetool等は許可）
if echo "$command" | grep -qE '(^|[;&|(] *)(git( +(-[Cc]|--git-dir|--work-tree|--namespace|--exec-path)([= ]+[^ ]+)?| +(--no-pager|--paginate|--bare|-p|-P))* +merge( |$)|gh( +(-R|--repo)[= ]+[^ ]+)? +pr +merge( |$))'; then
  harness_log "block-merge" "deny" "$(printf '%.120s' "$command")" "$(echo "$input" | jq -r '.session_id // empty')"
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: "git merge / gh pr merge はブロックされている。"
    }
  }'
fi

exit 0
