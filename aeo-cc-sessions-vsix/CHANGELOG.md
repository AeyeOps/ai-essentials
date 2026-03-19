# Changelog

All notable changes to the AEO VSC CC Sessions extension will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
