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

# 既存の handoff.json がなければスキップ（自動生成しない）
# handoff.json は /save-session context-reset で明示的に作成するもの
if [ ! -f "$HANDOFF_FILE" ]; then
  exit 0
fi

# jq が使えなければスキップ
if ! command -v jq &>/dev/null; then
  exit 0
fi

# 既存の handoff.json を更新（created_at は触らない — freshness 判定の基準）
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
tmp=$(mktemp)
if jq --arg sha "$HEAD_SHA" --arg branch "$BRANCH" --arg dirty "$DIRTY_COUNT" --arg now "$NOW" \
  '.updated_at = $now | .progress.last_commit = $sha | .progress.current_branch = $branch | .progress.dirty_files = ($dirty | tonumber)' \
  "$HANDOFF_FILE" > "$tmp" 2>/dev/null; then
  mv "$tmp" "$HANDOFF_FILE"
else
  rm -f "$tmp"
  # JSON が壊れている場合は静かにスキップ
fi
