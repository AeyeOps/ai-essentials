# VS Code Terminal Setup for Power Users

Configuration files that make VS Code's integrated terminal work seamlessly with terminal multiplexers and CLI tools.

## Problem Solved

VS Code intercepts many keybindings (Ctrl+B, Ctrl+P, Ctrl+R, etc.) that terminal tools need:
- **Zellij**: Mode switches (Ctrl+B/G/H/O/P/Q/T), pane navigation (Alt+H/J/K/L)
- **Claude Code**: Toggle modes (Alt+T/M/P), vim mode (Escape), history (Ctrl+R)
- **Readline (zsh/bash)**: Line editing (Ctrl+A/E/K/U/W), word nav (Alt+B/F), history (Ctrl+R/P/N)

## Files

| File | Purpose |
|------|---------|
| `vscode-terminal-settings.json` | Settings to add to your `settings.json` |
| `vscode-terminal-keybindings.json` | Complete `keybindings.json` replacement |

## Installation

### 1. Settings

Open VS Code settings JSON (`Ctrl+Shift+P` → "Preferences: Open User Settings (JSON)") and merge the contents of `vscode-terminal-settings.json`.

Key settings:
```json
"terminal.integrated.sendKeybindingsToShell": true,
"terminal.integrated.allowChords": false,
"terminal.integrated.gpuAcceleration": "on"
```

### 2. Keybindings

Open keybindings JSON (`Ctrl+Shift+P` → "Preferences: Open Keyboard Shortcuts (JSON)") and replace with contents of `vscode-terminal-keybindings.json`.

## How It Works

```
┌─────────────────────────────────────────────────────────────────┐
│  Keybinding Priority                                            │
├─────────────────────────────────────────────────────────────────┤
│  1. Unbind VS Code defaults (e.g., -workbench.action.quickOpen) │
│  2. Pass to terminal when focused (sendSequence + terminalFocus)│
│  3. Restore VS Code command outside terminal (!terminalFocus)   │
└─────────────────────────────────────────────────────────────────┘
```

Example for Ctrl+P:
1. `"-workbench.action.quickOpen"` removes VS Code's Quick Open
2. `sendSequence \u0010` sends Ctrl+P to terminal (previous history)
3. `quickOpen when !terminalFocus` restores Quick Open in editor

## Keybindings Reference

### Readline (Shell)
| Key | Action |
|-----|--------|
| Ctrl+A/E | Beginning/End of line |
| Ctrl+K/U | Kill to end/Kill line |
| Ctrl+W | Delete word backward |
| Ctrl+Y | Yank (paste) |
| Ctrl+R/S | Reverse/Forward history search |
| Ctrl+P/N | Previous/Next history |
| Alt+B/F | Word backward/forward |
| Alt+D | Delete word forward |
| Alt+. | Insert last argument |

### Zellij
| Key | Action |
|-----|--------|
| Ctrl+B | Tmux mode |
| Ctrl+G | Locked mode |
| Ctrl+H | Move mode |
| Ctrl+O | Session mode |
| Ctrl+P | Pane mode |
| Ctrl+T | Tab mode |
| Alt+H/J/K/L | Navigate panes |
| Alt+N | New pane |

### Claude Code
| Key | Action |
|-----|--------|
| Ctrl+R | Reverse search history |
| Ctrl+L | Clear screen |
| Alt+T | Toggle thinking mode |
| Alt+P | Switch model |
| Alt+M | Toggle modes |
| Escape | Vim normal mode |

## GPU Acceleration

The config enables WebGL rendering for the terminal:
```json
"terminal.integrated.gpuAcceleration": "on"
```

Verify with: `Ctrl+Shift+P` → "Terminal: Show GPU Contribution Info"

If you see rendering issues, change to `"auto"` or `"off"`.

## Font Requirements

The config expects a Nerd Font for icons (Zellij, Powerlevel10k):
```json
"terminal.integrated.fontFamily": "'JetBrainsMono Nerd Font', 'FiraCode Nerd Font', 'Hack Nerd Font', monospace"
```

Install from: https://www.nerdfonts.com/

## Troubleshooting

**Keybindings not working?**
1. Reload VS Code: `Ctrl+Shift+P` → "Developer: Reload Window"
2. Check terminal has focus (click in terminal)
3. Verify with: `Ctrl+Shift+P` → "Preferences: Open Keyboard Shortcuts" and search for the key

**GPU acceleration issues?**
- Set `"terminal.integrated.gpuAcceleration": "auto"` or `"off"`
- Check `Ctrl+Shift+P` → "GPU: Show GPU Contribution Info"

## Version

- **Version**: 1.0.0
- **Tested with**: VS Code Insiders 1.109.0, Zellij 0.40+, Claude Code
- **Platforms**: Windows (Remote SSH to Linux), Native Linux
