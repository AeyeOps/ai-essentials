# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**AI Essentials** is a monorepo providing production-ready tools for AI developers on Linux GPU workstations:

- **AEO Push-to-Talk** (`packages/stt-service/`) - GPU-accelerated speech-to-text with system-wide hotkey support
- **AI Developer Stack** (`scripts/setup-ai-dev-stack.sh`) - Complete terminal environment installer
- **GPU-Optimized Configs** (`configs/`) - Dotfiles for OLED/4K displays

## Build & Development Commands

```bash
# Install all workspace dependencies
uv sync

# Install STT service with dev and optional dependencies
uv sync --package stt-service --all-extras

# Run tests (pytest with asyncio_mode=auto)
cd packages/stt-service && pytest tests/

# Lint shell scripts
shellcheck scripts/*.sh packages/stt-service/scripts/*.sh

# Run STT server (requires GPU)
packages/stt-service/scripts/stt-server.sh

# Run STT client in PTT mode (separate terminal)
packages/stt-service/scripts/stt-client.sh --ptt

# Test in Docker sandbox with GPU passthrough
packages/stt-service/scripts/test-sandbox.sh
```

## Architecture

### Monorepo Structure
- `uv` workspace with Python 3.12.3+
- Root `pyproject.toml` defines workspace, packages in `packages/*`
- Build backend: hatchling

### STT Service Components (`packages/stt-service/src/stt_service/`)

| Module | Purpose |
|--------|---------|
| `server.py` | WebSocket server, session management, model inference |
| `client.py` | WebSocket PTT client, audio streaming, output modes |
| `ptt.py` | Push-to-Talk state machine (IDLE→RECORDING→PROCESSING), hotkey listeners |
| `transcriber.py` | ONNX-asr wrapper with Parakeet TDT model, GPU-only (CUDA/TensorRT) |
| `config.py` | Pydantic-settings configuration (all via env vars) |
| `protocol.py` | WebSocket message protocol (Pydantic models) |
| `tray.py` | System tray indicator (pystray) with state colors |

### Communication Flow
```
PTT Client → WebSocket → STT Server
  ↓ Config (sample_rate)       ↑
  ↓ Binary PCM chunks          ↑
  ↓ "end" message              ↑ "ready" (session_id)
                               ↑ "final" (text, confidence)
```

### Key Design Decisions

1. **GPU-only, fail-fast**: `GPUNotAvailableError` if CUDA unavailable (no CPU fallback)
2. **Environment-driven config**: All settings via pydantic-settings + env vars (prefix: `STT_`)
3. **Wrapper scripts**: CUDA 12 library path handling abstracted into shell wrappers
4. **Dual hotkey listeners**: `EvdevHotkeyListener` (global X11) vs `TerminalHotkeyListener` (Docker/SSH)
5. **Idempotent installation**: Installer safe to re-run; checks existing state before modifications

## Key Environment Variables

```bash
# Server
STT_SERVER_HOST=127.0.0.1
STT_SERVER_PORT=9876
STT_MODEL_PROVIDER=cuda  # cuda or tensorrt

# Client
STT_CLIENT_OUTPUT_MODE=stdout  # stdout, type, clipboard
STT_PTT_HOTKEY='["LEFTCTRL", "LEFTMETA"]'  # Ctrl+Super
STT_PTT_TERMINAL_HOTKEY=' '  # Spacebar for Docker/SSH
```

## Coding Standards

### Shell Scripts
- Shebang: `#!/usr/bin/env bash`
- Safety: `set -euo pipefail`
- Indentation: 2 spaces
- Constants: UPPERCASE (e.g., `INSTALL_DIR`)
- Lint with `shellcheck`

### Python
- Type hints required
- Pydantic for data models and configuration
- asyncio for concurrency

### Commits
- Imperative mood: `fix(stt-service): correct model path`
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
- **ARM64 GPU**: Requires manual onnxruntime-gpu wheel (no PyPI wheels for aarch64)
- **CUDA**: Wrapper scripts search for CUDA 12.x libraries in standard paths

### WSL Troubleshooting

- Never remove packages to fix WSL-specific issues (breaks real servers)
- For broken package states: use `apt-mark hold <package>` or replace failing postinst scripts with `exit 0`
- WSL lacks systemd by default - package postinst scripts calling systemctl will fail

## Testing Philosophy

- Test actual functionality, not superficial checks (e.g., test audio capture, not just server connectivity)
- Docker sandbox (`test-sandbox.sh`) tests the real curl installer path
- Use spacebar (terminal hotkey) instead of Ctrl+Super when testing in containers

## Installer Design

- Interactive prompts over environment variables for user choices
- Same curl command for all install modes - user picks options when prompted
- Env vars acceptable only for CI/automation (`STT_NONINTERACTIVE=1`), not for feature selection
