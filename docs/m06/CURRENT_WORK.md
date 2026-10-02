# M06 current work

User resumed 2026-10-02. Primary D checkout, final-tuankiet@c3436d5 baseline.
Active scope M06.2–M06.5, local-first; M09 deferred until both collabs finish,
their work is integrated/tested together and a new UI/UX plan is prepared.

Read MUST_REMEMBER.md, CONTRACT.md and PROGRESS.md at continuation. No goal or
subagents; graph Tier2 exact D root. _agent_ops tools are absent.

## Current batch

- M06.2 source implemented: exact Cognito verified-sub lookup, owner share admin,
  Dynamo ACL/conditional stamps, canonical shared-update-only route, actor/pair
  receipts, actor feed, membership CAS, independent recipient password grants,
  Summary access epoch and private durable EVENT rows. No deployment.
- Backend source checkpoint accepted: 75/75 checks, tsc and diff check pass.
  Regression found intentional owned-route parser contract change (reject shared
  identity); test now asserts refusal. SDK-double union typing fixed.
  Pushed and remote verified at 08809ed. No deployment/live AWS claim.
- M06.3 source acceptance passed Chrome56 + Android56, VM408 (+1skip),
  editor/UI/repository147. Atomic compare-and-save and explicit editor review
  prevent silent local/remote overwrite. Shared With Me/management and encrypted
  unsaved access-loss evidence are connected. Final analyzer is clean and row
  regression119 passed. Notion actual FR05/06/10 NFR04/05 + recipient Done When
  checked. Pushed/remote verified 22dc1cc3faba47362ceac57f50791d64c5d37463.
  No live AWS claim.
- M06.4 source/protocol accepted: durable EVENT lease/recovery and scoped AppSync Events publish;
  account/session-owned socket adapter requests the existing cursor coordinator.
  No second local writer and no client publication. Protocol and two-client
  local acceptance precede the separate deployed AppSync/Cognito gate.
  Backend84/84 and tsc pass; final protocol/cursor VM14 and real Chrome14 pass.
  Android14 now passed after task-private TEMP retry (496s build, no uninstall).
  Scoped VM280 (+1skip), analyzer and diff check pass. Added catchUpPending feed flag and
  saved-cursor retry to cover an event arriving before GSI visibility.
  Android first build failed clang temporary-object rename in system TEMP,
  before any test. Retry uses a task-private ignored build temp directory;
  after the shared hook lock timeout, final Android retry now compiles with that
  private TEMP succeeded. Setup failures are excluded from acceptance counts.
  Subsequent uncached native builds must run sequentially; no native source edits.
  Duplicate D-path VM startup attempts timed out on the native hook lock and
  are excluded; the R-path VM receipt passed. Never overlap uncached native builds.
- M06.5 preparation: loopback synthetic WebSocket fixture + production Dynamo
  store/ACL/relay SDK-double HTTP fixture and two-client target. No AWS access,
  real Cognito/JWT verification or cloud encryption is claimed by that fixture.
- Next M06.4 durable metadata event relay/session
  subscription, M06.5 two-client Chrome + Android, full regression/fix.
- Local sharing intents may be durable, but ACTIVE ACL is only server-authorized.
- M05 encrypted drafts/session/consent/lineage must survive all changes.
- Update/push after accepted milestone/M/P, not after partial preparation.

## Preserve unrelated work

At entry macos/Flutter/GeneratedPluginRegistrant.swift was modified (SHA256
72E079184D14D8D03E86FB8928A90BC09F21E1D871F4F4B69FFF96030E67756B).
Do not revert/stage it. .playwright-cli/ and final_project.md stay untracked.
No C worktrees, no reset/uninstall, no live deployment authorization.
