# tmux Configuration

Opinionated tmux configuration optimized for AI-assisted development workflows (Claude Code, Vim, terminal multiplexing).

## Features

- **Prefix**: `Ctrl+Space` (avoids conflict with Claude Code's `Ctrl+b`)
- **Zero escape-time**: No input lag for Vim/terminal apps
- **True color**: 256-color with RGB terminal features
- **Vi copy mode**: `v` to select, `y` to yank via OSC 52 clipboard
- **Mouse support**: Click, scroll, resize with 50k line scrollback
- **Catppuccin Mocha** color scheme throughout

### Custom Keybindings

| Key | Action |
|-----|--------|
| `\|` / `-` | Split panes (horizontal/vertical) in current directory |
| `T` | Set pane title |
| `Tab` | Navigator popup — fzf-powered view/jump/move for all panes across sessions |
| `M` | Merge all detached sessions into current session |
| `r` | Reload config |

### 3-Row Status Bar

A built-in keyboard reference across three color-coded rows:

- **Row 1 (blue)** - Window operations + live window list (right-aligned, active window highlighted)
- **Row 2 (green)** - Pane operations and layout controls
- **Row 3 (pink)** - Session management with prefix indicator, current `session:window.pane`, and pane title

### Pane Borders

Each pane displays a top border with window index, pane index, window name, pane title, and current command.

## Installation

```bash
# Copy the config
cp configs/tmux/tmux.conf ~/.tmux.conf

# Install the helper scripts
mkdir -p ~/.config/tmux/scripts
cp configs/tmux/scripts/*.sh ~/.config/tmux/scripts/
chmod +x ~/.config/tmux/scripts/*.sh

# Reload (from inside tmux)
tmux source-file ~/.tmux.conf
```

## Scripts

### `scripts/navigator.sh`

Fzf-powered navigator popup triggered by `Prefix + Tab`. Lists every pane across all sessions with auto-sized columns: target (`session:window.pane`), window name, pane title, current command, and attach status. The current pane is marked with `*`.

Action keys (shown in fzf header):

| Key | Action | tmux command |
|-----|--------|-------------|
| `Enter` | Jump to selected pane | `switch-client -t S:W.P` |
| `Ctrl-O` | Bring selected pane into current window | `join-pane -s S:W.P` |
| `Ctrl-S` | Send current pane to selected pane's window | `join-pane -t S:W` |
| `Ctrl-G` | Bring selected window into current session | `move-window -s S:W` |
| `Ctrl-X` | Swap current pane with selected pane | `swap-pane -t S:W.P` |

**Create actions** (peach legend bar):

| Key | Action | Notes |
|-----|--------|-------|
| `Ctrl-T` | Break current pane to new window | Single-pane guard: shows "Only one pane in window" if only one pane exists |
| `Ctrl-Y` | Break current pane to new session | Single-pane guard; creates new session in a new terminal tab |
| `Ctrl-R` | Move current window to new session | Captures source window explicitly before move; opens new terminal tab |

Selecting the current pane (`*`) with any action key (except Enter) shows "Already here".

### `scripts/terminal-tab.sh`

Spawns a new terminal tab attached to a given tmux session. Used by navigator's `C-y` and `C-r` to open the newly created session in a separate tab instead of switching the current client away.

```
terminal-tab.sh <session-name>
```

**Supported terminals:**

| Terminal | Detection | Method |
|----------|-----------|--------|
| Windows Terminal (WSL) | `WT_SESSION` in tmux env | `wt.exe -w 0 nt` with correct WSL distro |
| Kitty | `KITTY_WINDOW_ID` in tmux env | `kitten @ launch --type=tab` (requires `allow_remote_control socket-only` in kitty.conf), falls back to new kitty instance |

Terminal detection uses `tmux show-environment -g` to read variables reliably from fzf subshells. Unsupported terminals get a `tmux display-message` fallback.

## Requirements

- tmux 3.2+ (for `status-format`, `display-menu`, `display-popup`, `allow-passthrough`)
- `fzf` (for the navigator popup)
- A terminal with true color and OSC 52 clipboard support (e.g., Windows Terminal, Kitty, iTerm2)
