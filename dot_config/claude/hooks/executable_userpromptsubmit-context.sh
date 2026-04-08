#!/usr/bin/env bash
# UserPromptSubmit hook: workflow instructions + session title from Haiku summary cache
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

# Read workflow instructions and build output JSON
content=$(cat ~/.config/claude/hooks/data/workflow-instructions.md 2>/dev/null || echo "")
echo "$content" | jq -Rs --arg t "$title" '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",additionalContext:.,sessionTitle:$t}}'
