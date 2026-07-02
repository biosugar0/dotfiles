#!/usr/bin/env bash
# UserPromptSubmit hook:
#   - additionalContext に golden-rules + workflow-instructions + git status + goal status + 現在時刻を集約注入
#   - sessionTitle を Haiku 要約キャッシュ（なければ dir/branch）から設定
set -euo pipefail

# Read stdin JSON
stdin_json=$(cat)
session_id=$(echo "$stdin_json" | jq -r '.session_id // empty')
transcript_path=$(echo "$stdin_json" | jq -r '.transcript_path // empty')

# djb2 hash (same algorithm as stop-hook.ts) — base36 output
djb2() {
  printf '%s' "$1" | python3 -c "
import sys
s=sys.stdin.read();h=5381
for c in s:h=((h<<5)+h+ord(c))&0xFFFFFFFF
d='0123456789abcdefghijklmnopqrstuvwxyz';r=''
while h:r=d[h%36]+r;h//=36
print(r or '0',end='')
"
}

# Build fallback title from dir/branch
dir=$(basename "${CLAUDE_PROJECT_DIR:-$(pwd)}")
branch=$(git -C "${CLAUDE_PROJECT_DIR:-.}" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
fallback="${dir}"
[ -n "$branch" ] && fallback="${dir}/${branch}"

# Try to read Haiku summary from statusline cache
title="$fallback"
if [ -n "$session_id" ]; then
  cache_file="/tmp/claude-session-summaries/${session_id}.json"
  if [ -f "$cache_file" ]; then
    cached_slug=$(jq -r '.slug // empty' "$cache_file" 2>/dev/null || true)
    [ -n "$cached_slug" ] && title="$cached_slug"
  fi
fi

# Assemble context sources（いずれも欠損時は空でフォールバック）
golden=$(cat ~/.config/claude/hooks/data/golden-rules.txt 2>/dev/null || true)
workflow=$(cat ~/.config/claude/hooks/data/workflow-instructions.md 2>/dev/null || true)

# モデル別ルールの出し分け:
# sonnet-bash-runner 委譲・tool-call タグ破損対策は Opus 固有。モデルは自分が何かを
# 確実には知らないため「Opus 稼働時は…」という自己条件付きルールは機能しない。
# transcript の直近 assistant メッセージから現行モデルを決定的に判定して注入を切り替える。
# 判定不能（セッション先頭・読取失敗）は既定 main=Opus に合わせて注入側に倒す。
model=""
if [ -n "$transcript_path" ] && [ -f "$transcript_path" ]; then
  model=$(tail -n 100 "$transcript_path" 2>/dev/null \
    | jq -r 'select(.type == "assistant") | .message.model // empty' 2>/dev/null \
    | tail -n 1 || true)
fi
case "$model" in
  ""|*opus*)
    opus_rules=$(cat ~/.config/claude/hooks/data/golden-rules-opus.txt 2>/dev/null || true)
    [ -n "$opus_rules" ] && golden=$(printf '%s\n%s' "$golden" "$opus_rules")
    ;;
esac

git_status=""
if git -C "${CLAUDE_PROJECT_DIR:-.}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git_status=$(git -C "${CLAUDE_PROJECT_DIR:-.}" status --short 2>/dev/null || true)
fi
[ -z "$git_status" ] && git_status="（clean）"

# Goal status
goal_line=""
if [ -n "$transcript_path" ]; then
  goal_hash=$(djb2 "$transcript_path")
  goal_file="/tmp/claude-goal-${goal_hash}.json"
  if [ -f "$goal_file" ]; then
    goal_condition=$(jq -r '.condition // empty' "$goal_file" 2>/dev/null || true)
    goal_iterations=$(jq -r '.iterations // 0' "$goal_file" 2>/dev/null || true)
    goal_target=$(jq -r '.targetTurns // empty' "$goal_file" 2>/dev/null || true)
    goal_set_at=$(jq -r '.setAt // empty' "$goal_file" 2>/dev/null || true)
    if [ -n "$goal_condition" ]; then
      elapsed=""
      if [ -n "$goal_set_at" ]; then
        now_ms=$(date +%s)000
        diff_s=$(( (${now_ms%000} - ${goal_set_at%???}) ))
        if [ "$diff_s" -ge 3600 ] 2>/dev/null; then
          elapsed="$(( diff_s / 3600 ))h$(( (diff_s % 3600) / 60 ))m"
        elif [ "$diff_s" -ge 60 ] 2>/dev/null; then
          elapsed="$(( diff_s / 60 ))m"
        else
          elapsed="${diff_s}s"
        fi
      fi
      turn_info="${goal_iterations}"
      [ -n "$goal_target" ] && [ "$goal_target" != "null" ] && turn_info="${goal_iterations}/${goal_target}"
      time_info=""
      [ -n "$elapsed" ] && time_info=", ${elapsed}"
      goal_line="Goal active (turn ${turn_info}${time_info}): ${goal_condition}"
    fi
  fi
fi

# Write goal status for tmux pane-border display
if [ -n "${TMUX_PANE:-}" ]; then
  pane_dir="/tmp/claude-goal-pane"
  mkdir -p "$pane_dir" 2>/dev/null
  if [ -n "$goal_line" ]; then
    printf '%s' "$goal_line" > "${pane_dir}/${TMUX_PANE}" 2>/dev/null
  else
    rm -f "${pane_dir}/${TMUX_PANE}" 2>/dev/null
  fi
fi

now=$(date '+%Y-%m-%d %H:%M')

# Single additionalContext payload
goal_block=""
[ -n "$goal_line" ] && goal_block=$(printf '\n## %s\n' "$goal_line")
context=$(printf '%s\n\n%s\n\n## Git status (--short)\n%s%s\n\n---\nCurrent time: %s\n' \
  "$golden" "$workflow" "$git_status" "$goal_block" "$now")

printf '%s' "$context" | jq -Rs --arg t "$title" \
  '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",additionalContext:.,sessionTitle:$t}}'
