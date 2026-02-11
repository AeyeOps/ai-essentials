#!/bin/bash
# Join pane menu: presents a list of windows (excluding current) to pull a pane from,
# plus a "New window" option that breaks the current pane into its own window.

current_win=$(tmux display-message -p "#{window_index}")
current_pane=$(tmux display-message -p "#{pane_id}")
args=("» New window (break pane)" "n" "break-pane" "" "" "")

while IFS= read -r line; do
    idx="${line%%:*}"
    name="${line#*:}"
    args+=("${idx}:${name}" "${idx}" "join-pane -s ${idx} -t ${current_pane}")
done < <(tmux list-windows -F "#{window_index}:#{window_name}" | grep -v "^${current_win}:")

tmux display-menu -T "Join pane from:" "${args[@]}"
