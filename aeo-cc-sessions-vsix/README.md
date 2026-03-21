# AEO VSC CC Sessions

Real-time state monitoring for Claude Code terminal sessions in VS Code.

## Features

- **Session Discovery** — Automatically detects all running Claude Code sessions in the current VS Code window
- **Transcript Handoff Tracking** — Follows Claude transcript rotation across `/clear`, resume flows, and related session handoffs so state stays attached to the active transcript
- **Real-Time State** — Shows live session state: idle, thinking, tool use, waiting for permission, compacting, or exited
- **Tool Details** — Displays which tool is running and what it's operating on (file name, command, search pattern, agent task description)
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
- `aeoVscCcSessions.detectorPollInterval` — Transcript detection poll interval in milliseconds (default: `2000`)
- `aeoVscCcSessions.sortByActivity` — Sort active sessions before idle ones (default: `true`)
- `aeoVscCcSessions.showExited` — Show exited sessions in the list (default: `false`)
- `aeoVscCcSessions.debug` — Enable diagnostic logging to the AEO VSC CC Sessions output channel (default: `false`)

## Requirements

- VS Code 1.110.0 or later
- Claude Code running in VS Code terminal sessions

### Planned Enhanced Lineage Mode

For the planned high-fidelity lineage and prompt-detection mode, this extension will require the dedicated Claude Code sidecar plugin to be installed and enabled so its hooks can emit authoritative per-session state.

Plugin and skill installation guidance should follow the official Claude Code documentation:
- Plugins: https://docs.claude.com/en/docs/claude-code/plugins
- Skills: https://docs.claude.com/en/docs/claude-code/skills

The sidecar JSONL output must be retention-managed so it does not grow without bound. The current roadmap target is:
- per-process `state.json` retained only while active plus a short post-exit window
- per-process `events.jsonl` pruned on age and capped in size

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
