#!/bin/bash
# Count claude panes across tmux; emit " 🔵 running/total " or " ⚫ 0/total ".
# Designed for tmux status-right at 5s interval. Silent when no claude panes.
#
# Detection:
#   - "claude pane" = pane_current_command matches X.Y.Z (claude process title)
#     or contains "claude"
#   - "running" = host has at least one `caffeinate` process (claude spawns it
#     during active turns and kills it when idle). Capped to total.
set -eu

panes=$(tmux list-panes -a -F '#{pane_current_command}' 2>/dev/null) || exit 0
total=$(printf '%s\n' "$panes" | awk '/^[0-9]+\.[0-9]+\.[0-9]+$/ || /claude/' | wc -l | tr -d ' ')
[[ $total -eq 0 ]] && exit 0

running=$(pgrep -x caffeinate 2>/dev/null | wc -l | tr -d ' ')
[[ $running -gt $total ]] && running=$total

if [[ $running -gt 0 ]]; then
  printf ' 🔵 %d/%d ' "$running" "$total"
else
  printf ' ⚫ 0/%d ' "$total"
fi
