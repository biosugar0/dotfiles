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

# Haiku API 認証: keychain の OAuth トークンのみ。
# claude ランチャ(dot_config/zsh/dot_zshrc)が CLAUDE_CODE_OAUTH_TOKEN を unset し、
# ANTHROPIC_API_KEY も未使用のため、env 経由の認証トークンは hook に届かない。
# (Claude Code はデフォルトでは cred を scrub しない: CLAUDE_CODE_SUBPROCESS_ENV_SCRUB=1 が必要)

# compact_summary から機械的に resume を生成（Haiku 不可・失敗・タイムアウト時の共通フォールバック）
write_mechanical_resume() {
    [ -n "$COMPACT_SUMMARY" ] || return 0
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
}

# macOS keychain から有効な Claude Code OAuth トークンを取得
# lib/session-context.ts と同様に全 service を走査し、取得失敗・期限切れは skip して次を試す。
get_keychain_token() {
    command -v security >/dev/null 2>&1 || return 1
    local services svc raw token expires now
    services=$(security dump-keychain 2>/dev/null \
        | grep -oE '"svce"<blob>="Claude Code-credentials[^"]*"' \
        | sed -E 's/^"svce"<blob>="(.*)"$/\1/' \
        | awk '!seen[$0]++')
    if [ -z "$services" ]; then return 1; fi
    now=$(( $(date +%s) * 1000 ))
    while IFS= read -r svc; do
        [ -n "$svc" ] || continue
        raw=$(security find-generic-password -s "$svc" -w 2>/dev/null) || continue
        token=$(printf '%s' "$raw" | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null) || continue
        [ -n "$token" ] || continue
        expires=$(printf '%s' "$raw" | jq -r '.claudeAiOauth.expiresAt // 0' 2>/dev/null || echo 0)
        if [ "$expires" != "0" ] && [ "$expires" -lt "$now" ]; then continue; fi
        printf '%s' "$token"
        return 0
    done <<< "$services"
    return 1
}

TOKEN=$(get_keychain_token || true)

# keychain トークンが取れない場合は機械抽出で終了
if [ -z "$TOKEN" ]; then
    write_mechanical_resume
    exit 0
fi

# Haiku で構造化抽出（keychain OAuth トークンを Bearer + beta ヘッダで）。
# curl の --max-time は PostCompact hook timeout(20s)の 60-70% に収め、超過/失敗時は機械抽出へ。
if [ -n "$COMPACT_SUMMARY" ]; then
    HAIKU_RESPONSE=$(curl -s --max-time 13 https://api.anthropic.com/v1/messages \
        -H "authorization: Bearer $TOKEN" \
        -H "anthropic-beta: oauth-2025-04-20" \
        -H "anthropic-version: 2023-06-01" \
        -H "content-type: application/json" \
        -d "$(jq -n \
            --arg summary "$COMPACT_SUMMARY" \
            '{
                model: "claude-haiku-4-5-20251001",
                max_tokens: 512,
                messages: [{
                    role: "user",
                    content: ("Extract structured resume state from this compact summary. Output JSON only with these fields: objective (1 line), current_subtask (1 line), done_criteria (array of strings, max 5), decisions (array of {what, why}), working_files (array of {path, intent, status}), failed_attempts (array of {attempt, why_failed}, max 3, approaches that were tried and did NOT work), open_loops (array of strings), next_actions (array of strings). Be concise. Japanese OK.\n\nSummary:\n" + $summary)
                }]
            }')" 2>/dev/null || true)

    RESUME_CONTENT=""
    if [ -n "$HAIKU_RESPONSE" ]; then
        RESUME_CONTENT=$(echo "$HAIKU_RESPONSE" | jq -r '.content[0].text // ""' 2>/dev/null || true)
    fi

    # Haiku は JSON を ```json フェンスで包むことがある。先頭/末尾のフェンス行のみ除去してから判定
    RESUME_JSON=$(printf '%s\n' "$RESUME_CONTENT" \
        | sed -e '1{/^```[a-zA-Z]*[[:space:]]*$/d;}' -e '${/^```[[:space:]]*$/d;}')

    if [ -z "$RESUME_CONTENT" ]; then
        # curl 失敗 / 空応答 / content 欠落 → 機械抽出へフォールバック（resume 欠落を防ぐ）
        write_mechanical_resume
    elif echo "$RESUME_JSON" | jq empty 2>/dev/null; then
        # valid JSON
        jq -n \
            --arg src "haiku" \
            --argjson count "$count" \
            --argjson resume "$RESUME_JSON" \
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

exit 0
