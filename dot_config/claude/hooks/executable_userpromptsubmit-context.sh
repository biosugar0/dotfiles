#!/usr/bin/env bash
# UserPromptSubmit hook:
#   - additionalContext に golden-rules + workflow-instructions + git status + 現在時刻を集約注入
#   - sessionTitle を Haiku 要約キャッシュ（なければ dir/branch）から設定
# 旧構成では golden-rules / git status / 時刻を別フックの素の stdout echo で注入しており、
# シェル依存(`echo '\n'`)があった。本スクリプトに統合し additionalContext JSON へ一本化した。
set -euo pipefail

# Read stdin JSON to get session_id
stdin_json=$(cat)
session_id=$(echo "$stdin_json" | jq -r '.session_id // empty')

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

git_status=""
if git -C "${CLAUDE_PROJECT_DIR:-.}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git_status=$(git -C "${CLAUDE_PROJECT_DIR:-.}" status --short 2>/dev/null || true)
fi
[ -z "$git_status" ] && git_status="（clean）"

now=$(date '+%Y-%m-%d %H:%M:%S')

# Single additionalContext payload（shell 依存の echo '\n' を排し printf で組み立て）
context=$(printf '%s\n\n%s\n\n## Git status (--short)\n%s\n\n---\nCurrent time: %s\n' \
  "$golden" "$workflow" "$git_status" "$now")

printf '%s' "$context" | jq -Rs --arg t "$title" \
  '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",additionalContext:.,sessionTitle:$t}}'
