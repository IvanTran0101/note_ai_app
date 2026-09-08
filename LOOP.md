# Loop Configuration — Minimal Triage (Codex)

## Active Loops

| Pattern | Cadence | Status | Automation prompt |
|---------|---------|--------|-------------------|
| Daily Triage | 1d | L1 report-only | `Run $loop-triage. Read STATE.md. Inspect only changes since the last triage. Check repository health, latest CI status, and relevant open issues/PRs if available. Report actionable findings only. Do not modify code. Early-exit when there are no meaningful changes.` |

## Triage Scope

Daily Triage must:

- Read `STATE.md`
- Inspect changes since the last recorded triage
- Prefer delta inspection over full repository scans
- Check latest CI status when available
- Check only relevant open issues and PRs when available
- Report only actionable findings
- Update loop state/log only when appropriate
- Early-exit if there are no meaningful changes

Daily Triage must not:

- Modify source code
- Refactor unrelated code
- Update dependencies
- Modify database migrations or schemas
- Run the full test suite unless a relevant failure requires investigation
- Spawn sub-agents at L1
- Create or merge pull requests
- Push directly to protected branches

## Human Gates

- No auto-fix until the L2 checklist is complete
- No auto-merge
- No direct push to `main`
- All code changes require human review
- All high-risk paths require human review
- See `docs/safety.md` for denylist and protected paths

## Worktrees

- Codex may use a dedicated worktree per thread for L2+ fix attempts
- One scoped fix per worktree
- Do not mix unrelated changes in the same worktree
- Verifier sub-agent must APPROVE before proposing a PR at L2+

## Connectors (MCP)

- MCP is optional for L1 report-only loops
- For L2+, GitHub connector may read:
  - CI status
  - issues
  - pull requests
- Write scope must remain limited to comments until explicitly trusted
- No merge, branch deletion, or repository-setting changes through connectors

## Budget

- Max scheduled runs per day: 1
- Suggested daily token cap: 50k
- Hard daily token ceiling: 100k
- Max sub-agent spawns per run: 0 at L1
- Prefer early-exit over deep inspection
- Stop and require human review if the hard budget is exceeded
- Review `STATE.md` and Codex Triage inbox daily

## Escalation

Escalate to human review when:

- CI failure cannot be explained from recent changes
- A fix would require source-code modification
- A dependency update is required
- A migration or schema change is required
- Security-sensitive files are involved
- The same issue repeats without progress
- The token budget would be exceeded

## Links

- Pattern: [daily-triage](../../patterns/daily-triage.md)
- Checklist: [loop-design-checklist](../../docs/loop-design-checklist.md)