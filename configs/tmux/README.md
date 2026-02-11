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
| `J` | Interactive menu to join a pane from another window or break to new window |
| `M` | Merge all detached sessions into current session |
| `r` | Reload config |

### 3-Row Status Bar

A built-in keyboard reference across three color-coded rows:

- **Row 1 (blue)** - Window operations + live window list (right-aligned, active window highlighted)
- **Row 2 (green)** - Pane operations and layout controls
- **Row 3 (pink)** - Session management with prefix indicator

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

### `scripts/join-pane-menu.sh`

Interactive `display-menu` triggered by `Prefix + J`. Presents a list of windows (excluding the current one) to pull a pane from, plus a "New window" option that breaks the current pane out via `break-pane`.

## Requirements

- tmux 3.2+ (for `status-format`, `display-menu`, `allow-passthrough`)
- A terminal with true color and OSC 52 clipboard support (e.g., Windows Terminal, Kitty, iTerm2)
