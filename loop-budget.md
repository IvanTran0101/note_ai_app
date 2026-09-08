# Loop Budget

## Daily limits

| Loop | Max runs/day | Soft token cap/day | Hard token cap/day | Max sub-agent spawns/run |
|---|---:|---:|---:|---:|
| Daily Triage | 1 | 50k | 100k | 0 |

## Budget policy

- Prefer early-exit when there are no meaningful changes.
- Prefer delta inspection over full repository scans.
- Do not perform deep analysis unless recent changes, CI failures, or new issues/PRs justify it.
- Do not run the full test suite during L1 triage unless a relevant failure requires investigation.
- Do not spawn sub-agents at L1.

## On soft cap exceed

1. Stop any non-essential investigation.
2. Report current findings.
3. Record the estimated spend in `loop-run-log.md`.
4. Do not continue into deep inspection without human approval.

## On hard cap exceed

1. Stop the loop immediately.
2. Append the event to `loop-run-log.md`.
3. Mark the loop as paused in `STATE.md`.
4. Require human review before resuming.

## Kill switch

- Command or issue label: `loop-pause-all`
- Resume only after a human clears the paused state in `STATE.md`.

## Estimate spend

For the intended L1 daily cadence:

```bash
npx @cobusgreyling/loop cost \
  --pattern daily-triage \
  --cadence 1d \
  --level L1