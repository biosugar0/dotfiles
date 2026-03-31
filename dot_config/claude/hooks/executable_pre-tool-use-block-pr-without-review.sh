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

  # --repo フラグからリポジトリ名を抽出してマーカー検索
  # worktree 環境では hook_cwd が別リポジトリを指すため、コマンド内の --repo + --head で検証
  if [ "$found" = false ]; then
    cli_repo=$(echo "$command" | grep -oE -- '--repo[= ]+[^ ]+' | sed 's/--repo[= ]*//' | sed 's|.*/||')
    cli_head=$(echo "$command" | grep -oE -- '--head[= ]+[^ ]+' | sed 's/--head[= ]*//')
    if [ -n "$cli_repo" ] && [ -n "$cli_head" ]; then
      # repo + branch で厳密マッチ（hash のみワイルドカード）
      for marker in /tmp/.codex-review-done--"${cli_repo}"--"${cli_head}"--*; do
        if [ -f "$marker" ]; then
          found=true
          break
        fi
      done
    fi
    # --head なし & --repo のみ → deny（安全側に倒す）
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
      # workflow-gate.json が存在しない → 変更が多い場合のみ evaluator 推奨
      changed_count=$(git -C "$hook_cwd" diff --name-only origin/main...HEAD 2>/dev/null | wc -l | tr -d ' ')
      if [ "${changed_count:-0}" -ge 5 ]; then
        echo "evaluator: 未実施（変更ファイル ${changed_count} 件）。/evaluator で品質評価を推奨。" >&2
      fi
    fi
  fi

  if [ "$found" = false ]; then
    # --repo あり & --head なしの場合、--head 付与を促すメッセージ
    cli_repo_check=$(echo "$command" | grep -oE -- '--repo[= ]+[^ ]+' | head -1)
    cli_head_check=$(echo "$command" | grep -oE -- '--head[= ]+[^ ]+' | head -1)
    if [ -n "$cli_repo_check" ] && [ -z "$cli_head_check" ]; then
      reason="Codex reviewが未実施、または --head フラグが不足。--head {branch} を付けて再試行すること。"
    else
      reason="Codex reviewが未実施。先にcodex-tmux skillでレビューを受けてからPRを作成すること。"
    fi
    jq -n --arg reason "$reason" '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: $reason
      }
    }'
  fi
fi

exit 0
