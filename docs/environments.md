Environments

Goals
- Reproducible, minimal, and secure environments for AI tooling.

Local Setup
- Prefer Python 3.11+ with `python -m venv .venv`.
- Keep dependencies pinned in `requirements.txt` or per-tool install docs.
- Use `.env` for local-only variables; never commit secrets.

CLI Utilities
- Make scripts self-documenting with `--help`.
- Validate prerequisites (e.g., `python3`, `curl`, `jq`) and provide install hints.

Remote and Cloud
- Use containers for parity when feasible.
- Parameterize credentials and regions via environment variables.

Security Basics
- Principle of least privilege for API keys.
- Rotate secrets regularly; prefer secret managers over files.
