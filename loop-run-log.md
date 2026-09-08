# Loop Run Log — My Project

Append one concise entry per run.

Prune entries older than 30 days.

Do not store:
- full CI logs
- full diffs
- long reasoning
- source-code excerpts
- secrets or credentials

## Format

```json
{
  "run_id": "2026-09-08T08:15:00Z",
  "pattern": "daily-triage",
  "level": "L1",
  "duration_s": 45,

  "commit_before": "abc123",
  "commit_after": "def456",

  "ci_status": "green | failed | unknown",

  "items_found": 2,
  "high_priority_items": 0,
  "watch_items": 2,
  "escalations": 0,

  "tokens_estimate": 12000,

  "outcome": "no-op | report-only | escalated"
}