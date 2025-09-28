# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased] - 2025-09-28

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