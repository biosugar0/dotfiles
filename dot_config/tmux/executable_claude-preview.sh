#!/bin/bash
# Preview helper for claude-pane-picker.sh.
# Args: <pane_id> <jsonl_path-or-empty>
# Output: latest user prompt + latest assistant text from the jsonl,
# followed by a short live pane tail. Falls back to pane capture only
# when the jsonl is missing.
set -eu

pane_id="${1:-}"
jsonl="${2:-}"

# Extract the most recent assistant text content from a pre-buffered stream.
latest_assistant() {
  grep '"type":"assistant"' \
    | tail -r 2>/dev/null \
    | head -20 \
    | jq -rs '
        map(.message.content
            | if type=="array" then ([.[]? | select(.type=="text") | .text] | join("\n\n"))
              else "" end
            | select(length > 0))
        | (.[0] // "")' 2>/dev/null
}

# Extract the most recent user-typed prompt from a pre-buffered stream.
latest_user() {
  grep '"type":"user"' \
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

# ANSI styling. fzf preview window interprets escape sequences natively.
BOLD=$'\033[1m'
DIM=$'\033[2m'
CYAN=$'\033[38;5;75m'
GREEN=$'\033[38;5;114m'
YELLOW=$'\033[38;5;179m'
GREY=$'\033[38;5;244m'
RESET=$'\033[0m'

# Render a section header: colored block + uppercase label + dimmed meta.
header() {
  local color=$1 label=$2 meta=${3:-}
  local meta_str=""
  [[ -n "$meta" ]] && meta_str="${DIM} · ${meta}${RESET}"
  printf '%s▌%s %s%s%s%s\n' "$color" "$RESET" "${BOLD}${color}" "$label" "${RESET}" "$meta_str"
}

# Trim a block to fit the preview viewport (prints last N lines).
trim_tail() {
  local max=$1 input=$2 n
  n=$(printf '%s' "$input" | awk 'END{print NR}')
  if [[ "$n" -gt "$max" ]]; then
    printf '%s' "$input" | tail -n "$max"
  else
    printf '%s' "$input"
  fi
}

# Meta string describing trim status, e.g. "72 lines · last 30" or "4 lines".
meta_for() {
  local max=$1 input=$2 n
  n=$(printf '%s' "$input" | awk 'END{print NR}')
  if [[ "$n" -gt "$max" ]]; then
    printf '%d lines · last %d' "$n" "$max"
  elif [[ "$n" -le 1 ]]; then
    printf '%d line' "$n"
  else
    printf '%d lines' "$n"
  fi
}

if [[ -n "$jsonl" && -f "$jsonl" ]]; then
  # Read the last 200KB of the transcript once; extract user/assistant
  # in parallel subshells that read from the shared temp file.
  tmp=$(mktemp)
  tail -c 200000 "$jsonl" > "$tmp"
  latest_user   < "$tmp" > "$tmp.user"   &
  latest_assistant < "$tmp" > "$tmp.asst" &
  wait
  user_msg=$(cat "$tmp.user")
  asst_msg=$(cat "$tmp.asst")
  rm -f "$tmp" "$tmp.user" "$tmp.asst"

  umsg="${user_msg:-(none)}"
  amsg="${asst_msg:-(no text response yet)}"
  header "$CYAN" "USER" "$(meta_for 10 "$umsg")"
  printf '%s\n\n' "$(trim_tail 10 "$umsg")"
  header "$GREEN" "ASSISTANT" "$(meta_for 30 "$amsg")"
  printf '%s\n\n' "$(trim_tail 30 "$amsg")"
fi

if [[ -n "$pane_id" ]]; then
  header "$YELLOW" "LIVE PANE" "$pane_id"
  tmux capture-pane -pJ -t "$pane_id" -S -100 2>/dev/null | tail -n 15
fi
