# Loop Constraints

> Add rules below with `/constraints <rule>` in your agent.
>
> The `loop-constraints` skill reads this file at the start of every run.
>
> Constraints here are **binding** — the agent MUST follow them.

## Autonomy Levels

### L1 — Report Only

At L1, the agent may:

- Read repository state
- Inspect recent changes
- Check CI status
- Read relevant issues and pull requests
- Update `STATE.md` and `loop-run-log.md` when appropriate
- Report actionable findings

At L1, the agent must not:

- Modify source code
- Modify dependencies
- Modify migrations or schemas
- Create commits
- Push branches
- Create or modify pull requests
- Spawn sub-agents
- Run full test suites unless required to investigate a specific failure

### L2+ — Assisted Fixes

Code changes are allowed only after explicit human approval or when the loop has been intentionally promoted to L2+.

## Push & Merge

- Never push before informing the human.
- Never push directly to `main`.
- Never auto-merge into `main`.
- Human approval is required before merge.
- For L2+ changes, create a draft PR first.
- Do not mark a draft PR ready for review without human approval.
- Never force-push unless explicitly authorized for a specific task.

## Paths

Never edit the following without explicit human approval:

- `.env`
- `.env.*`
- `auth/`
- `payments/`
- `secrets/`
- `credentials/`
- signing keys
- API keys
- deployment credentials

Never edit infrastructure or CI/CD configuration without explicit human approval, including:

- `.github/workflows/`
- Docker / Compose files
- deployment manifests
- cloud configuration
- infrastructure-as-code files

## Code Changes

For L2+ fix attempts:

- Make the smallest change necessary to solve the scoped problem.
- Never refactor unrelated code.
- One scoped fix per run.
- Never disable, skip, weaken, or delete tests just to make CI green.
- Run relevant tests before proposing a fix.
- Run the required verification gate before declaring success.
- Do not change public APIs unless required by the task.
- Do not add dependencies unless necessary and justified.

## Verification

When code has changed:

1. Run the smallest relevant verification first.
2. Run required project-level verification before proposing completion.
3. Record failures before retrying.
4. Never claim success if required checks are failing.

At L1 with no code changes:

- Do not run tests by default.
- Prefer CI status and existing verification results.
- Early-exit when there are no actionable findings.

## Retry & Escalation

- Maximum 3 fix attempts per item.
- Record every fix attempt in `loop-ledger.json`.
- Run `loop-context --check` before retrying when the required tooling is available.
- Escalate immediately if the same failure repeats without meaningful progress.
- Escalate instead of broadening scope without approval.
- Do not reset or hide the attempt count between runs.

## Communication

- Before any write action, state what will be changed and why.
- Read-only L1 inspection does not require announcing every individual read operation.
- Never close an issue or PR without human approval.
- Clearly distinguish observations, proposed actions, and completed actions.
- Do not present an unverified assumption as a confirmed finding.

## Budget

- If estimated token spend reaches 80% of the daily hard cap, switch to report-only.
- Prefer early-exit over additional investigation when findings are non-actionable.
- Do not exceed the configured hard token cap.
- If `loop-pause-all` is active, exit immediately.
- If budget limits conflict with completing an investigation, stop and escalate.

## Safety

- Never expose secrets, tokens, credentials, or sensitive configuration in logs or reports.
- Never bypass branch protection, CI checks, or security controls.
- Never use destructive Git operations without explicit approval.
- Never delete branches, tags, issues, pull requests, or repository resources without explicit approval.

---

<!-- Add your own project-specific rules below. Use plain English. The loop reads this verbatim. -->