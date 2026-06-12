#!/bin/bash
set -euo pipefail

target_pane="${1:?Usage: merge-panes.sh <target-pane-id> <target-window-id> <target-session-id>}"
target_window="${2:?Usage: merge-panes.sh <target-pane-id> <target-window-id> <target-session-id>}"
target_session="${3:?Usage: merge-panes.sh <target-pane-id> <target-window-id> <target-session-id>}"

moved=0

for session in $(tmux list-sessions -F '#{session_id}' -f '#{?session_attached,,1}'); do
    [ "$session" = "$target_session" ] && continue

    for pane in $(tmux list-panes -s -t "$session" -F '#{pane_id}'); do
        tmux join-pane -d -s "$pane" -t "$target_pane"
        moved=$((moved + 1))
        tmux select-layout -t "$target_window" tiled >/dev/null
    done
done

tmux select-pane -t "$target_pane"
tmux display-message "merge-panes: moved $moved pane(s) into current window"
