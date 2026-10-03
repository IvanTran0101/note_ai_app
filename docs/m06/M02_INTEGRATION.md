# M02 + M05/M06 integration receipt

Date: 2026-10-04 (Asia/Saigon). Delivery branch: final-tuankiet.

## Revisions and scope

Incoming final-TanMinh: aabf2294cdf882b9110971345d5f574a8d98e6c0.
Our starting HEAD:276c7493e9d12365cdfa4c1187ef47daece16e32.
This receipt supersedes the review-only checkpoint in M02_COMPATIBILITY_REVIEW.md.
M03 implementation and M09 redesign remain deferred to their owners/planned work.

A real merge was started with the actual Git ancestor6233e168. It produced96
historical conflicting paths, including older overlapping Summary/sync work.
The M02 source delta after shared source baseline6ce2afe was isolated (74 paths;
25 diagnostic conflicts). Resolution retained our newer M05/M06 and Summary
implementation while porting that M02 delta. The integration commit has both
actual branch parents;6ce2afe was not substituted as Git ancestry.

## Integrated boundaries

- Domain Note retains protection/share/content lineage and gains UTC pin,
  nonblank new-write validation and no-op text/pin behavior. Legacy restore
  retains historical text/timestamps.
- All production text/pin/editor use cases use the named canonical owner/note,
  actor and synchronous fresh-instance writer. One existing store transaction
  writes Note and outbox, with session/access/caller fences and full editor
  compare. Legacy saveSnapshot remains a compatibility adapter to that same
  storage lane and now also compares pin; direct shared save cannot change pin.
- One NoteDto projection serves Domain/local state and Summary. Saved snapshot
  comparison includes pin, dates and M05/M06 lineage, with consent/session and
  access rechecks. A logout during final Summary read returns sessionChanged.
- Pin survives local metadata, payload, ACK/pull/conflict, encrypted vault and
  hydration. Omitted pin preserves old request fingerprints; explicit null
  unpins. Attempted requests are frozen. Shared editor payload omits pin;
  backend rejects shared pin and requires owner manage capability for pin.
- Local inner schema is4. Both published v3 shapes and strict v2 migrate in
  memory, preserving prefs, IDs, queued bytes, revisions, conflicts and cursor.
  M05 encrypted packet/AAD remains version3 with the existing device key; it
  is independent of inner schema4. No cache reset or plaintext fallback.
- Account layout preferences use the existing encrypted atomic envelope and
  session fence. Sync/security transforms retain them.
- M02 autosave, retry, transitions, pin ordering and Grid/List are combined with
  existing protected/shared UI, stale editor review and encrypted retained
  drafts. Shared Viewer/Editor metadata remains visible in animated rows;
  outgoing rows cannot act and revoked shared plaintext is masked immediately.

## Confirmed defects fixed during regression

| Finding | Fix / evidence |
| --- | --- |
| Pin accepted but discarded by parser | Strict nullable UTC pin payload, mapper/store/snapshot contract tests |
| Concurrent writers / stale editor | Fresh named writer, full snapshot comparison and fences |
| Incompatible same-number v3 schemas | Distinct v3 shape migration to inner4; real encrypted reopen |
| Logout during last Summary read reported wrong error | Recheck captured run context immediately after await |
| Shared role label lost while porting animated list | Restore role/access metadata, canonical row keys |
| Pending local null unpin overwritten by remote pin | Keep local pin including null during pending hydration |
| Direct legacy shared save could alter owner pin | Enforce manage policy on changed pin in compatibility save |
| Layout queued callback from same-user former session | Repository session generation fence |

Initial failures also included old schema assertions, old compact-layout
expectations, a v2 fixture containing newer fields, and a lazy store fixture.
They were corrected to the integrated contract. A broad browser runner initially
included6 direct native IO/isolate test files (88 UnsupportedErrors); those files
are covered by VM. A blank request_data message caused one invalid browser driver
receipt; rerunning without message yielded result=true and no failureDetails.
The first final VM delivery rerun had one Windows errno32 teardown failure after
all product assertions passed. The private TEMP fixture cleanup now validates
its resolved root/prefix and retries only that transient error up to6 attempts;
other failures still surface. No application storage behavior was changed.

## Fresh execution

| Run | Verified result | Local log |
| --- | --- | --- |
| Full VM test/ |1029 pass,2 configured skips | output/m02-integration/full-vm-delivery-final.log |
| Backend10 targets |89 checks pass (49 Node entries minus4 file runners plus44 internal checks) | backend-final.log |
| Strict backend tsc | exit0 | typecheck-final.log |
| Chrome Application/Domain36 original targets |241 pass | chrome-application.log |
| Chrome Storage/Sharing35 original targets |380 pass,1 configured skip | chrome-storage-final.log |
| Chrome platform plugins |100 scenarios pass; log101 includes framework teardown; driver true/no failures | platform-chrome-result-final.log + console-2026-10-03T19-14-54-027Z.log |
| Chrome UI27 original targets |281 pass | chrome-ui-final.log |
| Android real platform plugins |100 pass;383.2s build,5m25s tests; no uninstall | platform-android.log |
| Final root analyzer | exit0, no issues | analyze-final.log |

Chrome unit totals902 pass/1 skip across98 compatible original targets.
Owned Dart formatting:90 files,0 changes; no staged conflict markers or secret
signatures were found.

Chrome platform uses actual Chrome/IndexedDB/device key custody; Android uses
existing NoteFlow_API35 and SDK D:/tools/AndroidSdk, no wipe/uninstall. Platform
suite extends90 original M05/M06 registrations with8 M02 core and2 real store
scenarios. Network/provider collaborators within these tests are doubles.
Existing deployed Cognito/AppSync acceptance remains a separate gate.

## Reproduction and collaborator handoff

- flutter test --no-pub --reporter expanded
- Browser groups: tool/run_chrome_tests.py --sdk C:/Users/meow/flutter --aggregate
  with browser-compatible original mains (exclude direct IO/isolate targets).
- flutter build web --debug --target integration_test/m06_regression_test.dart
  --output output/m02-integration/platform-web --no-pub --no-wasm-dry-run;
  loopback HTTP8766 + installed Chrome. request_data omits message, then read
  $flutterDriverResult and require isError=false/result=true/empty failureDetails.
- flutter test integration_test/m06_regression_test.dart -d emulator-5554
  --no-pub --no-uninstall (run native builds from verified R: checkout alias).
- npm run typecheck; node --import tsx --test followed by the10 backend targets
  listed in output/m02-integration/backend/results.json.

M03 should first sync this delivered integration, then use named updateById and
preserve schema4 pin/preferences/security/access fields. Attachment bytes/cache/
scopes remain the agreed M03 contract; this batch does not implement them.
Backend compatible rollout precedes the client when deploying. Read DEV_SETUP.md
for local synthetic two-user runtime and LIVE_GATE.md for provider acceptance.

Graph index_status/check_index_coverage returned Transport closed; exact source,
Git diffs and executed tests supplied evidence. Ops folder/protocol remains
absent; CURRENT_WORK, MUST_REMEMBER and this receipt hold continuity.
Unrelated macOS generated-file SHA256 stayed
72E079184D14D8D03E86FB8928A90BC09F21E1D871F4F4B69FFF96030E67756B.
User untracked files and local runtime outputs are excluded from source delivery.

Notion receipt: https://app.notion.com/p/3eef9c7a1aa081d2a7c4ee37adefbb38.
## Delivery record

All application source is staged explicitly; no unmerged paths or conflict
markers remain. Formatter91 files/0 changes, backend89/typecheck and final
analyzer clean. The final VM delivery rerun passed1029 tests/2 configured skips in1m29s;
fixture follow-up analyzer is also clean.
Source merge commit: `2c0397c688f5573c79fb76a9f66786755edac2b8`, verified parents276c749 and aabf229.
The following documentation checkpoint records closure. Delivery is a normal
push to refs/heads/final-tuankiet; the final branch SHA is recorded on Notion.

## Continuity closure

| Record | Action |
| --- | --- |
| MUST_REMEMBER.md | Active integration and accepted local/source checkpoint |
| docs/m06/CURRENT_WORK.md | Final scope, receipts, preservation and next handoff |
| docs/m06/M02_INTEGRATION.md | Conflict resolutions, migration, test and delivery receipt |
| _agent_ops records | Not needed: folder/protocol absent in this checkout |
