# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

## [0.4.1] - 2026-01-20

### Added
- Async logging for server with QueueHandler/QueueListener (non-blocking writes)
- Audio warmup at module load to prevent first PTT beep from being swallowed

### Changed
- Installer always installs tray dependencies (pystray, pillow) via `--extra desktop`
- Audio initialization moved to module load time for faster first sound
- Client singleton now uses kill-and-takeover pattern (newest instance wins)

### Fixed
- Excluded parent PID in singleton check (fixes uv wrapper being killed)
- Installer returns to original directory on completion (avoids direnv issues)
- First PTT beep no longer lost due to PulseAudio startup latency

## [0.4.0] - 2026-01-20

### Changed
- Rebranded from "STT Service" to "AEO Push-to-Talk" across all user-facing surfaces
- Updated installer banners, systemd description, and documentation
- Internal identifiers (file paths, class names) unchanged for compatibility

## [0.0.13] - 2026-01-19

### Added
- STT Service system-wide auto-start (AEO Push-to-Talk)
  - XDG autostart desktop entry for automatic client launch at login
  - System tray indicator with state colors (gray=connecting, green=ready, red=recording)
  - Daemon mode (`--daemon`) for silent background operation
  - `desktop` optional dependency group (evdev, pystray, pillow)
  - Installer prompts for auto-start after systemd service setup
  - Uninstaller cleanup for autostart entry

### Changed
- STT Service installer comments now use raw.githubusercontent.com instead of jsdelivr
- Test sandbox script URLs updated to raw.githubusercontent.com

## [0.0.12] - 2026-01-20

### Added
- STT Service Push-to-Talk (PTT) terminal mode for Docker/SSH environments
  - Spacebar-based recording (hold to record, release to transcribe)
  - Clean timing output format: `[2.1s → 45ms] transcribed text`
  - 30-second auto-submit with seamless continuation
  - Audio feedback (click/unclick sounds) with paplay fallback for containers
  - Robust key release detection with two-phase timeout algorithm
- STT Service test sandbox (`packages/stt-service/scripts/test-sandbox.sh`)
  - CUDA 13 Ubuntu 24.04 container with GPU passthrough
  - PulseAudio client configuration for audio output in Docker
  - Automatic UID/GID matching for socket permissions

### Changed
- STT Service installer now always downloads from GitHub (removed local source detection)
- STT Service logging moved to file-only (no console spam with -v flag)
- Server and client logs written to `~/.local/state/stt-service/`

### Fixed
- PTT race condition where recording could be cancelled before WebSocket connection completed
- Audio device selection now uses system default instead of first available device
- Installer no longer deletes itself when run from within installation directory

## [0.0.11] - 2026-01-19

### Added
- Claude Code ultrareview command suite (`claude-code/commands/ultrareview/`)
  - `/ultrareview` - Deep validation of plans, code, and context
  - `/ultrareview-fix` - Systematic resolution of ultrareview findings
  - `/ultrareview-loop` - Automated validation loop (cycles until no findings)
  - Session tokens for multi-user safety in shared projects
  - Stop hook pattern following ralph-loop plugin architecture

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
