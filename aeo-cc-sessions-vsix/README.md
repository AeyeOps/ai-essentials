# AEO VSC CC Sessions

Real-time state monitoring for Claude Code terminal sessions in VS Code.

## Features

- **Session Discovery** — Automatically detects all running Claude Code sessions in the current VS Code window
- **Transcript Handoff Tracking** — Follows Claude transcript rotation across `/clear`, resume flows, and related session handoffs so state stays attached to the active transcript
- **Real-Time State** — Shows live session state: idle, thinking, tool use, waiting for permission, compacting, or exited
- **Tool Details** — Displays which tool is running and what it's operating on (file name, command, search pattern, agent task description)
- **Click to Focus** — Click any session to jump to its terminal
- **Rich View Labels** — Multi-line Rich View rows show session name, compacted path, short session id, session age, and current activity with active-terminal highlighting
- **Expandable Diagnostics** — Expand any row to inspect the extracted per-process/session fields without leaving the panel
- **Local Aliases** — Rename a live row entry in the popup menu with an extension-owned alias that persists for that process lifetime
- **Rich View Actions** — Right-click a session for actions, or right-click blank space in Rich View to start a new Claude session in the loaded workspace folder
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
- `aeoVscCcSessions.showExited` — Show exited sessions in the list (default: `false`)

## Requirements

- VS Code 1.110.0 or later
- Claude Code running in VS Code terminal sessions
- The `aeo-vsc-cc-sessions-sidecar` Claude plugin installed and enabled for authoritative hook state

### Sidecar runtime mode

High-fidelity lineage and prompt detection now depend on the `aeo-vsc-cc-sessions-sidecar` plugin from the `aeo-skill-marketplace` Claude marketplace. The VSIX install command first adds the marketplace from `https://github.com/AeyeOps/aeo-skill-marketplace.git`, then installs or updates the plugin. The VSIX exposes commands to:

- install or update the sidecar plugin
- validate sidecar health for the current machine and live sessions
- remove or disable the sidecar plugin cleanly

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

## View

The Sessions panel uses the Rich View interface with multi-line rows, active-terminal grouping, and inline sort controls for `None`, `Name`, and `State`.

## Rich View context menu

- Right-click a session row in Rich View to open session actions.
- Right-click a session row to rename that live entry with a local alias.
- Right-click blank space in Rich View to open `New Session`, which launches `claude --debug --verbose` in the loaded workspace folder.

## License

MIT
