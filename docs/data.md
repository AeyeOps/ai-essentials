Data Handling

Foundations
- Track dataset provenance and versioning.
- Use clear schemas and document fields.

Formats
- Prefer parquet, jsonl, and CSV for portability.
- Validate with lightweight checks before training or evaluation.

Privacy
- Remove PII where possible; anonymize or tokenize when not.
- Maintain opt-out paths and data retention policies.

Storage
- Separate raw from processed data.
- Use checksums to verify integrity.
