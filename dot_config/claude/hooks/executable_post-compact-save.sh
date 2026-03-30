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

# Evaluator findings checkpoint (compact 後も findings を保持)
GATE_FILE="$CLAUDE_PROJECT_DIR/ai/state/workflow-gate.json"
CHECKPOINT_FILE="$STATE_DIR/findings-checkpoint.json"
if [ -f "$GATE_FILE" ] && command -v jq &>/dev/null; then
    active=$(jq -r '.evaluator.active_findings // [] | length' "$GATE_FILE" 2>/dev/null || echo "0")
    if [ "$active" -gt 0 ]; then
        cp "$GATE_FILE" "$CHECKPOINT_FILE"
        echo "PostCompact: findings checkpoint saved ($active active findings)" >&2
    fi
fi

# Compact Resume Packet 生成（Haiku で構造化）
# transcript_path と compact_summary から目的・決定・意図・依存・未完了を抽出
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // ""')
RESUME_FILE="$STATE_DIR/compact_resume.json"

# Haiku API 呼び出しに必要な認証を試みる
API_KEY="${ANTHROPIC_API_KEY:-}"
if [ -z "$API_KEY" ]; then
    # keychain からトークン取得を試みる
    SESSION_TOKEN="${CLAUDE_CODE_SESSION_ACCESS_TOKEN:-}"
    if [ -z "$SESSION_TOKEN" ]; then
        # keychain 経由は shell から複雑なので、compact_summary から機械的に抽出
        if [ -n "$COMPACT_SUMMARY" ]; then
            cat > "$RESUME_FILE" << RESUME
{
  "schema_version": 1,
  "source": "mechanical",
  "compact_count": $count,
  "compact_summary_excerpt": $(echo "$COMPACT_SUMMARY" | head -c 2000 | jq -Rs .),
  "created_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
RESUME
            echo "PostCompact: compact_resume.json saved (mechanical extraction)" >&2
        fi
        exit 0
    fi
fi

# API key がある場合は Haiku で構造化抽出
if [ -n "$API_KEY" ] && [ -n "$COMPACT_SUMMARY" ]; then
    HAIKU_RESPONSE=$(curl -s --max-time 15 https://api.anthropic.com/v1/messages \
        -H "x-api-key: $API_KEY" \
        -H "anthropic-version: 2023-06-01" \
        -H "content-type: application/json" \
        -d "$(jq -n \
            --arg summary "$COMPACT_SUMMARY" \
            '{
                model: "claude-haiku-4-5-20251001",
                max_tokens: 512,
                messages: [{
                    role: "user",
                    content: ("Extract structured resume state from this compact summary. Output JSON only with these fields: objective (1 line), current_subtask (1 line), done_criteria (array of strings, max 5), decisions (array of {what, why}), working_files (array of {path, intent, status}), open_loops (array of strings), next_actions (array of strings). Be concise. Japanese OK.\n\nSummary:\n" + $summary)
                }]
            }')" 2>/dev/null || true)

    if [ -n "$HAIKU_RESPONSE" ]; then
        RESUME_CONTENT=$(echo "$HAIKU_RESPONSE" | jq -r '.content[0].text // ""' 2>/dev/null || true)
        if echo "$RESUME_CONTENT" | jq empty 2>/dev/null; then
            # valid JSON
            jq -n \
                --arg src "haiku" \
                --argjson count "$count" \
                --argjson resume "$RESUME_CONTENT" \
                '{schema_version: 1, source: $src, compact_count: $count, resume: $resume, created_at: (now | todate)}' \
                > "$RESUME_FILE"
            echo "PostCompact: compact_resume.json saved (haiku extraction)" >&2
        else
            # Haiku がプレーンテキストを返した場合
            cat > "$RESUME_FILE" << RESUME
{
  "schema_version": 1,
  "source": "haiku_text",
  "compact_count": $count,
  "resume_text": $(echo "$RESUME_CONTENT" | head -c 2000 | jq -Rs .),
  "created_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
RESUME
            echo "PostCompact: compact_resume.json saved (haiku text fallback)" >&2
        fi
    fi
fi

exit 0
