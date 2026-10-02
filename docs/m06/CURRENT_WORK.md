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
- M06.4 pushed/remote verified 315caf4a7c0fb5f678a7df5f45090428a8983015.
  M06.5 active two-client batch: Chrome owner at localhost8776, Android recipient
  uses 10.0.2.2:8786 HTTP/8787 socket. Private TEMP/native hooks now cached. Both
  test apps use separate fixed synthetic account namespaces, never real data.
- M06.5 first two-client run failed because the synthetic HTTP fixture passed
  the recipient as canonical owner to applyMutation. Production handler already
  separates canonical owner and actor; fixture now uses the same binding.
  This setup attempt is excluded, not a product ACL defect. Rerun with fresh
  synthetic fixture state, then full regression/fix and final acceptance.
- M06.5 two-client retry passed: real Chrome owner driver true/no failures and
  Android recipient1 passed; both fixture passed flags true, eventPublishes13.
  Actual HTTP/socket, local-first durable outbox, bidirectional automatic edit,
  disconnect/cursor catch-up, lost relay ACK, viewer API denial and revoke mask.
  Fixture uses synthetic identities/SDK doubles; live AWS remains unverified.
- Full VM and Chrome-compatible regression and backend/tsc are running. Added
  m06_regression_test.dart to group the existing M05/M06 registrations for one
  final real-plugin Chrome/Android run. No product assertions are changed.
- Final platform Android startup found no emulator device after the two-client
  run. Host had only587MB free physical RAM while two Web compilers and VM were
  active. The extra platform Web build completed155.6s before a guarded stop
  could run; the guard rejected an absent process, so nothing was stopped.
  Let full regressions finish, then restart existing AVD without wipe/reset and
  run platform builds sequentially. This pre-test device failure is excluded.
- Continuation03/10: full VM971 passed (+2skips). Chrome89 aggregate compiler
  exited unexpectedly during host memory pressure; excluded setup attempt.
  Retrying browser targets in three layer groups: Application/Domain35 targets
  passed232 cases; Storage/Sharing33 and remaining UI21 are next.
- User confirmed deleting C:/AndroidSdk and requested reinstall. New official
  command-line tools22 archive SHA256 verified against Android download page;
  installing D:/tools/AndroidSdk with API36 build tools/NDK28.2 and the existing
  API35 Google APIs x86_64 image/emulator. Existing NoteFlow AVD data is retained.
  Flutter SDK config + ignored local.properties point to D; no product source
  or tracked native configuration is changed. Notion connector is available
  again after plugin discovery; fresh plan/rubric/progress were fetched.
- Final Chrome regression is844 passed (+1skip) across89 original targets:
  Application/Domain232, Storage/Sharing363 (+1skip), UI249. Full aggregate
  compiler failure is excluded; grouped runs use unchanged original test mains.
  Real Chrome final M05/M06 platform integration90 passed, driver true with
  no failureDetails. Root analyzer clean (160s) and Dart formatter0 changes.
- SDK Manager installed emulator + CMake, but remaining Java download was waiting
  on TLS reads. Stopped only the verified SDK installer; direct official archive
  download/checksum verification uses HTTPS repository manifests and writes local
  package metadata for later SDK Manager validation. No AVD/data reset.
- SDK Manager --list_installed now validates all seven required packages:
  API36/build36, platform-tools37.0.1, emulator37.2.12, NDK28.2.13676358,
  CMake3.22.1 and Google APIs API35 x86_64 revision9. Existing AVD started
  without snapshot load/save or wipe; task RAM1536MB. Final Android90 next.
- Prepared LIVE_GATE.md plus a local CloudFormation resource review through
  tool/m06_cloud_review.ts. Synth uses a fictional account/pool and makes no
  AWS call; it cannot substitute for the real account/stack diff or deployment.
- New SDK booted emulator5554 (sys.boot_completed=1); final Android90 build
  is active. Gradle installed its additional API35 platform dependency. Verified
  local_llm_bridge clang compilation is running after the SDK-root change;
  preserve the task-private TEMP and let the sequential native build finish.
- Graph connection recovered: D root ready, generation2026-10-02T16:47:30Z.
  Coverage checked all five new acceptance/review code paths; four show changed
  metadata and cloud_review not_tracked. Exact source/patch fallback was read;
  no exhaustive graph or deployed-provider claim is made.
- Final Android platform90 passed after SDK reinstall: native build524s,
  all90 in6m09s, no uninstall/data reset. Chrome90 + Android90 plugin regression
  accepted. Repeated two-client HTTP/socket on the new SDK also passed: Android1,
  Chrome driver true/no failures, both fixture passed flags true, eventPublishes13.
- M06.5 source/local acceptance is complete: VM971/2skips, Chrome844/1skip across
  all89 original targets, backend84/tsc, root analyzer clean and formatter0 changes.
  ACCEPTANCE.md and LIVE_GATE.md hold reproduction/evidence and provider limits.
  Notion actual rubric/progress now15 checked/4 pending deployed realtime criteria.
  Finish plan/status consistency, explicit-stage checkpoint/push and verify remote;
  then rebuild/install main.dart APK with -r and record final receipts on Notion.
- Local sharing intents may be durable, but ACTIVE ACL is only server-authorized.
- M05 encrypted drafts/session/consent/lineage must survive all changes.
- Update/push after accepted milestone/M/P, not after partial preparation.

## Preserve unrelated work

At entry macos/Flutter/GeneratedPluginRegistrant.swift was modified (SHA256
72E079184D14D8D03E86FB8928A90BC09F21E1D871F4F4B69FFF96030E67756B).
Do not revert/stage it. .playwright-cli/ and final_project.md stay untracked.
No C worktrees, no reset/uninstall, no live deployment authorization.
