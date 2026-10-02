# M06 — Implementation progress

## Current resumed work — 2026-10-02

User resumed M06.2–M06.5 with local-first behavior; all historical pause records
are superseded. Baseline final-tuankiet@c3436d5, accepted M05 local-first d02fc40.
Preserve the pre-existing modified macos/Flutter/GeneratedPluginRegistrant.swift
and untracked .playwright-cli/ and final_project.md. _agent_ops remains absent.
Current scope: fresh backend ACL/verified recipient + conditional actor/canonical
sync and Summary, then local-first sharing/UI and durable realtime acceptance.
M09 is deferred until both collaborators finish and a combined integration/test
batch precedes a new UI/UX plan. No M09 implementation in this M06 run.
M06.2–M06.4 source acceptance now passes. Next M06.5 full two-client local
acceptance and the separate deployed AppSync/Cognito gate.

Updated 2026-10-02. Active scope: M06 only, after M05 accepted and pushed at
22587a5954c182c202d07923ec8be1e3060fa42d. Read MUST_REMEMBER.md before coding.

- [Source plan](https://app.notion.com/p/3e8f9c7a1aa08193b4f9d1fbf42999ed)
- [Progress page](https://app.notion.com/p/3edf9c7a1aa0817fb5fedd1e18b52ab2)
- [Frozen contract](CONTRACT.md)
- [Delivery branch](https://github.com/IvanTran0101/note_ai_app/tree/final-tuankiet)

## Milestones

| Milestone | State | Evidence/next step |
| --- | --- | --- |
| M06.0 | Complete contract/evidence freeze | Notion decisions and current source inspected; CONTRACT.md |
| M06.1 | Complete foundation | Canonical pair/role/share policy, strict v3 codecs, encrypted actor storage; Chrome40 + Android40 |
| M06.2 | Complete backend source/tests | SERVER_CONTRACT.md; 75 backend checks, tsc; AWS live gate remains separate |
| M06.3 | Complete client source acceptance | CLIENT_CONTRACT.md; Chrome56 + Android56, local encrypted storage/UI/atomic draft review |
| M06.4 | Complete source/protocol acceptance | REALTIME.md; backend84, Chrome14 + Android14, VM280 (+1skip); deployed AWS gate pending |
| M06.5 | Planned | Full tests + two clients on Web/Android; distinguish live cloud spike |

At contract freeze all criteria were pending. Current accepted criteria: FR05,
FR06, FR10, NFR04, NFR05 and recipient Shared With Me Done When; backend/live
realtime and full two-client gates remain explicit. Update this record DURING
work with files, confirmed failures and the next step; after each completed M06.x
or M/P criterion, update Notion, explicit-stage commit/push and verify remote SHA.

## M06.0 evidence

Graph Tier2 source/coverage findings and compatibility requirements are recorded
in CONTRACT.md. Canonical identity crosses every layer; bare-id maps and owner-only
gates are known existing limitations to replace, not permission to remove guards.
M05 tests passed: VM921/2skip, Chrome797/1skip, Android12 and real Web-plugin12;
backend57, root analyzer and typecheck. Additional native bridge smoke6 and
Chrome stub1 also passed; no model loaded. No deployment was performed.

## Current work

Next: implement M06.1 domain types, preserve owned-note compatibility, add tests
for same noteId across two owners and foreign projection validation; then extend
vault/codec identity without relabeling existing authenticated ciphertext.

### Workspace correction and current M06.1 files

User requested C: worktrees removed. The primary D: checkout is now
final-tuankiet@61a826b. Four uncommitted domain files were backed up/restored and
hash-verified: note_identity.dart, note_role.dart, note_share_grant.dart and
note_access_policy.dart. They implement canonical pairs, viewer/editor, lifecycle
and local operation policy; not yet wired or accepted. Graph project is now
noteflow-final-d, freshly indexed at the D: root. Original untracked user files
are preserved; the old instructions/configuration backup is outside the repo on D:.
R: maps this same primary directory to keep native command paths short. Chrome
checks will use a real browser; Android checks use emulator-5554 with no reset.
Next: domain/DTO/local actor projection and codecs, plus identity/lifecycle tests.

### M06.1 source and initial verification

C: worktree directories are now absent; emulator restarted from D without reset.
Added canonical/share fields through DTO/local state/mutation/snapshot/conflict,
strict optional v3 codecs, pair-aware vault/bundle/hydration and actor queue checks.
Access-first page projection blocks stale epochs before pending/revision filtering;
encrypted storage retains drafts and parks keys when access changes. Added domain,
projection and real-platform store scenarios, plus integration_test/m06_sharing_test.dart.
Initial Chrome run: 43 passed, one legacy typed-error-message assertion failed;
restored the field-specific rejection for an ungranted foreign projection and rerunning.
No M06.1 acceptance claim yet. npm ci prerequisite fixed missing OpenTelemetry peer
entries in package-lock.json; 927 dependencies installed successfully. Next: Chrome
regressions, real Web/Android integration, review vault compatibility, then checkpoint.

### M06.1 acceptance - 2026-10-02

- Real Chrome browser integration: 40 application cases passed, driver result true,
  empty failureDetails. Real Android emulator-5554 integration: 40 passed, 0 failed.
- Covers role/lifecycle, same-id canonical pairs, legacy strict shape, isolated
  protected keys, access-first revoke/re-share, encrypted retained draft, per-note
  denial with owned queue continuation, conflict role policy and old v3 reserved-id
  ciphertext/quarantine reopening with unchanged authenticated binding.
- Coordinator/resolver legacy regression cases are included in these 40 cases.
  Earlier broader Chrome foundation regression: 63 passed. Scoped analyzer clean.
- Commands: flutter build web --debug --target integration_test/m06_sharing_test.dart
  --output output/m06-browser-integration --no-pub --no-wasm-dry-run; real Chrome
  via Playwright CLI at localhost8766 and request_data driver; flutter test
  integration_test/m06_sharing_test.dart -d emulator-5554 --no-pub --no-uninstall.
- Evidence logs outside repository: TEMP/m06-browser-foundation-final-console.log,
  m06-android-foundation-final.log, m06-pair-final-analyze.log. No user data reset.
- M06.1 progress checkbox checked. All final sharing FR/NFR/Done When remain pending
  backend/UI/realtime acceptance. M05/M09 actual source checklist audit synchronized
  in CHECKLIST_AUDIT.md. Next M06.2: verified recipient resolver, current ACL stamps,
  actor/canonical mutation idempotency and conditional recipient feed transactions.


## M06.2 backend checkpoint

Pushed 08809ede96c37807d3b176dda601be9a1f2d879d, remote SHA verified.
75 backend checks and TypeScript typecheck passed. See SERVER_CONTRACT.md for
verified lookup/ACL/atomic actor feed and shared-route evidence and cloud limits.

## M06.3 client acceptance - 2026-10-02

- Chrome real browser56 and Android emulator56 passed. Chrome driver result true,
  failureDetails empty; real IndexedDB and native secure storage included.
- VM regression408 (+1skip), editor/UI/repository147, clean scoped analyzer and
  diff check. CLIENT_CONTRACT.md explains scope and independent live AWS gate.
- Shared With Me, role/sharer/time, owner recipients/roles/revoke UI, stable lost
  ACK retry, offline canonical editor outbox, recipient password scope and Summary
  lineage are connected. Saves compare the selected snapshot atomically and
  queue both fields together; changed editor requires explicit local/cloud review.
- Access loss clears private UI/Summary and retains encrypted unsaved evidence;
  metadata/status/delete/conflict identities cannot collide across owners.
- Final platform logs: TEMP/m06-ui-final-android.log; Playwright session m06-ui
  at localhost8773 and request_data true; TEMP/m06-ui-clean-analyze.log.
  Existing old Web output was excluded; unique output/dart-define used.
- Row rendering was extracted from list layout to keep the list file bounded;
  it preserves keys/content/layout and is covered by final UI regression.
- Tick actual Implement plan criteria FR05/06/10, NFR04/05 and recipient list
  Done When. No live AWS/AppSync claim, no M09 redesign, no data reset.

## M06.4 source/protocol receipt — 2026-10-02

- Durable EVENT stream relay, conditional lease, sparse recovery, stable event ID,
  SDK SigV4 IAM-only publish and own-sub Cognito channel handler are implemented.
- Account/session adapter refreshes ID token, keepalive/reconnect and cursor catch-up.
  No second data writer. Additive catchUpPending flag covers GSI visibility gaps.
- Acceptance: backend84/84 + tsc; VM protocol14; real Chrome14 and Android14;
  scoped VM280 (+1skip), root analyzer clean and diff check pass.
- Android initial system-TEMP rename error and later shared-hook lock timeout are
  excluded setup attempts. Final build used task-private ignored TEMP, 496 seconds,
  then installed with --no-uninstall and all14 passed. No native source changed.
- Notion M06.4 source/protocol milestone recorded; full realtime rubric still
  awaits actual two-client local acceptance and the separate AWS/Cognito live gate.
- M06.5 synthetic two-client HTTP/socket fixture is prepared, outside this source
  checkpoint. No AWS deployment or collaborator branch integration occurred.
