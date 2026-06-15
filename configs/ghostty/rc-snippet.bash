# AEO Ghostty launcher — bash rc blocks. The installer inserts each marker-fenced
# block separately: the GUARD near the top of ~/.bashrc, and the INTEGRATION block
# at the very end. @FZF_PATH@ is replaced with the resolved fzf>=0.45 absolute
# path at install time.

# >>> aeo ghostty session launcher (guard) >>>
_gt_launcher="${XDG_CONFIG_HOME:-$HOME/.config}/ghostty/ghostty-tmux-launch"
# Pin the launcher's fzf: the guard runs before the rc's own PATH edits, and apt's
# fzf 0.44.1 (no `transform` action) would shadow a newer one on PATH.
export GT_FZF="@FZF_PATH@"
if [[ $- == *i* && -z "${TMUX:-}" && -n "${GHOSTTY_RESOURCES_DIR:-}" \
      && -z "${GHOSTTY_QUICK_TERMINAL:-}" && -x "$_gt_launcher" ]]; then
  exec "$_gt_launcher"
fi
unset _gt_launcher
# <<< aeo ghostty session launcher (guard) <<<

# >>> aeo ghostty shell integration >>>
# Ghostty auto-injects integration only into directly-spawned shells, not tmux
# panes — source it so cwd/title reporting works inside tmux too.
if [[ -n "${GHOSTTY_RESOURCES_DIR:-}" ]]; then
  builtin source "$GHOSTTY_RESOURCES_DIR/shell-integration/bash/ghostty.bash"
fi
# <<< aeo ghostty shell integration <<<
