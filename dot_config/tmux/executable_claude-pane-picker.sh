#!/bin/bash
# Interactive claude pane picker. Launched from tmux display-popup.
# Lists claude-like panes across all sessions, previews each with
# `tmux capture-pane`, and switches client on Enter.
set -eu

list=$(tmux list-panes -a -F '#{session_name}:#{window_index}.#{pane_index}|#{pane_id}|#{pane_current_command}|#{pane_current_path}' 2>/dev/null || true)
if [[ -z "$list" ]]; then
  tmux display-message "no panes"
  exit 0
fi

selected=$(printf '%s\n' "$list" \
  | awk -F'|' '$3 ~ /^[0-9]+\.[0-9]+\.[0-9]+$/ || $3 ~ /claude/ {
      n = split($4, a, "/"); proj = a[n]
      printf "%s\t%s\t%s\t%s\n", $1, proj, $3, $2
    }' \
  | fzf --delimiter=$'\t' \
        --with-nth=1,2,3 \
        --header='target / project / version' \
        --preview 'tmux capture-pane -p -t {4} -S -50' \
        --preview-window=right:60% || true)

[[ -z "$selected" ]] && exit 0
target=$(awk -F'\t' '{print $1}' <<< "$selected")
tmux switch-client -t "$target"
