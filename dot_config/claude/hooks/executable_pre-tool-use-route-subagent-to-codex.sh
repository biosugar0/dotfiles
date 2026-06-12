#!/bin/bash
# PreToolUse hook: general-purpose subagent を codex-worker (codex exec) に振り替える
# subagentタスクはcodexに委譲する方針の強制。専門agent (Explore/Plan/ci-quality-checker等) は対象外
# opt-out: prompt 冒頭に [no-codex] / 環境変数 CODEX_SUBAGENT_ROUTING=off / codex 不在

input=$(cat)

# Task(旧称)/Agent(v2.1.63+) 以外は対象外
tool_name=$(echo "$input" | jq -r '.tool_name // empty')
case "$tool_name" in
  Task|Agent) ;;
  *) exit 0 ;;
esac

[ "${CODEX_SUBAGENT_ROUTING:-on}" = "off" ] && exit 0
command -v codex >/dev/null 2>&1 || exit 0

# general-purpose（未指定含む）のみ振り替え。専門agentはそのまま通す
subagent_type=$(echo "$input" | jq -r '.tool_input.subagent_type // "general-purpose"')
[ "$subagent_type" = "general-purpose" ] || exit 0

# [no-codex] マーカーはフォールバック経路（codex失敗後の再委譲用）として素通し。
# 先頭の空白・改行を除去してから判定（main agent が改行付きで再委譲してもフォールバックを取りこぼさない）
prompt=$(echo "$input" | jq -r '.tool_input.prompt // empty')
prompt_trimmed="${prompt#"${prompt%%[![:space:]]*}"}"
case "$prompt_trimmed" in
  "[no-codex]"*) exit 0 ;;
esac

echo "$input" | jq '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "allow",
    permissionDecisionReason: "subagentタスクはcodexで実行する方針のため general-purpose を codex-worker に振り替えた",
    updatedInput: (.tool_input + {subagent_type: "codex-worker"})
  }
}'
