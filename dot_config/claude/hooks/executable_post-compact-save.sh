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

# Compact count tracking for context reset recommendation
STATS_FILE="$STATE_DIR/compact-stats.json"
if [ -f "$STATS_FILE" ] && command -v jq &>/dev/null; then
    tmp=$(mktemp)
    if jq '.compact_count += 1 | .last_compact_at = (now | todate)' "$STATS_FILE" > "$tmp" 2>/dev/null; then
        mv "$tmp" "$STATS_FILE"
    else
        rm -f "$tmp"
    fi
else
    cat > "$STATS_FILE" << STATS
{
  "compact_count": 1,
  "last_compact_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
STATS
fi
echo "PostCompact: compact count updated for session $SESSION_ID" >&2

# compact count が 2 以上なら context reset を推奨
count=$(jq -r '.compact_count // 0' "$STATS_FILE" 2>/dev/null || echo "0")
if [ "$count" -ge 2 ]; then
    echo "⚠ Context reset 推奨: compaction が ${count} 回発生。品質低下の兆候がある場合は claude --continue --fork-session を検討してください。" >&2
fi

exit 0
