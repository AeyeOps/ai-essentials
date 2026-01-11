# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.0.5] - 2026-01-10

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