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
  No deployment/live AWS claim. Next: M06.3 pair-aware repository/Application,
  HTTP shared mappings, recipient protection scope, shared/management UI.
- Then M06.3 shared UI/offline, M06.4 durable metadata event relay/session
  subscription, M06.5 two-client Chrome + Android, full regression/fix.
- Local sharing intents may be durable, but ACTIVE ACL is only server-authorized.
- M05 encrypted drafts/session/consent/lineage must survive all changes.
- Update/push after accepted milestone/M/P, not after partial preparation.

## Preserve unrelated work

At entry macos/Flutter/GeneratedPluginRegistrant.swift was modified (SHA256
72E079184D14D8D03E86FB8928A90BC09F21E1D871F4F4B69FFF96030E67756B).
Do not revert/stage it. .playwright-cli/ and final_project.md stay untracked.
No C worktrees, no reset/uninstall, no live deployment authorization.
