# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.0.16] - 2026-01-25

### Removed
- Claude Code ultrareview commands (moved to user profile)
  - `claude-code/` directory with ultrareview plugin
  - `commands/` directory with ultrareview*.md slash commands
  - `hooks/` directory with ultrareview-loop scripts
- AEO Push-to-Talk / STT Service (migrated to separate repo)
  - `packages/stt-service/` moved to `aeo-ptt-tts` repository
  - `docs/stt-model-options.md` and `docs/stt-ptt-setup.md` moved
  - `scripts/whisper-ptt.sh` moved
  - See https://github.com/AeyeOps/aeo-ptt-tts for continued development

## [0.0.15] - 2026-01-24

### Added
- Additional CLI tools to dev stack (`scripts/setup-ai-dev-stack.sh`)
  - btop: Beautiful system monitor (replaces htop)
  - ncdu: Interactive disk usage analyzer
  - duf: Modern df replacement with visual output
  - httpie: Human-friendly curl alternative
  - yq: YAML processor (like jq for YAML)
  - shellcheck: Shell script linter
  - p7zip: 7z archive support
  - Shell aliases: `disk` (ncdu), `df` (duf), `top` (btop), `yaml` (yq)

## [0.0.14] - 2026-01-24

### Added
- Terminal media tools to dev stack (`scripts/setup-ai-dev-stack.sh`)
  - ffmpeg for video processing, format conversion, and ffprobe inspection
  - mpv with Kitty graphics protocol support (`--vo=kitty`) for terminal video playback
  - chafa for terminal image and animated GIF rendering with auto-detected protocol support
  - Shell alias: `mpvk` for convenient Kitty-native video playback with optimized flags
- Post-install configuration for dev stack
  - Set Kitty as default terminal on GNOME (update-alternatives priority 50 + gsettings)
  - Configure git delta as default pager with navigate and dark mode
  - fzf Zsh keybindings (Ctrl+T, Ctrl+R, Alt+C) and fuzzy completion

### Fixed
- setup-ai-dev-stack.sh: chsh now uses sudo and handles failure gracefully
- setup-ai-dev-stack.sh: plugins sed is more robust (appends to any existing plugins)
- setup-ai-dev-stack.sh: XDG_CURRENT_DESKTOP uses default empty value for WSL/headless

### Changed
- CLAUDE.md: Updated platform notes with explicit x86_64/aarch64 and Ubuntu 22/24 support
- CLAUDE.md: Added WSL troubleshooting guidance

## [0.0.10] - 2026-01-19

### Added
- Glow markdown renderer to dev stack (`scripts/setup-ai-dev-stack.sh`)
  - Terminal-based markdown rendering with syntax highlighting
  - ARM64 architecture support (handles glow's `arm64` naming convention)
  - Alias: `mdv` for quick markdown viewing

## [0.0.9] - 2026-01-18

### Added
- Pop Shell GNOME tiling extension to setup script
  - Auto-installs from source on GNOME desktops
  - Optimized settings: 4px gaps, active-hint, smart-gaps, hidden titles
  - Cheatsheet included (`configs/pop-shell/pop-shell-cheatsheet.txt`)
- Configuration files directory (`configs/`)
  - `configs/kitty/kitty.conf` - GPU-optimized Kitty terminal config
  - `configs/zellij/config.kdl` - Modern Zellij theme matching p10k
  - `configs/pop-shell/` - Pop Shell settings and cheatsheet

### Changed
- Enhanced Kitty terminal configuration for high-performance GPU systems
  - OLED-optimized true black background (#000000)
  - 4K display support with 2x3 grid window sizing
  - Low-latency GPU settings (repaint_delay 5ms, input_delay 1ms)
  - 50k scrollback lines, shell integration enabled
- Zellij theme converted to modern format with semantic component names
  - Explicit control over ribbons, frames, tables, lists
  - Color palette matching Powerlevel10k classic darkest (234)

## [0.0.8] - 2026-01-10

### Added
- AI Developer Stack setup script (`scripts/setup-ai-dev-stack.sh`) for complete development environment
  - Idempotent installation - safe to run multiple times
  - Multi-architecture support (amd64/arm64)
  - Terminal: Kitty with auto-copy on select and right-click paste
  - Shell: Zsh + Oh-My-Zsh + Powerlevel10k + MesloLGS Nerd Font
  - Plugins: zsh-autosuggestions, zsh-syntax-highlighting
  - File Manager: Yazi (Rust-based TUI with previews)
  - Multiplexer: Zellij
  - CLI Tools: ripgrep, fd, fzf, bat, eza, delta
  - Runtimes: NVM + Node.js 22 LTS, Mamba + Python dev environment, Bun
  - Utilities: direnv for per-project environment variables

## [0.0.7] - 2026-01-09

### Changed
- Replaced AWS Q CLI with Kiro CLI in update script
  - Updated deb package URL from amazon-q.deb to kiro-cli.deb
  - Renamed all Q_* variables to KIRO_* equivalents
  - Updated command detection from 'q' to 'kiro-cli'
  - Updated all user-facing messages to reference Kiro CLI

## [0.0.6] - 2025-10-09

### Added
- Windows Chrome launcher script (`scripts/chrome-wsl2-win.sh`) for WSL2-to-Windows browser automation
  - Launches Chrome on Windows host from WSL2 environment
  - Complements the Linux-native WSL2 Chrome launcher

## [0.0.5] - 2025-09-28

### Added
- Chrome WSL2 launcher script (`scripts/google-chrome-wsl2.sh`) for reliable browser automation in WSL2 environments
  - Addresses common D-Bus session management issues in WSL2
  - Automatic display platform detection (X11, Wayland, headless)
  - Optimized Chrome flags for WSL2 compatibility
  - GPU acceleration workarounds for WSL2 limitations
  - Support for browser automation tools (Playwright, Puppeteer, DevTools Protocol)

## [0.0.4] - 2025-09-25

### Changed
- Revised agent guide documentation for improved clarity
- Further hardened CLI updater script with additional error handling

## [0.0.3] - 2025-09-22

### Changed
- Refactored and hardened CLI updater script for improved reliability
- Enhanced error handling and edge case coverage

## [0.0.2] - 2025-09-15

### Changed
- Updated repository links to AeyeOps/ai-essentials organization
- Changed support contact to support@aeyeops.com
- Updated license owner to AeyeOps

## [0.0.1] - 2025-09-15

### Added
- Initial repository structure and scaffold
- Core project structure with scripts and documentation directories
- Ubuntu CLI update script (`scripts/update_cli_ubuntu.sh`) for development environment setup
- AGENTS.md guidance document for AI assistants and agentic tooling
- Basic documentation framework for AI development patterns
- MIT License
- Contributing guidelines and code of conduct
- Project README with goals and quick start guide
