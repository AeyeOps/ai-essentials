#!/bin/bash
if [ "${1:-}" = "__fn" ]; then
    _break_to_window() {
        local pane_count
        pane_count=$(tmux display-message -p '#{window_panes}')
        if [ "$pane_count" -eq 1 ]; then
            tmux display-message "Only one pane in window"
            return
        fi
        tmux break-pane
    }

    _break_to_session() {
        local pane_count
        pane_count=$(tmux display-message -p '#{window_panes}')
        if [ "$pane_count" -eq 1 ]; then
            tmux display-message "Only one pane in window"
            return
        fi
        local target new_s
        target=$(tmux break-pane -dP -F '#{session_name}:#{window_index}')
        new_s=$(tmux new-session -dP -F '#{session_name}')
        tmux move-window -s "$target" -t "$new_s"
        tmux kill-window -t "${new_s}:1" 2>/dev/null
        tmux switch-client -t "$new_s"
    }

    _window_to_session() {
        local src_window new_s
        src_window=$(tmux display-message -p '#{session_name}:#{window_index}')
        new_s=$(tmux new-session -dP -F '#{session_name}')
        tmux move-window -s "$src_window" -t "$new_s"
        tmux kill-window -t "${new_s}:1" 2>/dev/null
        tmux switch-client -t "$new_s"
    }

    return 0 2>/dev/null || exit 0
fi
stty -ixon 2>/dev/null
current="$(tmux display-message -p '#{session_name}:#{window_index}.#{pane_index}')"

# ANSI dim for detached rows
dim=$'\033[38;2;88;91;112m'
rst=$'\033[0m'

list=$(tmux list-panes -a -F \
  "#{session_name}:#{window_index}.#{pane_index}|#{window_name}|#{pane_title}|#{pane_current_command}|#{?session_attached,attached,detached}" |
awk -F'|' -v cur="$current" -v dim="$dim" -v rst="$rst" '
{
    n = NR
    m[n] = (cur == $1) ? "*" : " "
    t[n] = $1; w[n] = $2; ti[n] = $3; c[n] = $4; s[n] = $5
    if (length($1) > wt) wt = length($1)
    if (length($2) > ww) ww = length($2)
    if (length($3) > wti) wti = length($3)
    if (length($4) > wc) wc = length($4)
    if (length($5) > ws) ws = length($5)
}
END {
    if (4 > wt) wt = 4; if (4 > ww) ww = 4; if (5 > wti) wti = 5
    if (7 > wc) wc = 7; if (6 > ws) ws = 6
    fmt = " %1s  %-" wt "s  %-" ww "s  %-" wti "s  %-" wc "s  %-" ws "s"
    hdr = sprintf(fmt, "", "S:W.P", "Name", "Title", "Command", "Status")
    printf "HEADER:%s\n", hdr
    for (i = 1; i <= n; i++) {
        display = sprintf(fmt, m[i], t[i], w[i], ti[i], c[i], s[i])
        if (s[i] == "detached")
            printf "%s%s%s\t%s\n", dim, display, rst, t[i]
        else
            printf "%s\t%s\n", display, t[i]
    }
}')

header="${list%%$'\n'*}"
header="${header#HEADER:}"
data="${list#*$'\n'}"

# Legend bar — bg-safe ANSI (no mid-line resets so background persists)
bg=$'\033[48;2;49;50;68m'        # surface0 #313244
hi=$'\033[1;38;2;137;180;250m'   # bold #89b4fa (fg only)
lo=$'\033[22;38;2;108;112;134m'  # #6c7086 (fg only, unbold)
bar=$'\033[22;38;2;69;71;90m'    # #45475a (fg only)
hi2=$'\033[1;38;2;250;179;135m'  # bold #fab387 (peach)
r=$'\033[0m'
pad=$(printf '%80s' '')

legend="${bg}  ${hi}Enter ${lo}jump       ${bar}│  ${hi}C-o ${lo}bring pane   ${bar}│  ${hi}C-s ${lo}send pane    ${bar}│  ${hi}C-g ${lo}bring win    ${bar}│  ${hi}C-x ${lo}swap${pad}${r}"
legend2="${bg}  ${hi2}C-t ${lo}new win      ${bar}│  ${hi2}C-y ${lo}new session   ${bar}│  ${hi2}C-r ${lo}win→session${pad}${r}"

result=$(printf '%s\n' "$data" | \
fzf --no-sort --ansi \
    --delimiter='\t' \
    --with-nth=1 \
    --header="
$legend
$legend2

$header" \
    --prompt="Nav > " \
    --pointer="▶" \
    --layout=reverse \
    --expect=ctrl-o,ctrl-s,ctrl-g,ctrl-x \
    --bind "ctrl-t:execute-silent(bash -c '. ~/.config/tmux/scripts/navigator.sh __fn && _break_to_window')+abort" \
    --bind "ctrl-y:execute-silent(bash -c '. ~/.config/tmux/scripts/navigator.sh __fn && _break_to_session')+abort" \
    --bind "ctrl-r:execute-silent(bash -c '. ~/.config/tmux/scripts/navigator.sh __fn && _window_to_session')+abort")

[ -z "$result" ] && exit 0

key=$(head -1 <<< "$result")
selected=$(sed -n '2p' <<< "$result" | cut -f2)
[ -z "$selected" ] && exit 0

# Guard: no-op if targeting current pane (except jump)
if [ "$key" != "" ] && [ "$selected" = "$current" ]; then
    tmux display-message "Already here"
    exit 0
fi

# Parse current and target components
current_session="${current%%:*}"
current_winpane="${current#*:}"
current_window="${current_winpane%%.*}"
current_sw="${current_session}:${current_window}"

target_session="${selected%%:*}"
target_winpane="${selected#*:}"
target_window="${target_winpane%%.*}"
target_sw="${target_session}:${target_window}"

# Guard: block send/swap to detached sessions
if [ "$key" = "ctrl-s" ] || [ "$key" = "ctrl-x" ]; then
    status=$(tmux display-message -t "$target_session" -p '#{?session_attached,attached,detached}' 2>/dev/null)
    if [ "$status" = "detached" ]; then
        tmux display-message "Target is detached"
        exit 0
    fi
fi

# Guard: no-op actions that would change nothing
case "$key" in
    ctrl-o)
        if [ "$target_sw" = "$current_sw" ]; then
            tmux display-message "Pane already in this window"
            exit 0
        fi
        tmux join-pane -s "$selected" ;;
    ctrl-s)
        if [ "$target_sw" = "$current_sw" ]; then
            tmux display-message "Already in that window"
            exit 0
        fi
        tmux join-pane -t "$target_sw" ;;
    ctrl-g)
        if [ "$target_session" = "$current_session" ]; then
            tmux display-message "Window already in this session"
            exit 0
        fi
        tmux move-window -s "$target_sw" ;;
    ctrl-x) tmux swap-pane -t "$selected" ;;
    *)      tmux switch-client -t "$selected" ;;
esac
