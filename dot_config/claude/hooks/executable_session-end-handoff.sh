#!/usr/bin/env bash
# SessionEnd hook: 軽量な git 状態スナップショットを handoff.json に記録
# 主経路ではなく補助。一次保存は PreCompact + /save-session。

set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
HANDOFF_FILE="${PROJECT_DIR}/ai/state/handoff.json"

# git リポジトリでなければスキップ
if ! git -C "$PROJECT_DIR" rev-parse --is-inside-work-tree &>/dev/null; then
  exit 0
fi

BRANCH=$(git -C "$PROJECT_DIR" branch --show-current 2>/dev/null || echo "unknown")
HEAD_SHA=$(git -C "$PROJECT_DIR" rev-parse --short HEAD 2>/dev/null || echo "unknown")
DIRTY_COUNT=$(git -C "$PROJECT_DIR" status --porcelain 2>/dev/null | wc -l | tr -d ' ')

# 既存の handoff.json があれば last_commit を更新するだけ
if [ -f "$HANDOFF_FILE" ]; then
  # jq が使えれば使う、なければスキップ
  if command -v jq &>/dev/null; then
    tmp=$(mktemp)
    jq --arg sha "$HEAD_SHA" --arg branch "$BRANCH" --arg dirty "$DIRTY_COUNT" \
      '.progress.last_commit = $sha | .progress.current_branch = $branch | .progress.dirty_files = ($dirty | tonumber)' \
      "$HANDOFF_FILE" > "$tmp" && mv "$tmp" "$HANDOFF_FILE"
  fi
  exit 0
fi

# handoff.json がなければ最小限のスナップショットを作成
mkdir -p "$(dirname "$HANDOFF_FILE")"
cat > "$HANDOFF_FILE" << EOF
{
  "schema_version": 1,
  "created_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "progress": {
    "current_branch": "$BRANCH",
    "last_commit": "$HEAD_SHA",
    "dirty_files": $DIRTY_COUNT
  }
}
EOF
