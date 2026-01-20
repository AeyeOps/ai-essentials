AI Essentials

A public, general-purpose collection of scripts, docs, and utilities that support modern AI-based development: local tooling, cloud workflows, model evaluation, data handling, ops, and best practices. This repository is intended to be practical, lightweight, and framework-agnostic.

- Home: https://github.com/AeyeOps/ai-essentials
- Maintainer: AeyeOps Support (support@aeyeops.com)

Contents
- `packages/`: Self-contained service packages
  - `stt-service/`: GPU-accelerated Speech-to-Text with WebSocket streaming (see below)
- `scripts/`: CLI helpers and setup scripts for common environments.
  - `setup-ai-dev-stack.sh`: Comprehensive AI developer environment setup (terminal, tools, runtimes)
  - `google-chrome-wsl2.sh`: Chrome launcher optimized for WSL2 browser automation
  - `update_cli_ubuntu.sh`: Development environment setup for Ubuntu systems
- `configs/`: Pre-configured dotfiles optimized for high-performance GPU workstations.
  - `kitty/`: GPU-optimized Kitty terminal config (OLED black, 4K ready, low-latency)
  - `zellij/`: Modern Zellij theme matching Powerlevel10k classic darkest
  - `pop-shell/`: Pop Shell tiling settings and cheatsheet
  - `zsh/`: Powerlevel10k configuration
- `docs/`: Short guides, patterns, and checklists for AI dev and ops.
- `AGENTS.md`: Guidance and conventions for agentic tooling and assistants working in this repo.

Quick Start
1. Review the license and contribution guidelines.
2. Explore `scripts/` for useful automation. Run scripts with caution and review them first.
3. Browse `docs/` for task-oriented guidance and patterns.

STT Service (Speech-to-Text)
GPU-accelerated speech-to-text using NVIDIA Parakeet ONNX models. One-line install:

```bash
curl -fsSL https://raw.githubusercontent.com/AeyeOps/ai-essentials/main/packages/stt-service/install.sh | bash
```

Features:
- **Real-time transcription** via WebSocket (40-200ms latency after warmup)
- **Push-to-Talk modes**: Global hotkey (Ctrl+Super) or terminal spacebar
- **Multiple outputs**: stdout, type-to-window, clipboard
- **GPU-only execution** (CUDA/TensorRT) - fails fast if unavailable

Quick usage after install:
```bash
cd ~/stt-service
./scripts/stt-server.sh &       # Start server
./scripts/stt-client.sh --ptt   # PTT mode (hold space to record)
```

See [packages/stt-service/README.md](packages/stt-service/README.md) for full documentation.

AI Developer Environment Setup
The `scripts/setup-ai-dev-stack.sh` script provides an idempotent setup for a complete AI development environment on Linux (amd64/arm64). Components include:
- **Terminal**: Kitty (GPU-optimized for OLED/4K, low-latency settings)
- **Shell**: Zsh + Oh-My-Zsh + Powerlevel10k + MesloLGS Nerd Font
- **File Manager**: Yazi (fast, Rust-based TUI file manager with previews)
- **Multiplexer**: Zellij (modern terminal multiplexer with custom p10k theme)
- **Tiling**: Pop Shell (GNOME tiling extension with optimized settings)
- **CLI Tools**: ripgrep, fd, fzf, bat, eza, delta, glow
- **Runtimes**: NVM + Node.js 22 LTS, Mamba + Python dev environment, Bun
- **Utilities**: direnv for per-project environment variables

The script is safe to run multiple times - it detects existing installations and skips them.

Configuration Files
Pre-configured dotfiles are available in `configs/` for manual installation or reference:
- **Kitty** (`configs/kitty/kitty.conf`): True black background for OLED, 4K 2x3 grid sizing, 50k scrollback
- **Zellij** (`configs/zellij/config.kdl`): Modern theme format with semantic component names
- **Pop Shell** (`configs/pop-shell/`): Tiling settings (gaps, smart-gaps, active-hint) and keybinding cheatsheet

Browser Automation in WSL2
For developers using browser automation tools (Playwright, Puppeteer, Chrome DevTools Protocol) in WSL2 environments, the `scripts/google-chrome-wsl2.sh` script provides a reliable Chrome launcher that handles common WSL2 issues including D-Bus sessions, GPU acceleration limitations, and display server compatibility. This enables consistent browser automation testing and development workflows in WSL2.

Goals
- Keep utilities portable and dependency-light.
- Prefer clear, auditable bash and Python scripts.
- Document assumptions and side effects.
- Avoid vendor lock-in where reasonable; provide adapters.

Contributing
Contributions are welcome. Please see `CONTRIBUTING.md` and the `CODE_OF_CONDUCT.md`.

Security
- Avoid committing secrets. Use environment variables and secret managers.
- See `.gitignore` and consider adding local overrides in `.gitignore.local` (not tracked).

License
This project is licensed under the MIT License. See `LICENSE`.
