#!/bin/bash
# Preview helper for claude-pane-picker.sh.
# Args: <pane_id> <jsonl_path-or-empty>
# Output: latest user prompt + latest assistant text from the jsonl,
# followed by a short live pane tail. Falls back to pane capture only
# when the jsonl is missing.
set -eu

pane_id="${1:-}"
jsonl="${2:-}"

# Extract the most recent assistant text content. Reads only the last
# 500KB of the jsonl to stay fast on multi-MB transcripts.
latest_assistant() {
  local f=$1
  tail -c 500000 "$f" 2>/dev/null \
    | grep '"type":"assistant"' \
    | tail -r 2>/dev/null \
    | head -20 \
    | jq -rs '
        map(.message.content
            | if type=="array" then ([.[]? | select(.type=="text") | .text] | join("\n\n"))
              else "" end
            | select(length > 0))
        | (.[0] // "")' 2>/dev/null
}

# Extract the most recent user-typed prompt (string or text-block content),
# skipping auto-injected boilerplate. Reads only the last 500KB.
latest_user() {
  local f=$1
  tail -c 500000 "$f" 2>/dev/null \
    | grep '"type":"user"' \
    | tail -r 2>/dev/null \
    | head -40 \
    | jq -rs '
        map(select((.message.role // "") == "user")
            | .message.content
            | if type=="string" then .
              elif type=="array" then ([.[]? | select(.type=="text") | .text] | join(" "))
              else "" end
            | sub("^ +"; "") | sub(" +$"; "")
            | select(length > 0
                and (startswith("<system-reminder>") | not)
                and (startswith("Base directory for this skill:") | not)
                and (startswith("<command-") | not)
                and (startswith("[Request interrupted by user]") | not)))
        | (.[0] // "")' 2>/dev/null
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
