#!/bin/bash
# PreToolUse hook: Block gh pr create without codex review
# マーカー形式: /tmp/.codex-review-done--{repo}--{branch}--{hash}

input=$(cat)

command=$(echo "$input" | jq -r '.tool_input.command // empty')

# gh pr create をチェック（cd && gh pr create 等のパターンも検出）
if echo "$command" | grep -qE '(^|[;&|] *)gh pr create( |$)'; then
  hook_cwd=$(echo "$input" | jq -r '.cwd')
  found=false

  # コマンド内の絶対パスを抽出し、git リポジトリなら直接チェック
  while IFS= read -r p; do
    if [ -d "$p" ] && git -C "$p" rev-parse --git-dir &>/dev/null; then
      r=$(basename "$(git -C "$p" rev-parse --show-toplevel 2>/dev/null)")
      b=$(git -C "$p" branch --show-current 2>/dev/null)
      h=$(git -C "$p" rev-parse --short HEAD 2>/dev/null)
      if [ -f "/tmp/.codex-review-done--${r}--${b}--${h}" ]; then
        found=true
        break
      fi
    fi
  done < <(echo "$command" | grep -oE '/[^"'\''[:space:];&|)]+' | sort -u)

  # hook_cwd でフォールバック
  if [ "$found" = false ]; then
    r=$(basename "$(git -C "$hook_cwd" rev-parse --show-toplevel 2>/dev/null)")
    b=$(git -C "$hook_cwd" branch --show-current 2>/dev/null)
    h=$(git -C "$hook_cwd" rev-parse --short HEAD 2>/dev/null)
    if [ -f "/tmp/.codex-review-done--${r}--${b}--${h}" ]; then
      found=true
    fi
  fi

  # repo名 glob フォールバック（変数経由cd等でパス抽出不可の場合）
  if [ "$found" = false ]; then
    repo=$(basename "$(git -C "$hook_cwd" rev-parse --show-toplevel 2>/dev/null)")
    for marker in /tmp/.codex-review-done--"${repo}"--*; do
      if [ -f "$marker" ]; then
        found=true
        break
      fi
    done
  fi

  if [ "$found" = false ]; then
    jq -n '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: "Codex reviewが未実施。先にcodex-tmux skillでレビューを受けてからPRを作成すること。"
      }
    }'
  fi
fi

exit 0
