---
name: loop-budget
description: >
  Enforce loop token and run budgets before and after each loop iteration.
  Prefer early exit, delta inspection, and report-only behavior when budget
  thresholds are approached.
user_invocable: false
---

# Loop Budget Guard

Run at the start and end of every loop iteration.

Budget enforcement is mandatory.

## Start of Run

### 1. Load Budget Policy

Read `loop-budget.md`.

Determine for the active loop:

- maximum scheduled runs per day
- soft token cap
- hard token cap
- maximum sub-agent spawns per run
- kill-switch state
- any stricter limits imposed by `loop-constraints.md`

When policies conflict, apply the stricter limit.

### 2. Check Kill Switch

If `loop-pause-all` is active:

- stop immediately
- do not perform triage or implementation
- record the paused state if needed
- report:

```text
LOOP_PAUSED: loop-pause-all is active.