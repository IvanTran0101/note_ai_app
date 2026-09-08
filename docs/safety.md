# Safety Policy

This file defines the minimum safety rules for Loop Engineering + Codex in this repository.

## Protected Paths

Do not modify without explicit human approval:

- `.env`
- `.env.*`
- `secrets/`
- `credentials/`
- authentication / authorization config
- database migrations / schema
- `.github/workflows/`
- infrastructure / deployment config

## Git Safety

- Never push directly to `main`.
- Never auto-merge.
- Never force-push without explicit approval.
- Use a separate branch or worktree for L2+ fixes.
- Human review is required before merge.

## Autonomy

### L1 — Report Only

Allowed:

- Read repository state
- Inspect recent changes
- Check CI, issues, and PRs
- Update `STATE.md` and `loop-run-log.md`

Not allowed:

- Modify source code
- Create commits
- Push
- Create or merge PRs
- Spawn sub-agents
- Change dependencies or migrations

### L2+ — Assisted Fixes

Allowed only for a clearly scoped task.

Requirements:

- Make the smallest necessary change.
- One fix per worktree.
- Run relevant verification.
- Verifier must review the result.
- Use a draft PR.
- Human approves merge.

## Verification

A code change is complete only when required checks pass.

For Flutter:

```bash
flutter analyze
flutter test
```

Never disable, weaken, or skip tests just to make CI pass.

## Retry Limit

Maximum fix attempts per item: **3**.

After 3 failed attempts:

```text
STOP
→ record evidence
→ ESCALATE_HUMAN
```

## Budget

Daily Triage:

- Max runs/day: 1
- Soft cap: 50k tokens/day
- Hard cap: 100k tokens/day
- Sub-agents at L1: 0

At 80% of the hard cap, switch to report-only.

At 100%, stop and require human review.

## Kill Switch

Kill switch:

```text
loop-pause-all
```

When active, stop immediately and perform no further actions.

## Human Escalation

Use `ESCALATE_HUMAN` when:

- protected files are involved
- a medium/high-risk change is required
- verification cannot prove correctness
- retry limit is reached
- budget limit is reached
- security impact is unclear

## Default Rule

When uncertain, choose the smallest safe action and escalate instead of expanding autonomy.

## Tool / MCP Permissions

Use least privilege for every loop role.

### L1 — Triage

Allowed:

- Read repository files
- Read Git status and history
- Read CI status
- Read GitHub issues
- Read GitHub pull requests
- Update `STATE.md`
- Update `loop-run-log.md`

Not allowed:

- Modify source code
- Create commits
- Push
- Create or modify pull requests
- Merge
- Delete branches
- Modify repository settings
- Access or modify secrets
- Modify production infrastructure

### L2 — Implementation

Allowed only for the approved task:

- Read repository files
- Modify files inside the approved scope
- Run relevant tests
- Run static analysis
- Create local commits
- Create a draft PR when explicitly permitted

Not allowed without explicit human approval:

- Push directly to `main`
- Merge
- Modify secrets
- Modify repository settings
- Delete branches
- Change branch protection
- Modify production infrastructure
- Perform destructive Git operations

### Verifier

Allowed:

- Read changed files
- Read relevant repository context
- Run verification commands
- Read CI results

Not allowed:

- Modify source code
- Implement fixes
- Push
- Merge
- Expand task scope