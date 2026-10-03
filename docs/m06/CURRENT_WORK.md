# M06 current work

## Latest active integration — 2026-10-04

M02 aabf229 integrated with M05/M06 on final-tuankiet, starting276c749.
True merge parents preserved; isolated source delta after6ce2afe used to resolve
historical overlap while retaining our newer Summary/security implementation.
Read M02_INTEGRATION.md. Real defects fixed: Summary final-read session check,
shared role labels in animation, null pending unpin hydration, legacy shared pin
bypass and queued same-user preference fence. Inner schema4/outer crypto packet3.

Fresh receipts: VM1029/2 configured skips; Chrome902/1 skip over98 targets;
real Chrome100 (valid driver true/no failures) and Android100 (383.2s build,
5m25s tests, --no-uninstall), backend89, tsc/final analyzer clean, formatter91/0.
Final VM delivery rerun1029/2 skip passed after the last header transition;
Windows errno32 fixture teardown has bounded path-checked retry, scoped analyzer
clean. Application source stayed unchanged after platform acceptance;
source staged explicitly, no conflict marker/unmerged paths/secrets signature.
Android emulator and browser test session closed after completion; AVD data kept.
Graph transport/coverage unavailable; exact source fallback. Ops folder absent.
MacOS file hash and unrelated untracked files preserved and excluded from staging.

Source merge commit: `2c0397c688f5573c79fb76a9f66786755edac2b8`, with parents276c749 and aabf229.
VM delivery1029/2 skip is final; all local receipts complete. Notion records the
final remote branch SHA after publication. Next: M03 collaborator should sync
this checkpoint for the named writer/schema4; M09 remains deferred. No provider
acceptance or attachment byte/scopes completion is implied by this batch.
Notion: https://app.notion.com/p/3eef9c7a1aa081d2a7c4ee37adefbb38.

## Latest batch — M02 compatibility review (2026-10-04)

User authorized pulling/checking final-TanMinh against M05/M06 for the M03
handoff. Fetched fixed aabf229; app source still fcb4a54, no MERGE_HEAD or index
conflicts. Ordinary merge-tree96 paths; isolated M02 delta against6ce2afe25.
Exact source + executed parser probe confirm pin is dropped and writer/schema/
access/Summary integration remains pending M02.4-M02.6. See
M02_COMPATIBILITY_REVIEW.md for evidence, paths, commands and continuation gates.
Graph transport unavailable; source fallback used. No integrated platform PASS.
Review is published and re-fetched on Notion M02 and the collab2 index; existing
milestone/runtime boxes stay pending. Scoped docs checkpoint preserves unrelated
macOS/untracked files. Next source step is M02.4-M02.6 conflict resolution and
integrated regression; that implementation is not complete in this review.

User resumed 2026-10-02. Primary D checkout, final-tuankiet@c3436d5 baseline.
Active scope M06.2–M06.5, local-first; M09 deferred until both collabs finish,
their work is integrated/tested together and a new UI/UX plan is prepared.

Read MUST_REMEMBER.md, CONTRACT.md and PROGRESS.md at continuation. No goal or
subagents; graph Tier2 exact D root. _agent_ops tools are absent.

## Current batch

- Active follow-up: user cannot Share with plain flutter run -d chrome.
  Verified root: plain command uses older generated Cognito configuration;
  local mode deliberately has no Share gateway. Prior config/startup checks
  did not prove manual Share. Add an explicit debug-only main_dev entrypoint,
  two isolated synthetic actors, loopback persisted backend and one launcher.
  Reuse production application/store/ACL and cursor pipeline. No AWS deployment,
  credential request, M09 work, real-data reset or live-rubric completion.
  Next: prove owner Share -> recipient editor -> downgrade/revoke in actual UI.
- Main dev UI now runs through run_m06_local.py: fixed synthetic actors and
  debug-only loopback client, encrypted disk SDK-double backend, production
  store/ACL/password use cases and AppSync protocol fixture. Root token/client/
  revision collaborators are injectable; Cognito defaults remain intact.
- Actual browser proved owner creation/share, recipient Shared with me/editor
  write, explicit stale editor review, owner reply, Viewer update and revoke
  removal. Offline owner save shows one durable pending change after explicit
  local review. HTTP10 auth/origin/host/revoked-access/disk checks and Python13
  config checks pass. Scoped VM15 passes; matching Chrome15 is running.
- Fixed three observed main UI defects: initialize restored-identity sync before
  router mount; constrain long page status; clear stale error on Use cloud.
  Root analyzer passed before the latter two fixes; final analyzer is next.
  No M09 redesign. Next: online ACK, reload/restart persistence, final fresh
  main Chrome run, docs/Notion and scoped checkpoint push.
- Final follow-up accepted locally: online ACK automatic, restart retains
  revision4/offline content, installed Chrome fresh profile retrieves note.
  Re-shared the demo as Editor after proving revoke (fresh accessRevision4).
  VM15/Chrome15/HTTP10/config13 passed; tsc, Python compile, formatter/diff and
  final analyzer164.2s clean. Notion progress/plan/actual rubric updated with
  the explicit local runtime distinction; live15/19 status is unchanged.
  run_m06_local.py launched installed Chrome successfully; helper responsibilities
  are split into service startup, Flutter launch and owned-service cleanup.
  Next: verify scoped staged files, commit/push and keep local app running.

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
- Follow-up03/10: user shared collaborator's request to prepare code/config before
  credentials. Add .env.example and local Python config/child-environment helper,
  public Amplify outputs override at composition root and scoped boundary tests.
  Existing backend/realtime code is reused. Prepare local-first config without
  AWS calls; no own dev account is available and no live criterion is ticked.
  AWS credentials must never become Flutter defines, assets, logs or Git files.
  Helper13 checks, default/selected root configuration VM2 and Chrome2 passed;
  scoped analyzer clean155.7s, formatter/diff pass. DEV_SETUP.md and acceptance/
  progress records updated. Local ignored .env created with blank operator fields;
  R alias restored to the primary D checkout. Next: Notion/source checkpoint push,
  build/install a local-mode main APK from that commit and record its receipt.
- M05 encrypted drafts/session/consent/lineage must survive all changes.
- Update/push after accepted milestone/M/P, not after partial preparation.

## Preserve unrelated work

At entry macos/Flutter/GeneratedPluginRegistrant.swift was modified (SHA256
72E079184D14D8D03E86FB8928A90BC09F21E1D871F4F4B69FFF96030E67756B).
Do not revert/stage it. .playwright-cli/ and final_project.md stay untracked.
No C worktrees, no reset/uninstall, no live deployment authorization.
