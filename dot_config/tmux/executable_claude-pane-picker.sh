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

# Extract user-specified custom title from /rename. Latest wins.
# Scans only the last 200KB to stay fast on multi-MB transcripts.
custom_title() {
  local jsonl=$1
  [[ -f "$jsonl" ]] || { echo ""; return; }
  tail -c 200000 "$jsonl" 2>/dev/null \
    | grep '"type":"custom-title"' \
    | tail -1 \
    | jq -r '.customTitle // ""' 2>/dev/null \
    | tr '\n\r\t' '   ' \
    | cut -c1-60
}

# Extract first meaningful user message from a jsonl transcript.
# Skips "pick-task" (zsh function default), system-reminder blocks,
# and tool_result arrays. Returns first string content or first array
# text block that passes the filter. Single-pass jq (~10ms vs ~400ms
# when invoked per line).
first_user_msg() {
  local jsonl=$1
  [[ -f "$jsonl" ]] || { echo ""; return; }
  grep -m40 '"type":"user"' "$jsonl" 2>/dev/null \
    | jq -rs '
        map(select((.message.role // "") == "user")
            | .message.content
            | if type=="string" then .
              elif type=="array" then ([.[]? | select(.type=="text") | .text] | join(" "))
              else "" end
            | gsub("[\n\r\t]"; " ")
            | sub("^ +"; "") | sub(" +$"; "")
            | select(length > 0
                and . != "pick-task"
                and (startswith("<system-reminder>") | not)
                and (startswith("Base directory for this skill:") | not)
                and (startswith("<command-") | not)
                and (startswith("[Request interrupted by user]") | not)))
        | (.[0] // "")[0:60]' 2>/dev/null
}

list=$(tmux list-panes -a -F '#{session_name}:#{window_index}.#{pane_index}|#{pane_id}|#{pane_pid}|#{pane_current_command}|#{pane_current_path}' 2>/dev/null || true)
if [[ -z "$list" ]]; then
  tmux display-message "no panes"
  exit 0
fi

# Per-pane row builder. Prints a tab-separated row to stdout; intended to
# run as a background job so rows stream into fzf as soon as each pane's
# extraction finishes.
process_pane() {
  local target=$1 pane_id=$2 pane_pid=$3 cmd=$4 cwd=$5
  local project claude_pid msg jsonl sid scwd encoded title
  project=$(basename "${cwd:-unknown}")
  claude_pid=$(find_claude_pid "$pane_pid" || true)
  msg=""
  jsonl=""
  if [[ -n "$claude_pid" && -f "$SESSIONS_DIR/$claude_pid.json" ]]; then
    IFS='|' read -r sid scwd < <(jq -r '"\(.sessionId)|\(.cwd)"' "$SESSIONS_DIR/$claude_pid.json" 2>/dev/null || true)
    if [[ -n "${sid:-}" && -n "${scwd:-}" ]]; then
      encoded=$(printf '%s' "$scwd" | sed -e 's|/|-|g' -e 's|\.|-|g')
      jsonl="$PROJECTS_DIR/$encoded/$sid.jsonl"
      title=$(custom_title "$jsonl")
      if [[ -n "$title" && "$title" != "$project/"* && "$title" != "$project" ]]; then
        msg="$title"
      else
        msg=$(first_user_msg "$jsonl")
      fi
    fi
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$target" "$project" "$msg" "$cmd" "$pane_id" "$jsonl"
}

# Stream each pane's row into fzf as soon as its extraction finishes.
# fzf can render partial lists immediately so the popup feels responsive
# even before the slowest jsonl finishes parsing.
# NOTE: filtering uses [[ ]] instead of `case`, because bash's parser
# mishandles a `)` inside a case pattern when the whole block lives
# inside $(...) — triggered the `syntax error near unexpected token ";;"`
# on the deployed script.
selected=$(
  {
    while IFS='|' read -r target pane_id pane_pid cmd cwd; do
      [[ -z "$cmd" ]] && continue
      if [[ "$cmd" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ || "$cmd" == *claude* ]]; then
        process_pane "$target" "$pane_id" "$pane_pid" "$cmd" "$cwd" &
      fi
    done <<< "$list"
    wait
  } \
  | fzf --ansi \
        --delimiter=$'\t' \
        --with-nth=1,2,3 \
        --header='target / project / title-or-first-message' \
        --preview "$HOME/.config/tmux/claude-preview.sh {5} {6}" \
        --preview-window=right:60%:wrap \
        --preview-wrap-sign=' ' || true
)

[[ -z "$selected" ]] && exit 0
target=$(awk -F'\t' '{print $1}' <<< "$selected")
tmux switch-client -t "$target"
