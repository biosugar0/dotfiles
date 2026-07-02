#!/bin/bash
# PreToolUse hook: 禁止ディレクトリ ai/ のステージ/コミットをブロックする guardrail。
# 検出: git -C/-c/--no-pager 等の global option・複合コマンド・subshell 経由の add/commit と、
#       ai/ ./ai/ :/ai/ 形式の pathspec。Claude の誤操作防止が目的（完全な sandbox ではない）。
# 対象外(意図的): VAR=x 前置の env assignment、bare "ai"(語 "ai" への誤検出回避)、quoted pathspec。

input=$(cat)
# 発火実績を JSONL 記録(cc-harness-metrics 集計用)。lib 欠損時は no-op。
. "$(dirname "$0")/lib/harness-log.sh" 2>/dev/null || harness_log() { :; }

command=$(echo "$input" | jq -r '.tool_input.command // empty')
[ -z "$command" ] && exit 0
sid=$(echo "$input" | jq -r '.session_id // empty')

# git add/commit 以外はスルー（global option(-C/-c/--no-pager 等)・複合コマンド・subshell 経由も検出）
echo "$command" | grep -qE '(^|[;&|(] *)git( +(-[Cc]|--git-dir|--work-tree|--namespace|--exec-path)([= ]+[^ ]+)?| +(--no-pager|--paginate|--bare|-p|-P))* +(add|commit)' || exit 0

# 明示的な禁止パスを検出（ai/ ./ai/ :/ai/ 形式。別階層の src/ai/ 等は対象外）
if echo "$command" | grep -qE '(^|[[:space:](])(\.?/|:/)?ai/'; then
  harness_log "block-forbidden-dirs" "deny" "ai-dir" "$sid"
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: "禁止ディレクトリ(ai/)はステージ・コミットできない。"
    }
  }'
  exit 0
fi

# git add . / git add -A / git add --all をブロック（暗黙的な禁止ファイル混入防止）
if echo "$command" | grep -qE 'git add\s+(\.|--all|-A|:/)(\s|$)'; then
  harness_log "block-forbidden-dirs" "deny" "add-all" "$sid"
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
if echo "$command" | grep -qE 'git commit\s+(.*\s)?-([a-zA-Z]*)a([a-zA-Z]*)(\s|$)'; then
  harness_log "block-forbidden-dirs" "deny" "commit-a" "$sid"
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
