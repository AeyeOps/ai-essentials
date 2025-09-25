# Repository Guidelines

## Project Structure & Module Organization
The repository is intentionally lean: documentation lives in `docs/`, executable helpers live in `scripts/`, and top-level Markdown files describe community, contribution, and agent operations. When adding new material, align with this split—reference guides belong under `docs/`, automation should land in `scripts/`, and include a short pointer from `README.md` if the entry point changes.

## Build, Test, and Development Commands
There is no monolithic build; validate contributions with targeted commands. Use `bash scripts/update_cli_ubuntu.sh -h` to review script behaviour before running `bash scripts/update_cli_ubuntu.sh` on Ubuntu hosts. Lint shell changes locally via `shellcheck scripts/update_cli_ubuntu.sh` and dry-run new scripts with `bash -n path/to/script.sh`. Keep examples reproducible across POSIX shells.

## Coding Style & Naming Conventions
Shell scripts must start with `#!/usr/bin/env bash` and `set -euo pipefail`. Favour two-space indentation, uppercase constants (e.g., `Q_DEB_URL`), and descriptive function names such as `install_q_from_deb`. New Markdown content should use sentence-case headings and concise bullets; keep tables and diagrams in plain Markdown so they render well on GitHub.

## Testing Guidelines
Automated tests are not yet bundled, so treat every change as opt-in QA. Run `shellcheck` on every modified script, execute scripts with `--help` to confirm messaging, and manually verify network-dependent flows in a disposable environment. For documentation, build confidence through copyediting and, when relevant, capture short command transcripts to confirm accuracy.

## Commit & Pull Request Guidelines
Follow the repository norm of small, imperative commits (e.g., `Add agent quick-start section`). Document behavioural changes in the same review—update `README.md`, relevant files under `docs/`, and script help text together. Pull requests should link to any open Archon tasks, describe impact, list verification steps, and include screenshots or logs when tooling output changes.

## Security & Configuration Tips
Never commit secrets or machine-specific paths. Prefer environment variables for API keys, and scrub transcripts before sharing. Review scripts for elevated privilege calls like `sudo` and call them out in pull requests so reviewers can assess operational risk.
