#!/bin/bash
# Preview helper for claude-pane-picker.sh.
# Args: <pane_id> <jsonl_path-or-empty>
# Output: latest user prompt + latest assistant text from the jsonl,
# followed by a short live pane tail. Falls back to pane capture only
# when the jsonl is missing.
set -eu

pane_id="${1:-}"
jsonl="${2:-}"

# Extract the most recent assistant text content (iterates from last entry
# backwards until a non-empty text block is found).
latest_assistant() {
  local f=$1
  grep '"type":"assistant"' "$f" 2>/dev/null | tail -r 2>/dev/null | head -20 \
    | while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local text
        text=$(printf '%s' "$line" | jq -r '
          .message.content
          | if type=="array" then ([.[]? | select(.type=="text") | .text] | join("\n\n"))
            else "" end' 2>/dev/null)
        if [[ -n "$text" ]]; then
          printf '%s' "$text"
          return 0
        fi
      done
}

# Extract the most recent user-typed prompt (string or text-block content),
# skipping auto-injected boilerplate.
latest_user() {
  local f=$1
  grep '"type":"user"' "$f" 2>/dev/null | tail -r 2>/dev/null | head -40 \
    | while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local text
        text=$(printf '%s' "$line" | jq -r '
          select((.message.role // "") == "user")
          | .message.content
          | if type=="string" then .
            elif type=="array" then ([.[]? | select(.type=="text") | .text] | join(" "))
            else "" end' 2>/dev/null)
        text=$(printf '%s' "$text" | sed -E 's/^ +//; s/ +$//')
        if [[ -n "$text" \
            && "$text" != "<system-reminder>"* \
            && "$text" != "Base directory for this skill:"* \
            && "$text" != "<command-"* \
            && "$text" != "[Request interrupted by user]"* ]]; then
          printf '%s' "$text"
          return 0
        fi
      done
}

if [[ -n "$jsonl" && -f "$jsonl" ]]; then
  user_msg=$(latest_user "$jsonl" || true)
  asst_msg=$(latest_assistant "$jsonl" || true)
  printf '━━ User (latest) ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n'
  printf '%s\n\n' "${user_msg:-(none)}"
  printf '━━ Assistant (latest) ━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n'
  printf '%s\n\n' "${asst_msg:-(no text response yet)}"
fi

if [[ -n "$pane_id" ]]; then
  printf '━━ Live pane tail ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n'
  tmux capture-pane -pJ -t "$pane_id" -S -100 2>/dev/null | tail -n 15
fi
