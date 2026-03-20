# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**AI Essentials** is a collection of production-ready tools for AI developers on Linux GPU workstations:

- **AI Developer Stack** (`scripts/setup-ai-dev-stack.sh`) - Complete terminal environment installer
- **GPU-Optimized Configs** (`configs/`) - Dotfiles for OLED/4K displays

## Build & Development Commands

```bash
# Lint shell scripts
shellcheck scripts/*.sh

# Run dev stack installer
./scripts/setup-ai-dev-stack.sh
```

## Coding Standards

### Shell Scripts
- Shebang: `#!/usr/bin/env bash`
- Safety: `set -euo pipefail`
- Indentation: 2 spaces
- Constants: UPPERCASE (e.g., `INSTALL_DIR`)
- Lint with `shellcheck`

### Commits
- Imperative mood: `fix(dev-stack): correct font path`
- Scope in parentheses when applicable
- No Co-Authored-By lines for AI

### Change Discussion Protocol
- Discuss approach with user BEFORE implementing changes
- Do not commit/push until user confirms the approach
- For multi-step changes, get approval at each decision point
- Wait for explicit "go ahead" or similar before git operations

### Before Modifying Files
- Confirm which file to modify if multiple similar files exist
- Ask before creating new files or scripts that duplicate existing functionality
- Prefer minimal changes over comprehensive rewrites

### Transparency
- Explain what you're about to change and why BEFORE making edits
- If discovering unexpected state (multiple files, existing implementations), stop and clarify

## Platform Notes

- **Target**: NVIDIA GB10 (Grace Blackwell ARM64 + Blackwell GPU) and x86_64 workstations
- **Architectures**: x86_64 (amd64) and aarch64 (arm64)
- **OS**: Ubuntu 22.04 LTS and 24.04 LTS

### WSL Troubleshooting

- Never remove packages to fix WSL-specific issues (breaks real servers)
- For broken package states: use `apt-mark hold <package>` or replace failing postinst scripts with `exit 0`
- WSL lacks systemd by default - package postinst scripts calling systemctl will fail

## Repository Learnings

### AEO VSC CC Sessions VSIX

- Project path: `/opt/aeo/ai-essentials/aeo-cc-sessions-vsix`
- Real build/install target is `make install`. There is no `make build` target in this repo.
- The extension currently has 2 real view modes only:
  - Tree View
  - Rich View (webview/HTML)
- There is no separate third “HTML TreeView” mode. Rich View is the HTML view.
- Tree View and Rich View share the same session/discovery/sort/status logic, but only Rich View can do custom row styling and animation.
- VS Code does not expose a reliable public API for reading existing terminal split/join group identity, so “joined terminal” grouping/separators cannot be implemented deterministically from the current API surface.

### Session detection and transcript lineage

- Do not rely on `~/.claude/statusline-activity.jsonl` or `statusline.sh` for correctness. It is optional and can be stale.
- The guaranteed artifact set is:
  - `/proc/<pid>/cmdline`
  - `/proc/<pid>/fd`
  - `~/.claude/sessions/<pid>.json`
  - `~/.claude/projects/<encoded-cwd>/*.jsonl`
  - `~/.claude/history.jsonl`
- Resolver anchor order should be:
  - persisted last resolved transcript id for that VS Code session row
  - active task UUID from `/proc/<pid>/fd`
  - `--resume <uuid>` from cmdline
  - `--continue` as “latest transcript in project at process start”
  - registry session id from `~/.claude/sessions/<pid>.json`
- Never use “latest transcript in project” as a general rule. Only use it when the process actually launched with `--continue`, otherwise multiple live terminals in the same project collapse together incorrectly.
- Transcript lineage is strongest when any of these are present:
  - transcript `SessionStart:*` metadata (`clear`, `compact`, `resume`)
  - explicit previous transcript path/id in transcript content
  - first/last `promptId` continuity across transcript rotations
  - `/clear` or `/compact` events in `history.jsonl`
- `history.jsonl` gives source session id, project, command text, and timestamp for a handoff, but not the destination session id directly.
- For history-based handoffs, match transcript candidates by:
  - same project
  - matching handoff kind (`/clear` -> `SessionStart:clear`, `/compact` -> `SessionStart:compact`)
  - closest transcript start timestamp to the history event, preferring candidates at or just after the event
- `/clear` descendants may be nearly empty. Prompt-id continuity is important to chain them when history timing alone is ambiguous.
- Persist the last resolved transcript id per session row across extension reloads. Otherwise reloads force cold re-correlation and make ambiguous projects regress.

### Prompt-state detection

- Structured prompt states should be treated as `prompt`:
  - `AskUserQuestion`
  - `request_user_input`
  - `ExitPlanMode`
- `ExitPlanMode` is the important structured signal for plan approval / implementation approval style prompts.
- Plain assistant prose that ends in a question should not be treated as a prompt state by default. This caused false positives such as “Want me to start executing tasks 7-8-11...?” which is still just an idle end-turn response.
- For `ExitPlanMode`, showing the first plan heading as the prompt detail is a good status summary.

### Session list behavior

- Resorting rows on live state changes is disruptive and can desync click/focus behavior from terminal identity.
- Keep ordering stable across runtime state changes. Prefer terminal position, then session start time, then session id.
- Do not use state-based ordering for active detection lists.

### UI behavior

- Prompt rows use the bright warm animated treatment.
- Tree View cannot match Rich View visual parity for arbitrary row backgrounds, separators, or animation because of VS Code TreeView limitations.
- The project label row should come from the project path basename, not a transcript slug.

### CI and release pipeline

- `make ci-patch` may legitimately take several minutes because the changelog generation step can be slow.
- `make ci` must push the branch commit before pushing the release tag. Pushing only the tag can leave GitHub without the workflow-bearing commit on `main`, which prevents automated release creation.
- For this repo, successful automated release flow is:
  - branch commit pushed
  - tag pushed
  - GitHub Actions `Release VSIX` runs
  - release and VSIX asset are published automatically
