#!/bin/bash
# Spawn a new terminal tab attached to a tmux session.
# Usage: terminal-tab.sh <session-name>
# Detects host terminal (Windows Terminal, Kitty) and dispatches accordingly.

session="${1:?Usage: terminal-tab.sh <session-name>}"

_tab_wt() {
    local distro
    distro=$(tmux show-environment -g WSL_DISTRO_NAME 2>/dev/null | cut -d= -f2)
    [ -z "$distro" ] && distro="$WSL_DISTRO_NAME"
    wt.exe -w 0 nt -- wsl.exe -d "$distro" -- tmux attach-session -t "$session"
}

_tab_kitty() {
    kitten @ launch --type=tab --title "$session" bash -c "tmux attach-session -t '$session'" 2>/dev/null \
        || kitty --title "$session" bash -c "tmux attach-session -t '$session'" &
}

# Detect terminal from tmux's global environment
wt_val=$(tmux show-environment -g WT_SESSION 2>/dev/null | cut -d= -f2)
kitty_val=$(tmux show-environment -g KITTY_WINDOW_ID 2>/dev/null | cut -d= -f2)

if [ -n "$wt_val" ]; then
    _tab_wt
elif [ -n "$kitty_val" ]; then
    _tab_kitty
else
    tmux display-message "No tab handler for this terminal"
fi
