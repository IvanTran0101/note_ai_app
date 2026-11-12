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
{
  "run_id": "2026-09-08T07:42:55Z",
  "pattern": "daily-triage",
  "level": "L1",
  "duration_s": 90,
  "commit_before": "unknown",
  "commit_after": "c98285b",
  "ci_status": "unknown",
  "items_found": 1,
  "high_priority_items": 0,
  "watch_items": 1,
  "escalations": 0,
  "tokens_estimate": 8000,
  "outcome": "report-only"
}
{
  "run_id": "2026-10-06T06:35:30Z",
  "pattern": "daily-triage",
  "level": "L1",
  "trigger": "manual",
  "duration_s_estimate": 600,
  "commit_before": "c98285b",
  "commit_after": "8ec767db009fc6412e27268c971a927b6d88734d",
  "branch": "final-tuankiet",
  "branch_action": "already checked out; no switch required",
  "delta_commits": 182,
  "delta_files": 860,
  "ci_status": "unknown",
  "head_workflow_runs": 0,
  "latest_repo_ci": "success: c46498b / TuanKiet2 / run 36383048294 (2026-09-28)",
  "items_found": 2,
  "high_priority_items": 1,
  "watch_items": 3,
  "escalations": 1,
  "subagents": 0,
  "tokens_estimate": 25000,
  "estimates_metered": false,
  "outcome": "escalated",
  "summary": "No CI for HEAD; push trigger main differs from default note-ai-app. Latest encrypted-cache read fix needs human review; recorded local acceptance is not independent CI.",
  "issue_pr_scope": "bounded updated-since-2026-09-08 queries empty; pause label inactive",
  "preserved_dirty_files": 3,
  "tests_run": false,
  "source_edits": false,
  "commits_pushes_pr_writes": false
}
```
