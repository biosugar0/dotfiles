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
      r=$(git -C "$p" remote get-url origin 2>/dev/null | sed 's/\.git$//;s|.*/||')
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
    r=$(git -C "$hook_cwd" remote get-url origin 2>/dev/null | sed 's/\.git$//;s|.*/||')
    b=$(git -C "$hook_cwd" branch --show-current 2>/dev/null)
    h=$(git -C "$hook_cwd" rev-parse --short HEAD 2>/dev/null)
    if [ -f "/tmp/.codex-review-done--${r}--${b}--${h}" ]; then
      found=true
    fi
  fi

  # repo名 glob フォールバック（変数経由cd等でパス抽出不可の場合）
  if [ "$found" = false ]; then
    repo=$(git -C "$hook_cwd" remote get-url origin 2>/dev/null | sed 's/\.git$//;s|.*/||')
    for marker in /tmp/.codex-review-done--"${repo}"--*; do
      if [ -f "$marker" ]; then
        found=true
        break
      fi
    done
  fi

  # evaluator gate チェック（codex review 通過後）
  if [ "$found" = true ]; then
    gate_file="$hook_cwd/ai/state/workflow-gate.json"
    if [ -f "$gate_file" ] && command -v jq &>/dev/null; then
      gate_sha=$(jq -r '.head_sha // ""' "$gate_file")
      gate_status=$(jq -r '.evaluator.status // ""' "$gate_file")
      current_sha=$(git -C "$hook_cwd" rev-parse --short HEAD 2>/dev/null)

      if [ "$gate_sha" != "$current_sha" ]; then
        # head が変わっている（evaluator 後にコミットされた）→ 警告のみ、ブロックしない
        echo "evaluator: HEAD が変わっています（gate: $gate_sha, current: $current_sha）" >&2
      elif [ "$gate_status" = "FAIL" ]; then
        # evaluator FAIL → 警告のみ、ブロックしない（soft recommendation）
        gate_summary=$(jq -r '.evaluator.summary // ""' "$gate_file")
        echo "evaluator: FAIL — $gate_summary（修正推奨）" >&2
      fi
    else
      # workflow-gate.json が存在しない → evaluator 未実施の警告
      echo "evaluator: 未実施。/evaluator で品質評価を実行することを推奨します。" >&2
    fi
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
