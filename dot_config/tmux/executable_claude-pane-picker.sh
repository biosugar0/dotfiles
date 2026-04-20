#!/bin/bash
# Interactive claude pane picker. Launched from tmux display-popup.
# Lists claude-like panes across all sessions, enriched with the first
# user message from ~/.config/claude/sessions/<pid>.json + the matching
# jsonl transcript. Previews each pane with `tmux capture-pane` and
# switches client on Enter.
set -eu

SESSIONS_DIR="$HOME/.config/claude/sessions"
PROJECTS_DIR="$HOME/.config/claude/projects"

# Find the claude PID in a pane's subtree by correlating with session files.
find_claude_pid() {
  local pane_pid=$1
  pgrep -P "$pane_pid" 2>/dev/null | while read -r cpid; do
    if [[ -f "$SESSIONS_DIR/$cpid.json" ]]; then
      echo "$cpid"
      return
    fi
  done | head -n1
}

# Extract first meaningful user message from a jsonl transcript.
# Skips "pick-task" (zsh function default), system-reminder blocks,
# and tool_result arrays. Returns first string content or first array
# text block that passes the filter.
first_user_msg() {
  local jsonl=$1
  [[ -f "$jsonl" ]] || { echo ""; return; }
  local msg="" text
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    text=$(printf '%s' "$line" | jq -r '
      select((.message.role // "") == "user")
      | .message.content
      | if type=="string" then .
        elif type=="array" then ([.[]? | select(.type=="text") | .text] | join(" "))
        else "" end' 2>/dev/null)
    text=$(printf '%s' "$text" | tr '\n\r\t' '   ' | sed -E 's/^ +//; s/ +$//')
    if [[ -n "$text" \
        && "$text" != "pick-task" \
        && "$text" != "<system-reminder>"* \
        && "$text" != "Base directory for this skill:"* \
        && "$text" != "<command-"* \
        && "$text" != "[Request interrupted by user]"* ]]; then
      msg="$text"
      break
    fi
  done < <(grep -m40 '"type":"user"' "$jsonl" 2>/dev/null)
  printf '%s' "${msg:0:60}"
}

list=$(tmux list-panes -a -F '#{session_name}:#{window_index}.#{pane_index}|#{pane_id}|#{pane_pid}|#{pane_current_command}|#{pane_current_path}' 2>/dev/null || true)
if [[ -z "$list" ]]; then
  tmux display-message "no panes"
  exit 0
fi

rows=""
while IFS='|' read -r target pane_id pane_pid cmd cwd; do
  [[ -z "$cmd" ]] && continue
  case "$cmd" in
    [0-9]*.[0-9]*.[0-9]*|*claude*) ;;
    *) continue ;;
  esac
  project=$(basename "${cwd:-unknown}")
  claude_pid=$(find_claude_pid "$pane_pid" || true)
  msg=""
  if [[ -n "$claude_pid" && -f "$SESSIONS_DIR/$claude_pid.json" ]]; then
    sid=$(jq -r .sessionId "$SESSIONS_DIR/$claude_pid.json" 2>/dev/null || true)
    scwd=$(jq -r .cwd "$SESSIONS_DIR/$claude_pid.json" 2>/dev/null || true)
    if [[ -n "$sid" && -n "$scwd" ]]; then
      encoded=$(printf '%s' "$scwd" | sed -e 's|/|-|g' -e 's|\.|-|g')
      msg=$(first_user_msg "$PROJECTS_DIR/$encoded/$sid.jsonl")
    fi
  fi
  rows+="$target"$'\t'"$project"$'\t'"$msg"$'\t'"$cmd"$'\t'"$pane_id"$'\n'
done <<< "$list"

[[ -z "$rows" ]] && { tmux display-message "no claude panes"; exit 0; }

selected=$(printf '%s' "$rows" \
  | fzf --delimiter=$'\t' \
        --with-nth=1,2,3 \
        --header='target / project / first-message' \
        --preview 'tmux capture-pane -p -t {5} -S -50' \
        --preview-window=right:60% || true)

[[ -z "$selected" ]] && exit 0
target=$(awk -F'\t' '{print $1}' <<< "$selected")
tmux switch-client -t "$target"
