# Changelog

All notable changes to the AEO VSC CC Sessions extension will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.1] - 2026-03-25

### Added

- Expandable Rich View diagnostics showing the extracted per-process and per-session fields inline
- Session popup `Rename` action with persistent extension-owned local aliases keyed by Claude process identity

### Changed

- Removed Claude random `slug` values from the primary display-name fallback path
- Runtime plugin detection now uses `claude plugins list --json` only at startup / explicit install flows, not during ordinary runtime refreshes
- Periodic refresh scheduling now restarts its cadence after a refresh completes instead of using a wall-clock overlap interval
- Rich View rows now use improved width accounting, overlay scrolling, and slightly roomier internal spacing
- Activity text wraps again for long commands instead of clipping to a single line

### Fixed

- Restored the prompt / permission background pulse in Rich View
- Eliminated the row-padding right-click popup flicker caused by a re-render on context menu open
- Reduced false-positive stale-runtime warnings for long-running Claude tool activity
- Removed runtime reliance on Claude plugin cache-layout inspection
- Added stable per-process diagnostics fields such as `registrySessionId` for debugging session-id churn
- Fixed the selected-row tint and right-edge badge clipping regressions in narrow panels

## [0.2.0] - 2026-03-21

### Added

- Bundled Claude marketplace payload carrying the `aeo-vsc-cc-sessions-sidecar` plugin
- Python hook dispatcher writing retention-managed per-process `state.json` and `events.jsonl` under `~/.claude/aeo-vsc-cc-sessions/`
- Phase 0 validation evidence bundle under `docs/roadmap/validation/hook-sidecar/`
- Sidecar install, validate, and remove commands in the VSIX command palette

### Changed

- Session rows are now keyed by Claude process identity (`pid:start_ticks`) instead of mutable `sessionId`
- Runtime state prefers validated sidecar hook data ahead of transcript inference
- Startup grace handling adds a `starting` state while waiting for the first sidecar file
- Sidecar install automation uses the bundled marketplace path rather than a hardcoded cache layout

## [0.1.6] - 2026-03-20

### Added

- `prompt` session state detecting `AskUserQuestion`, `request_user_input`, and `ExitPlanMode` tool calls as user-input-needed signals
- Tool approval detection for mutating tools (`Edit`, `Write`, `Bash`, etc.) under default permission mode
- Prose-based approval prompt detection from trailing assistant text (e.g., "Want me to apply these changes?")
- Prompt state warm-glow animation and styling in Rich View with breathing background effect
- `--continue` cmdline detection resolving to the latest transcript in the project at launch time
- Prompt-id continuity edges linking transcripts across `/clear` and `/compact` handoffs via first/last `promptId` matching
- Transcript tail parsing (`readSuffix`) to extract `lastPromptId` from recent records
- Persistent resolved transcript ID storage in `workspaceState`, surviving extension reloads
- Resolver decision tracing with deduplicated debug logging per PID

### Changed

- Session sort order is now stable: ordered by start time and terminal position instead of state-based activity sorting
- Transcript resolver no longer depends on `statusline-activity.jsonl`; all resolution uses `/proc`, `history.jsonl`, and transcript content
- History-based handoff matching accepts candidates slightly before the event timestamp (5s pre-window) and prefers at-or-after matches
- Progress records with nested `assistant` or `user` messages are now dispatched through the main record handlers
- `permissionMode` tracked from user records to inform tool approval heuristics
- Resolution source labels are more specific: `cmdline-continue-chain`, `task-chain`, `cmdline-resume-chain`, `resolved-chain`
- `ExitPlanMode` detail shows the first plan heading instead of raw plan text

### Removed

- `sortByActivity` configuration option and state-based sort comparator
- `statusline-activity.jsonl` parsing and `StatuslineEntry` type from transcript resolver

## [0.1.5] - 2026-03-19

### Changed

- CI release script validates tag consistency against both local and remote refs before releasing
- Replace simple tag-exists check with SHA-aware guard that detects tag/HEAD mismatches and fails explicitly
- Reuse existing local tag when it already points at HEAD instead of re-creating it

## [0.1.4] - 2026-03-19

### Changed

- CI release script pushes branch before tagging so GitHub Actions workflow runs against up-to-date remote state

## [0.1.3] - 2026-03-19

### Added

- Transcript handoff tracking across `/clear`, resume flows, and related session handoffs via new `TranscriptResolver` module
- Active terminal highlighting in both TreeView (bold label) and WebviewView (font-weight 600)
- Configurable transcript detection poll interval (`aeoVscCcSessions.detectorPollInterval`)
- `--resume` cmdline parsing and task-fd resolution as separate discovery strategies
- Agent tool detail now prefers `description` or `name` fields over raw prompt text

### Changed

- Shorten sidebar panel title from "AEO VSC CC Sessions" to "AEO CC Sessions"
- State detector accepts a path-resolver function instead of a static file path, enabling live transcript switching
- Sort sessions by terminal group, then by state and recency within each group
- Recognize `end_turn` stop reason on text-only assistant records as idle transition
- Remove truncation limits on Bash command and Agent tool detail strings
- Webview status text wraps naturally instead of clipping on narrow panels

### Fixed

- Refresh view on active terminal change so highlighting updates immediately

## [0.1.2] - 2026-03-19

### Changed

- Simplify CI changelog generation by delegating file insertion to Claude instead of shell-based section splicing
- Bump version to 0.1.2

### Fixed

- Remove stray triple-backtick fence after `[0.1.1]` section in CHANGELOG.md

## [0.1.1] - 2026-03-19

### Changed

- Rename extension display name from "AEO VSC Claude Sessions" to "AEO VSC CC Sessions"
- Rewrite state detector with handler dispatch table replacing inline conditionals
- Replace timer-based idle heuristic with state derived exclusively from JSONL record content
- Switch output channel to `LogOutputChannel` with structured log levels (trace/debug/info/warn/error)
- Extract shared `formatDuration`, `getStatusText`, and `getFilteredSortedSessions` into `sessionUtils` module
- Fast-path skip `JSON.parse` for progress records (~43% of JSONL lines)
- Add re-entrant read guard preventing overlapping transcript reads
- Rename all command and configuration IDs from `claudeSessions.*` to `aeoVscCcSessions.*`
- Update `.vscodeignore` to exclude build scripts, source maps, and icon generator

### Added

- Platform detection module reporting WSL, Linux native, or Windows with `/proc` availability
- Parallel tool use detection showing count of concurrent tool calls in state detail
- `error` and `api_error` state recognition from system records

### Removed

- Manual refresh command (`aeoVscCcSessions.refresh`) — periodic refresh handles updates

## [0.1.0] - 2026-03-15

### Added

- Session discovery via ~/.claude/sessions/ PID registry files
- Real-time state detection from JSONL transcripts (idle, thinking, tool, permission, compact, exited)
- Tool detail extraction showing file names, commands, and search patterns
- Dual view modes: standard TreeView and rich HTML WebviewView with colored status indicators
- Click-to-focus terminal navigation
- Instance scoping to current VS Code window via process tree walking
- Resumed session handling via /proc/<pid>/fd/ symlink resolution
- Configurable refresh interval, sort order, and exited session visibility
- Debug logging setting for diagnostics via output channel
- Makefile with validate, package, install, ci, and clean targets
- GitHub Actions release workflow triggered by version tags
- Platform detection module for WSL, Linux native, and Windows environments
- `extensionKind: ["workspace"]` to ensure remote-side execution in WSL
- Cross-platform install script auto-detecting WSL/Linux and stable/Insiders targets
- Node.js-based profile registration replacing Python dependency
- One-time informational message when `/proc` is unavailable

### Fixed

- Wire `sortByActivity` setting to session list sorting in both TreeView and WebviewView
