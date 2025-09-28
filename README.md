AI Essentials

A public, general-purpose collection of scripts, docs, and utilities that support modern AI-based development: local tooling, cloud workflows, model evaluation, data handling, ops, and best practices. This repository is intended to be practical, lightweight, and framework-agnostic.

- Home: https://github.com/AeyeOps/ai-essentials
- Maintainer: AeyeOps Support (support@aeyeops.com)

Contents
- `scripts/`: CLI helpers and setup scripts for common environments.
  - `google-chrome-wsl2.sh`: Chrome launcher optimized for WSL2 browser automation
  - `update_cli_ubuntu.sh`: Development environment setup for Ubuntu systems
- `docs/`: Short guides, patterns, and checklists for AI dev and ops.
- `AGENTS.md`: Guidance and conventions for agentic tooling and assistants working in this repo.

Quick Start
1. Review the license and contribution guidelines.
2. Explore `scripts/` for useful automation. Run scripts with caution and review them first.
3. Browse `docs/` for task-oriented guidance and patterns.

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
