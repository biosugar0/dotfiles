#!/usr/bin/env bash
# UserPromptSubmit hook:
#   - additionalContext に golden-rules + workflow + git status + goal status + 現在時刻を集約注入
#   - sessionTitle を Haiku 要約キャッシュ（なければ dir/branch）から設定
#   - ただし手動 /rename を尊重: transcript 上の現在名が「この hook が前回設定した名前」
#     (state file) と異なる場合は手動 rename とみなし、以後 sessionTitle を注入しない
set -euo pipefail

# Read stdin JSON
stdin_json=$(cat)
session_id=$(echo "$stdin_json" | jq -r '.session_id // empty')
transcript_path=$(echo "$stdin_json" | jq -r '.transcript_path // empty')
prompt=$(echo "$stdin_json" | jq -r '.prompt // empty')

# djb2 hash (same algorithm as stop-hook.ts) — base36 output
djb2() {
  printf '%s' "$1" | python3 -c "
import sys
s=sys.stdin.read();h=5381
for c in s:h=((h<<5)+h+ord(c))&0xFFFFFFFF
d='0123456789abcdefghijklmnopqrstuvwxyz';r=''
while h:r=d[h%36]+r;h//=36
print(r or '0',end='')
"
}

# Build fallback title from dir/branch
dir=$(basename "${CLAUDE_PROJECT_DIR:-$(pwd)}")
branch=$(git -C "${CLAUDE_PROJECT_DIR:-.}" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
fallback="${dir}"
[ -n "$branch" ] && fallback="${dir}/${branch}"

# Try to read Haiku summary from statusline cache
title="$fallback"
if [ -n "$session_id" ]; then
  cache_file="/tmp/claude-session-summaries/${session_id}.json"
  if [ -f "$cache_file" ]; then
    cached_slug=$(jq -r '.slug // empty' "$cache_file" 2>/dev/null || true)
    # 旧形式キャッシュや生成不良 ("-" 単体等) を弾く: kebab-case 2-5語のみ採用
    if printf '%s' "$cached_slug" | grep -Eq '^[a-z0-9]+(-[a-z0-9]+){1,4}$'; then
      title="$cached_slug"
    fi
  fi
fi

# 手動 /rename の検出: 現在名 (transcript の custom-title 末尾) が state file
# (この hook が最後に設定した名前) と異なる = ユーザーが /rename した。
# state file が無い初回は判定不能なので従来通り設定する (直後の /rename から尊重される)
title_state_dir="/tmp/claude-session-titles"
title_state_file=""
skip_title=0
if [ -n "$session_id" ]; then
  title_state_file="${title_state_dir}/${session_id}"
  if [ -f "$title_state_file" ] && [ -n "$transcript_path" ] && [ -f "$transcript_path" ]; then
    last_set=$(cat "$title_state_file" 2>/dev/null || true)
    current_name=$(grep '"type":"custom-title"' "$transcript_path" 2>/dev/null \
      | tail -n 1 | jq -r '.customTitle // empty' 2>/dev/null || true)
    if [ -n "$last_set" ] && [ -n "$current_name" ] && [ "$current_name" != "$last_set" ]; then
      skip_title=1
    fi
  fi
fi

# Assemble context sources（いずれも欠損時は空でフォールバック）
hook_data_dir=~/.config/claude/hooks/data
golden=$(cat "${hook_data_dir}/golden-rules.txt" 2>/dev/null || true)

workflow_full_file="${hook_data_dir}/workflow-instructions.md"
workflow_core_file="${hook_data_dir}/workflow-core.md"
workflow_file="$workflow_full_file"
if [ -n "$session_id" ]; then
  workflow_state_file="/tmp/claude-workflow-cycle-${session_id}"
  workflow_count=0
  if [ -r "$workflow_state_file" ]; then
    IFS= read -r workflow_count < "$workflow_state_file" || workflow_count=0
    case "$workflow_count" in
      ''|*[!0-9]*) workflow_count=0 ;;
    esac
  fi
  workflow_count=$((10#$workflow_count))
  workflow_next_count=$((workflow_count + 1))

  workflow_full_every="${CLAUDE_WORKFLOW_FULL_EVERY:-10}"
  case "$workflow_full_every" in
    ''|*[!0-9]*) workflow_full_every=10 ;;
  esac
  workflow_full_every=$((10#$workflow_full_every))
  if [ "$workflow_full_every" -le 0 ] 2>/dev/null; then
    workflow_full_every=10
  fi

  inject_full_workflow=0
  compact_resume_file="${CLAUDE_PROJECT_DIR:-$(pwd)}/ai/state/${session_id}/compact_resume.json"
  if [ ! -e "$workflow_state_file" ]; then
    inject_full_workflow=1
  elif [ $((workflow_next_count % workflow_full_every)) -eq 0 ]; then
    inject_full_workflow=1
  elif [ -f "$compact_resume_file" ] && [ "$compact_resume_file" -nt "$workflow_state_file" ]; then
    inject_full_workflow=1
  fi

  if [ "$inject_full_workflow" != "1" ] && [ -f "$workflow_core_file" ]; then
    workflow_file="$workflow_core_file"
  fi
  printf '%s\n' "$workflow_next_count" > "$workflow_state_file" 2>/dev/null || true
fi
workflow=$(cat "$workflow_file" 2>/dev/null || true)

# モデル別ルールの出し分け:
# sonnet-bash-runner 委譲・tool-call タグ破損対策は Opus 固有。モデルは自分が何かを
# 確実には知らないため「Opus 稼働時は…」という自己条件付きルールは機能しない。
# transcript の直近 assistant メッセージから現行モデルを決定的に判定して注入を切り替える。
# 判定不能（セッション先頭・読取失敗）は既定 main=Opus に合わせて注入側に倒す。
model=""
if [ -n "$transcript_path" ] && [ -f "$transcript_path" ]; then
  model=$(tail -n 100 "$transcript_path" 2>/dev/null \
    | jq -r 'select(.type == "assistant") | .message.model // empty' 2>/dev/null \
    | tail -n 1 || true)
fi
case "$model" in
  ""|*opus*)
    opus_rules=$(cat "${hook_data_dir}/golden-rules-opus.txt" 2>/dev/null || true)
    [ -n "$opus_rules" ] && golden=$(printf '%s\n%s' "$golden" "$opus_rules")
    ;;
esac

# tool-call タグ破損バックストップ:
# 直前 assistant メッセージが未実行 tool call の漏洩(</invoke> 終端・tool_use 不成立)の
# まま残っていれば警告を注入する。stop-hook 不発(クラッシュ等)時の保険で、
# 判定基準は stop-hook.ts detectToolcallLeakInText と同一(tail-anchor)。
leak_block=""
if [ -n "$transcript_path" ] && [ -f "$transcript_path" ]; then
  stranded=$(tail -n 50 "$transcript_path" 2>/dev/null \
    | jq -c -R 'fromjson? // empty' 2>/dev/null \
    | jq -rs '
      [ .[] | select(.type == "assistant") ] | last // {} |
      (.message.content // []) as $c |
      if ($c | type) != "array" then "no"
      elif ([$c[] | select(.type == "tool_use")] | length) > 0 then "no"
      else
        ([$c[] | select(.type == "text") | .text // ""] | join("\n")
         | sub("\\s+$"; "")) as $t |
        if ($t | endswith("</invoke>")) and ($t | contains("<parameter name=")) then "yes" else "no" end
      end' 2>/dev/null || true)
  if [ "$stranded" = "yes" ]; then
    leak_block=$(printf '\n## ⚠ 未実行 tool call の漏洩あり\n直前の assistant 応答で tool call が text に漏洩したまま実行されていない(tool-call タグ破損)。ユーザー入力への対応時、必要ならそのコマンドを前置きテキストなしで実行し直すこと。漏洩 XML は verbatim 引用しない。\n')
  fi
fi

git_status=""
if git -C "${CLAUDE_PROJECT_DIR:-.}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git_status=$(git -C "${CLAUDE_PROJECT_DIR:-.}" status --short 2>/dev/null || true)
fi

# コーディング規律の条件注入:
# CLAUDE.md 置きだと user message としてセッション開始時に一度入るだけで長セッションで減衰する。
# working tree にソースコード変更がある（=実装局面）間だけ毎プロンプト再注入し、
# 調査・設計セッションではトークンを使わない。
coding_rules=""
if [ -n "$git_status" ] && printf '%s\n' "$git_status" \
  | grep -Eq '\.(ts|tsx|js|jsx|mjs|cjs|vue|svelte|py|go|rs|rb|java|kt|swift|c|h|cc|cpp|hpp|sql|prisma|proto|sh|bash|zsh|tf)$'; then
  coding_rules=$(cat "${hook_data_dir}/coding-rules.txt" 2>/dev/null || true)
fi

[ -z "$git_status" ] && git_status="（clean）"

# Goal status
goal_line=""
goal_file=""
if [ -n "$session_id" ]; then
  candidate="/tmp/claude-goal-s-${session_id}.json"
  [ -f "$candidate" ] && goal_file="$candidate"
fi
if [ -z "$goal_file" ] && [ -n "$transcript_path" ]; then
  goal_hash=$(djb2 "$transcript_path")
  candidate="/tmp/claude-goal-${goal_hash}.json"
  [ -f "$candidate" ] && goal_file="$candidate"
fi
if [ -n "$goal_file" ]; then
  goal_in_scope=1
  if [ -n "$prompt" ]; then
    prompt_hash=$(djb2 "$prompt")
    goal_user_hash=$(jq -r '.userHash // empty' "$goal_file" 2>/dev/null || true)
    if [ "$goal_user_hash" != "$prompt_hash" ]; then
      goal_in_scope=0
    fi
  fi
  if [ "$goal_in_scope" = "1" ]; then
    goal_condition=$(jq -r '.condition // empty' "$goal_file" 2>/dev/null || true)
    goal_iterations=$(jq -r '.iterations // 0' "$goal_file" 2>/dev/null || true)
    goal_target=$(jq -r '.targetTurns // empty' "$goal_file" 2>/dev/null || true)
    goal_set_at=$(jq -r '.setAt // empty' "$goal_file" 2>/dev/null || true)
    if [ -n "$goal_condition" ]; then
      elapsed=""
      if [ -n "$goal_set_at" ]; then
        now_ms=$(date +%s)000
        diff_s=$(( (${now_ms%000} - ${goal_set_at%???}) ))
        if [ "$diff_s" -ge 3600 ] 2>/dev/null; then
          elapsed="$(( diff_s / 3600 ))h$(( (diff_s % 3600) / 60 ))m"
        elif [ "$diff_s" -ge 60 ] 2>/dev/null; then
          elapsed="$(( diff_s / 60 ))m"
        else
          elapsed="${diff_s}s"
        fi
      fi
      turn_info="${goal_iterations}"
      [ -n "$goal_target" ] && [ "$goal_target" != "null" ] && turn_info="${goal_iterations}/${goal_target}"
      time_info=""
      [ -n "$elapsed" ] && time_info=", ${elapsed}"
      goal_line="Goal active (turn ${turn_info}${time_info}): ${goal_condition}"
    fi
  fi
fi

# Write goal status for tmux pane-border display
if [ -n "${TMUX_PANE:-}" ]; then
  pane_dir="/tmp/claude-goal-pane"
  mkdir -p "$pane_dir" 2>/dev/null
  if [ -n "$goal_line" ]; then
    printf '%s' "$goal_line" > "${pane_dir}/${TMUX_PANE}" 2>/dev/null
  else
    rm -f "${pane_dir}/${TMUX_PANE}" 2>/dev/null
  fi
fi

# Herdr: goal をサイドバー/pane 境界の custom status として報告 (tmux pane-border の代替)
if [ "${HERDR_ENV:-}" = "1" ] && [ -n "${HERDR_PANE_ID:-}" ] && command -v herdr >/dev/null 2>&1; then
  if [ -n "$goal_line" ]; then
    herdr pane report-metadata "$HERDR_PANE_ID" --source claude-goal \
      --custom-status "${goal_line:0:80}" >/dev/null 2>&1 || true
  else
    herdr pane report-metadata "$HERDR_PANE_ID" --source claude-goal \
      --clear-custom-status >/dev/null 2>&1 || true
  fi
fi

now=$(date '+%Y-%m-%d %H:%M')

# Single additionalContext payload
goal_block=""
[ -n "$goal_line" ] && goal_block=$(printf '\n## %s\n' "$goal_line")
coding_block=""
[ -n "$coding_rules" ] && coding_block=$(printf '\n\n%s' "$coding_rules")
context=$(printf '%s\n\n%s%s\n\n## Git status (--short)\n%s%s%s\n\n---\nCurrent time: %s\n' \
  "$golden" "$workflow" "$coding_block" "$git_status" "$goal_block" "$leak_block" "$now")

if [ "$skip_title" = "1" ]; then
  printf '%s' "$context" | jq -Rs \
    '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",additionalContext:.}}'
else
  if [ -n "$title_state_file" ]; then
    mkdir -p "$title_state_dir" 2>/dev/null || true
    printf '%s' "$title" > "$title_state_file" 2>/dev/null || true
  fi
  printf '%s' "$context" | jq -Rs --arg t "$title" \
    '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",additionalContext:.,sessionTitle:$t}}'
fi
