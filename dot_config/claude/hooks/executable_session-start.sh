#!/bin/bash
# Session Start Hook - Inject project context at startup
# Based on Anthropic's "Getting up to speed" best practices

set -e

# Read input from stdin (contains session info)
INPUT=$(cat)
SOURCE=$(echo "$INPUT" | jq -r '.source // "unknown"')

# Output context for Claude
output_context() {
    local context=""

    # 1. Current directory
    context+="## Session Context\n"
    context+="Working directory: $(pwd)\n"
    context+="Session source: $SOURCE\n"
    context+="\n"

    # 2. Git information (if in git repo)
    if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        context+="## Git Status\n"
        context+="Branch: $(git branch --show-current 2>/dev/null || echo 'detached')\n"

        # Recent commits
        context+="\n### Recent commits (last 5):\n"
        context+="\`\`\`\n"
        git log --oneline -5 2>/dev/null || echo "No commits"
        context+="\`\`\`\n"

        # Uncommitted changes summary
        CHANGES=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
        if [ "$CHANGES" -gt 0 ]; then
            context+="\n### Uncommitted changes: $CHANGES files\n"
        fi
        context+="\n"
    fi

    # 3. Check for recent session handoff files (ai/log/sessions/)
    # Git情報は上で取得済みのため、会話分析部分のみ抽出
    if [ -d "$CLAUDE_PROJECT_DIR/ai/log/sessions" ]; then
        LATEST_SESSION=$(ls -t "$CLAUDE_PROJECT_DIR/ai/log/sessions/"*.md 2>/dev/null | head -1)
        if [ -n "$LATEST_SESSION" ]; then
            context+="## Previous Session Summary\n"
            context+="File: $(basename "$LATEST_SESSION")\n"
            # "## Conversation Analysis" セクションのみ抽出（Git情報重複排除）
            CONV_ANALYSIS=$(sed -n '/^## Conversation Analysis/,/^---/p' "$LATEST_SESSION" 2>/dev/null | head -30)
            if [ -n "$CONV_ANALYSIS" ]; then
                context+="\`\`\`\n"
                echo "$CONV_ANALYSIS"
                context+="\`\`\`\n"
            fi
            context+="\n"
        fi
    fi

    # 4. Check for feature_list.json
    if [ -f "$CLAUDE_PROJECT_DIR/feature_list.json" ]; then
        INCOMPLETE=$(jq '[.features[] | select(.passes == false)] | length' "$CLAUDE_PROJECT_DIR/feature_list.json" 2>/dev/null || echo "0")
        if [ "$INCOMPLETE" -gt 0 ]; then
            context+="## Feature Status\n"
            context+="Incomplete features: $INCOMPLETE\n"
            context+="Next priority feature:\n"
            context+="\`\`\`json\n"
            jq '[.features[] | select(.passes == false)] | sort_by(.priority) | .[0]' "$CLAUDE_PROJECT_DIR/feature_list.json" 2>/dev/null
            context+="\`\`\`\n\n"
        fi
    fi

    echo -e "$context"
}

# Output JSON with additionalContext
CONTEXT=$(output_context)

# Use jq to properly escape the context for JSON
echo "{\"hookSpecificOutput\":{\"hookEventName\":\"SessionStart\",\"additionalContext\":$(echo "$CONTEXT" | jq -Rs .)}}"

exit 0
