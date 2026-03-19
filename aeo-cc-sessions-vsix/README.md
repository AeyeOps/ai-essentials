# AEO VSC CC Sessions

Real-time state monitoring for Claude Code terminal sessions in VS Code.

## Features

- **Session Discovery** — Automatically detects all running Claude Code sessions in the current VS Code window
- **Real-Time State** — Shows live session state: idle, thinking, tool use, waiting for permission, compacting, or exited
- **Tool Details** — Displays which tool is running and what it's operating on (file name, command, search pattern)
- **Dual View Modes** — Switch between a standard TreeView and a rich HTML view with colored status dots and borders
- **Click to Focus** — Click any session to jump to its terminal
- **Instance Scoping** — Only shows sessions belonging to the current VS Code window, not other windows or tmux sessions

## Session States

| State | Description |
|-------|-------------|
| Idle | Session is waiting for input |
| Thinking | Claude is generating a response |
| Tool | A tool is executing (Read, Edit, Bash, Agent, etc.) |
| Permission | Waiting for user to approve a tool call |
| Compacting | Context window is being compacted |
| Exited | Session process has terminated |

## Settings

- `aeoVscCcSessions.refreshInterval` — Refresh interval in milliseconds (default: `3000`)
- `aeoVscCcSessions.sortByActivity` — Sort active sessions before idle ones (default: `true`)
- `aeoVscCcSessions.showExited` — Show exited sessions in the list (default: `false`)
- `aeoVscCcSessions.debug` — Enable diagnostic logging to the AEO VSC CC Sessions output channel (default: `false`)

## Requirements

- VS Code 1.110.0 or later
- Claude Code running in VS Code terminal sessions

### Supported Environments

- **WSL Remote** (stable + Insiders) — VS Code on Windows connecting to WSL. Full functionality via `/proc` filesystem.
- **Linux native** (stable + Insiders) — VS Code running directly on Linux. Full functionality via `/proc` filesystem.
- **Windows native** — Graceful degradation. Session detection requires `/proc` and is not available on native Windows. An informational message is shown on first activation.

## View Toggle

Use the toolbar icons in the AEO VSC CC Sessions panel header to switch between:
- **Tree View** — Standard VS Code tree with colored circle icons
- **Rich View** — HTML view with two-line rows, colored left borders, pulsing dots for thinking state

## License

MIT
