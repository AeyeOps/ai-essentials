Agents Guide

Scope
This file applies to the entire repository. It provides conventions and guidance for agentic tooling and AI assistants that contribute to or operate within this project.

Principles
- Be precise and minimal: implement exactly what is requested without overreach.
- Prefer clarity over cleverness: choose explicit, auditable implementations.
- Keep portability in mind: default to POSIX shell and Python 3 standard library when possible.
- Document assumptions and side effects in the same change.

Repository Conventions
- Scripts live in `scripts/` and should be executable, with `set -euo pipefail` and `-x` only when troubleshooting.
- Every script must support `-h|--help` and exit with non-zero on error.
- Do not hardcode secrets. Accept configuration via flags or environment variables.
- Keep external dependencies optional; detect and guide users to install when needed.

Git and Change Hygiene
- Small, focused commits with imperative messages.
- Update `README.md`, `docs/`, and script help text together with behavior changes.
- Avoid unrelated refactors in functional changes.

Assistant Behavior
- Before running commands that mutate state, describe intent succinctly.
- Prefer reading to writing; propose patches for review when unsure.
- Respect `.gitignore` and avoid generating untracked binaries.

Testing and Verification
- Provide a simple example or smoke test path for new utilities.
- When adding Python, prefer `python -m venv` and keep requirements pinned if needed.

Licensing
All contributions are MIT-licensed under `LICENSE`.
