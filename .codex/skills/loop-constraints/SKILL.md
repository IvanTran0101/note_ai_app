---
name: loop-constraints
description: >
  Read loop-constraints.md before every loop run and enforce all applicable rules.
  Constraints override lower-priority loop behavior and action skills.
user_invocable: true
---

# Loop Constraints Enforcer

You are the guardrail for loop execution.

Before triage, implementation, verification, or any repository write action:

1. Read `loop-constraints.md` from the project root.
2. Determine the current autonomy level from the active loop configuration.
3. Check whether `loop-pause-all` is active.
4. Apply all applicable constraints to subsequent actions.
5. Stop or escalate whenever an action would violate a binding constraint.

Constraints are binding.

Do not restate the full constraints file unless explicitly requested.

## Start-of-Run Behavior

If `loop-pause-all` is active:

- Stop immediately.
- Do not inspect, modify, push, or create repository resources.
- Report that the loop is paused.

If `loop-constraints.md` exists:

- Read it once at the start of the run.
- Keep the applicable rules active for the duration of the run.
- Re-read only the relevant section immediately before a sensitive write action.

If `loop-constraints.md` does not exist:

- Apply the default safety constraints defined below.
- If `docs/safety.md` exists, apply any stricter rules from it.
- Do not assume `docs/safety.md` exists.

## Autonomy Enforcement

### L1 — Report Only

At L1:

- Allow read-only repository inspection.
- Allow reading CI status, issues, and pull requests when available.
- Allow updating loop state/log files only when the active loop policy permits it.
- Do not modify source code.
- Do not create commits.
- Do not push branches.
- Do not create or modify pull requests.
- Do not merge.
- Do not spawn sub-agents.
- Do not perform implementation work.

If triage discovers a problem requiring modification:

- Report it.
- Escalate to the human or an approved L2+ workflow.
- Do not fix it during the L1 run.

### L2+

At L2+:

- Apply all project constraints before any write action.
- Keep fixes narrowly scoped.
- Require verification before proposing completion.
- Respect retry, budget, protected-path, and human-review rules.

## Enforcement Rules

### Before Editing a File

1. Check the `Paths` section in `loop-constraints.md`.
2. Check whether the file is protected or denylisted.
3. If human approval is required and not present:
   - do not edit
   - escalate

### Before Changing Code

Check the `Code Changes` and `Verification` sections.

Require:

- smallest necessary change
- one scoped fix
- no unrelated refactor
- no weakened or disabled tests
- relevant verification after modification

At L1, code changes are prohibited regardless of whether the proposed fix appears safe.

### Before Retrying a Fix

Check the `Retry & Escalation` section.

- Respect the configured attempt limit.
- Record attempts when the required ledger mechanism exists.
- Run `loop-context --check` when required and available.
- Never reset or hide the retry count.
- Escalate when the limit is reached or progress has stalled.

### Before Pushing

Check the `Push & Merge` section.

Require:

- current autonomy level permits pushing
- human notification or approval where required
- target branch is allowed
- no protected-path violation

Never push directly to `main` when prohibited.

### Before Creating or Updating a PR

Check:

- autonomy level
- Push & Merge constraints
- verification status
- human-gate requirements

At L1, PR creation or modification is prohibited.

### Before Merging

Re-read the `Push & Merge` section.

Never merge without the required human approval.

Never auto-merge when prohibited.

### Before Sensitive Actions

Escalate before actions involving:

- authentication or authorization
- payments
- secrets or credentials
- infrastructure
- CI/CD configuration
- migrations or database schemas
- destructive Git operations
- protected branches

## Budget Interaction

`loop-budget.md` defines the normal budget.

`loop-constraints.md` may impose stricter limits.

When limits differ:

> Apply the stricter limit.

If the budget threshold requires report-only mode:

- stop implementation activity
- preserve current findings
- report the budget condition
- do not continue deep investigation

If the hard budget is reached:

- stop the loop
- follow the configured escalation policy

## Interaction with Other Skills

### `loop-triage`

Constraints override triage actions.

Example:

If triage finds a CI failure at L1:

```text
detect failure
→ investigate narrowly
→ report finding
→ do not implement fix