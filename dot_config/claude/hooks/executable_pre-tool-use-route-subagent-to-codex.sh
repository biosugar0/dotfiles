#!/bin/bash
# PreToolUse hook: general-purpose subagent を codex-worker (codex exec) に振り替える
# subagentタスクはcodexに委譲する方針の強制。専門agent (Explore/Plan/ci-quality-checker等) は対象外
# opt-out: prompt 冒頭に [no-codex] / 環境変数 CODEX_SUBAGENT_ROUTING=off / codex or codex-worker-env 不在

input=$(cat)

# 安価なチェックを先に（routing off / codex 不在なら jq を起動せず抜ける）
[ "${CODEX_SUBAGENT_ROUTING:-on}" = "off" ] && exit 0
command -v codex >/dev/null 2>&1 || exit 0
command -v codex-worker-env >/dev/null 2>&1 || exit 0

# tool_name・subagent_type・[no-codex]判定 を 1回の jq にまとめる（旧: 抽出ごとに jq を3回 fork）。
# [no-codex] は先頭空白・改行を除いた上での前方一致を jq 内で判定する
# （prompt の生の改行を bash に渡すと @tsv で \n にエスケープされ判定が壊れるため、bool だけ受け取る）。
IFS=$'\t' read -r tool_name subagent_type is_nocodex < <(echo "$input" | jq -r '
  [ (.tool_name // ""),
    (.tool_input.subagent_type // "general-purpose"),
    (if ((.tool_input.prompt // "") | sub("^\\s+"; "") | startswith("[no-codex]")) then "1" else "0" end)
  ] | @tsv')

# Task(旧称)/Agent(v2.1.63+) 以外は対象外
case "$tool_name" in
  Task|Agent) ;;
  *) exit 0 ;;
esac

# general-purpose（未指定含む）のみ振り替え。専門agentはそのまま通す
[ "$subagent_type" = "general-purpose" ] || exit 0

# [no-codex] マーカーはフォールバック経路（codex失敗後の再委譲用）として素通し
[ "$is_nocodex" = "1" ] && exit 0

# 発火実績を JSONL 記録(cc-harness-metrics 集計用)。lib 欠損時は no-op。
. "$(dirname "$0")/lib/harness-log.sh" 2>/dev/null || harness_log() { :; }
harness_log "route-subagent-to-codex" "reroute" "" "$(echo "$input" | jq -r '.session_id // empty')"
echo "$input" | jq '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "allow",
    permissionDecisionReason: "subagentタスクはcodexで実行する方針のため general-purpose を codex-worker に振り替えた",
    updatedInput: (.tool_input + {subagent_type: "codex-worker"})
  }
}'
