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
