#!/bin/bash
# PostCompact Hook - Save compact_summary for SessionStart(compact) to consume
# Lightweight: no AI/network calls

set -e

INPUT=$(cat)
COMPACT_SUMMARY=$(echo "$INPUT" | jq -r '.compact_summary // ""')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // ""')

if [ -z "$CLAUDE_PROJECT_DIR" ] || [ -z "$SESSION_ID" ]; then
    exit 0
fi

STATE_DIR="$CLAUDE_PROJECT_DIR/ai/state/$SESSION_ID"
mkdir -p "$STATE_DIR"

if [ -n "$COMPACT_SUMMARY" ]; then
    echo "$COMPACT_SUMMARY" > "$STATE_DIR/compact_summary.md"
    echo "PostCompact: compact_summary saved for session $SESSION_ID" >&2
fi

exit 0
