# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.0.31] - 2026-07-13

### Added
- `configs/herdr/`: herdr agent multiplexer bundle — `config.toml` (ctrl+a prefix clearing tmux ctrl+b and AEO tmux C-Space, tokyo-night on pure-black panels, system toasts, `resume_agents_on_restore` + `pane_history` persistence), `zshenv-display-snippet.zsh` (derives `DISPLAY` from the live X socket for GUI tools inside panes; inert when DISPLAY is already set), and a README with manual install steps and operational gotchas (never nest tmux/zellij inside a herdr pane; `pane_history` writes scrollback to disk; integration hooks embed machine-local absolute paths).
- `setup-ai-dev-stack.sh`: new optional "AEO Herdr + Config" component (section 7b) — installs herdr via the official installer, deploys the config with timestamped backup and live server reload, installs agent integrations gated on the agent CLIs actually present (claude, pi, codex, opencode), the herdr agent skill (socket-API pane control, self-gated on `HERDR_ENV=1`), plugins (herdr-plus prebuilt; file-viewer and spreader gated on a Rust toolchain), zsh completions (fpath inserted before oh-my-zsh's compinit to avoid stale-dump clobbering) and bash completions, and the `.zshenv` DISPLAY fallback. An md5-keyed idempotent pre-check silently skips when everything is current.

## [0.0.30] - 2026-06-15

### Added
- `configs/ghostty/`: Ghostty session launcher bundle — `ghostty-tmux-launch` (zsh) and `ghostty-tmux-launch.bash` (bash port), `aeo-launcher.conf` (native-split keybinds + the desktop-gated decoration fix), `config.full` (opinionated config), `rc-snippet.zsh`/`rc-snippet.bash`, and a README. Transparent tmux: every Ghostty surface (window, tab, native split) lands in its own recoverable tmux session via one fzf screen that names the session and pulls detached sessions in as panes.
- `setup-ai-dev-stack.sh`: new optional "AEO Ghostty session launcher" component with two install paths — **Integrate** (additive; appends a `config-file = aeo-launcher.conf` include and the shell rc guard, overriding only `alt+d`, `alt+shift+d`, and, when needed, Ghostty decoration keys) and **Full AEO** (replaces the Ghostty and tmux configs after a pre-confirm screen, with timestamped backups and a generated one-command `restore-<stamp>.sh`). A mode-marker-keyed idempotent pre-check silently skips when the recorded mode is already fully deployed.
- `setup-ai-dev-stack.sh`: desktop decoration detection now treats Plasma/KWin separately: it enables `window-decoration = server` and `gtk-titlebar = false`, while non-SSD tiling WMs keep the borderless `window-decoration = none` fallback for GTK CSD `_GTK_FRAME_EXTENTS` mouse→cell offsets.
- `setup-ai-dev-stack.sh`: resolves an `fzf` ≥ 0.45 (the launcher's conditional `Tab` needs fzf's `transform` action, added in 0.45; apt ships 0.44.1), installing the latest release to `/usr/local/bin` when no new-enough fzf is present, and pins the resolved path in the rc guard so it is used even before the rc edits `PATH`.

### Changed
- `configs/tmux/tmux.conf`: added Ghostty terminfo + title forwarding for the session launcher (`terminal-features` for `xterm-ghostty` RGB and hyperlinks, `set-titles on`).

## [0.0.29] - 2026-06-12

### Changed
- `update-coding-agents.sh` now replaces Gemini CLI with agy, and tmux adds `P`/`merge-panes` for detached-session panes.

## [0.0.28] - 2026-05-24

### Added
- `update-coding-agents.sh`: `handle_pi` — manages the `pi` agentic coding CLI (Earendil Works, `@earendil-works/pi-coding-agent`). Detects local `pi` via `command -v`, queries the npm registry for the latest version, installs/updates via `npm install -g --ignore-scripts @earendil-works/pi-coding-agent` when versions differ. Skips gracefully if `npm` is unavailable.
- `update-coding-agents.sh`: `handle_grok` — manages the xAI Grok CLI as an opt-in tool. Gated by `--with-grok` flag or `INCLUDE_GROK=1` environment variable. When opted in, always runs the official installer `curl -fsSL https://x.ai/cli/install.sh | bash` (the documented install and upgrade path); no version pre-check is performed. Records resulting `grok --version` in the summary when detectable.
- `update-coding-agents.sh`: `--with-grok` command-line flag. Unknown arguments now cause the script to print help and exit 2.

### Changed
- Renamed `scripts/update_cli_ubuntu.sh` to `scripts/update-coding-agents.sh` — script now supports Linux and macOS, and name reflects its purpose (updating agentic coding CLIs) rather than the original Ubuntu-only scope. Updated references in `README.md`, `AGENTS.md`, and the script's header/help text.
- `update-coding-agents.sh`: switched shebang from `#!/usr/bin/env zsh` to `#!/usr/bin/env bash` to match `AGENTS.md` project standard, the script's own `bash scripts/...` usage docs, and to allow `shellcheck` to lint the file (previously blocked by SC1071). Stock Ubuntu lacks zsh, so direct invocation (`./scripts/update-coding-agents.sh`) now works on a default Linux host.
- `update-coding-agents.sh`: help text now lists the default and opt-in tool sets separately and documents the `--with-grok` flag.

### Fixed
- `update-coding-agents.sh`: replaced hardcoded `/tmp/claude_install.sh` install-script path with `mktemp` (portable across Linux and macOS) to remove a predictable-path symlink-race trap on shared hosts; installer is now cleaned up after run.

## [0.0.27] - 2026-05-10

### Changed
- `setup-ai-dev-stack.sh`: Collapsed the shell stack (zsh + Oh-My-Zsh + Powerlevel10k + MesloLGS Nerd Font + zsh plugins + p10k preset + `~/.zshenv`) into a single `[Y/n]` bundle prompt with an idempotent pre-check that silently skips when every component is already in place
- `setup-ai-dev-stack.sh`: Collapsed tmux install/upgrade and AEO config deploy into a single `[y/N]` bundle prompt; pre-check md5-compares the deployed `tmux.conf` and every file under `tmux/scripts/` against the repo and verifies no apt upgrade is pending before silently skipping
- `setup-ai-dev-stack.sh`: Collapsed zellij install, plugin deploy (`zjstatus.wasm`, `zjwidth.wasm`), config, and default layout deploy into a single `[y/N]` bundle prompt with an md5-based pre-check
- `setup-ai-dev-stack.sh`: Homebrew shellenv now wired into both `~/.bashrc` and `~/.zshrc` (previously only `~/.zshrc`)
- `setup-ai-dev-stack.sh`: Summary block lists shell stack, tmux, and zellij components only when their respective bundles were applied

### Fixed
- `setup-ai-dev-stack.sh`: Removed the standalone tmux upgrade prompt that fired even when no apt upgrade was available
- `setup-ai-dev-stack.sh`: Removed the standalone `~/.zshenv` deployment prompt that fired when both NVM and Bun blocks were already present
- `setup-ai-dev-stack.sh`: Suppressed the misleading "AEO Powerlevel10k theme preset applied" success message when nothing was actually mutated
- `setup-ai-dev-stack.sh`: Added a missing `success` log line confirming tool aliases were appended to `~/.zshrc`

### Removed
- `setup-ai-dev-stack.sh`: Internal `TMUX_FRESH_INSTALL` and `ZELLIJ_FRESH_INSTALL` flags, obsoleted by the unified bundle deploy logic

## [0.0.26] - 2026-04-26

### Added
- Zellij default layout (`configs/zellij/layouts/default.kdl`): built-in tab-bar + status-bar (preserves Ctrl submodes) plus a 1-row zjstatus alt-bar sized at runtime by the zjwidth sidecar
- zjwidth sidecar plugin source tree (`configs/zellij/plugins-src/zjwidth/`) and built artifact (`configs/zellij/plugins/zjwidth.wasm`)
- `setup-ai-dev-stack.sh`: deploy step for `zjwidth.wasm` from repo to `~/.config/zellij/plugins/`
- `setup-ai-dev-stack.sh`: idempotent permission pre-seeding for `zjstatus.wasm` and `zjwidth.wasm` in `~/.cache/zellij/permissions.kdl`, preserving any existing entries — avoids interactive Allow? prompts on first session

### Changed
- `configs/zellij/config.kdl`: substantial rewrite to drive the new layout and zjstatus integration
- `setup-ai-dev-stack.sh` zjstatus deploy: switched existence check from `-f` to `-s` so a 0-byte download from a prior run is repaired on rerun; added post-curl size validation chained via `&&`
- `setup-ai-dev-stack.sh` zjwidth deploy: `-s` source validation, three-state branching (good / empty / missing) with distinct warnings, and a defensive post-cp size check

### Fixed
- `update_cli_ubuntu.sh`: source nvm with `${NVM_DIR:=$HOME/.nvm}` fallback so non-interactive shells (hooks, cron, `env -i`) don't fall through to stale system Node and produce EACCES errors on npm-managed CLIs (e.g. Gemini)
- `update_cli_ubuntu.sh`: `handle_crush` now resolves `$GOBIN` / `$(go env GOPATH)/bin` and prepends to `PATH` inside the function, so non-interactive runs detect installed crush instead of reporting "Updated from none to unknown"

## [0.0.25] - 2026-02-17

### Added
- Bulk git gc script (`scripts/git-bulk-gc.sh`) for running `git gc` across all repos under a directory tree
  - Parallel execution with configurable `-j N` (default: nproc/2)
  - Dry-run mode for read-only audit with object/pack statistics
  - Aggressive gc mode (`--aggressive`) for deeper repacking
  - Resume support via existing CSV progress files
  - Live progress display with per-tree bars, active worker status, and ESC-to-cancel
  - CSV output for success/failure tracking with per-repo logs
  - macOS/Linux portable (nproc + sysctl fallback, EPOCHREALTIME guard)

## [0.0.24] - 2026-02-13

### Changed
- Reduce tmux display-message timeout from 3s to 2s

## [0.0.23] - 2026-02-13

### Added
- Add terminal-aware tab spawning for navigator create-session operations (C-y, C-r)
  - Detects host terminal (Windows Terminal via WSL, Kitty) and opens new tab attached to new session
  - Kitty handler with `kitten @` remote control and new-instance fallback
- Enable Kitty remote control (`allow_remote_control socket-only`) for tab spawning support

### Changed
- Navigator C-y/C-r now open new terminal tab instead of switching client away from current session

## [0.0.22] - 2026-02-13

### Added
- Add create operations to tmux navigator: break pane to new window (C-t), break pane to new session (C-y), move window to new session (C-r)
- Add single-pane guards for break operations with user-visible messages

### Removed
- Remove `w` (list) and `f` (find) from tmux status bar and prefix table — superseded by navigator

## [0.0.21] - 2026-02-13

### Added
- Tmux navigator popup (`Prefix + Tab`) replacing separate overview and join-pane tools
  - Fzf-powered unified view of all panes across sessions with action key dispatch
  - Enter: jump, C-o: bring pane, C-s: send pane, C-g: bring window, C-x: swap
  - Detached session rows dimmed; send/swap to detached targets blocked
  - No-op guards with descriptive messages for redundant actions
  - Catppuccin-styled action legend bar in fzf header
- Glow markdown renderer configuration (`configs/glow/glow.yml`)

### Removed
- `scripts/overview.sh` and `scripts/join-pane-menu.sh` replaced by navigator
- `Prefix + J` and `Prefix + i` bindings replaced by `Prefix + Tab`

## [0.0.20] - 2026-02-11

### Removed
- Kiro CLI support disabled in update script (`scripts/update_cli_ubuntu.sh`)

## [0.0.19] - 2026-02-11

### Added
- tmux configuration (`configs/tmux/tmux.conf`) optimized for AI-assisted development
  - `Ctrl+Space` prefix to avoid conflict with Claude Code's `Ctrl+b`
  - Zero escape-time, true color, Vi copy mode, OSC 52 clipboard
  - 3-row color-coded status bar with inline keyboard reference
  - Live window list (right-aligned) with active window highlighting
  - `Prefix + J`: Interactive join-pane menu to merge panes across windows or break to new window
  - `Prefix + M`: Merge all detached sessions into current session
  - `Prefix + T`: Set pane title
  - Catppuccin Mocha color scheme for status bar and pane borders
- Helper script `configs/tmux/scripts/join-pane-menu.sh` for the join-pane menu
- README for tmux configuration with installation instructions

## [0.0.18] - 2026-02-06

### Fixed
- Oh-My-Zsh install now fully non-interactive (`KEEP_ZSHRC=yes` prevents .zshrc overwrite prompt)
- Powerlevel10k wizard no longer runs unexpectedly on first Zsh launch

### Added
- Interactive AEO Powerlevel10k theme preset prompt during dev stack install
  - Deploys `configs/zsh/p10k-aeo.zsh` → `~/.p10k.zsh` for instant themed prompt
  - Prepends p10k instant prompt cache block to top of `.zshrc`
  - Appends `source ~/.p10k.zsh` as last line in `.zshrc` (after all other appends)
  - EOF-safe read with graceful fallback for non-interactive invocations
  - Preserves `.zshrc` file permissions via `mktemp` + `chmod --reference`
  - Fully idempotent with `grep -q` guards on all modifications
- Conditional install summary: shows "pre-configured" or "wizard will run" based on user choice

## [0.0.17] - 2026-02-03

### Fixed
- Claude Code version detection in `scripts/update_cli_ubuntu.sh`
  - Check official install location (`~/.local/bin/claude`) before PATH lookup
  - Prevents stale versions from alternative install methods being reported
  - Post-install version check now uses the correct binary
  - Displays detected binary path for easier debugging

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
