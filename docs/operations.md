Operations

Packaging
- Keep CLIs single-file where possible; prefer zero-config defaults.
- Provide `--dry-run` for destructive operations.

Deployment
- Parameterize via env vars and flags; document required values.
- Emit structured logs to stdout for aggregation.

Monitoring
- Track latency, error rates, and cost.
- Capture inputs/outputs responsibly with redaction.
