# M03 completion — active work

## Current continuation — 06/10 offline create ACK UI QA

71a2795 pushed/remote verified; matching APK35.8s/sourceDirty=false, SHA256
8EEFF9312F50824B878AA29F689A3F4E83EA8EEC5C15BE7F23E3C4939E5B822B.
Actual native protected TXT export75bytes matches original SHA2569D467DD5...;
receipt under ignored output/playwright/m03-20261005. Runtime restart retains
actor fixture/profiles/AVD data. Android new QA-M03-Native-Offline explicitly
saved offline (Wi-Fi/data off, ADB reverses removed), Documents multi-select
JPG/TXT/27.2MiB MP4 all Pending. Cold app restart retains all3; JPG pixels and
40s large video render/play/seek offline. Reconnect/reverse8796+8797 and canonical
create ACK then automatic retries yield3 Ready/All synced, body preserved.

Confirmed presentation defect: pre-create ACK retry throws generic StateError,
displaying invalid-file/quota advice despite a normal local-first waiting state.
Added provider-neutral AttachmentAwaitingNoteSync, no-error catch and normal
waiting notice. New focused2 regressions plus application/transfer VM29/Chrome29
passed; scoped analyzer5 items clean58.4s. Publish accepted waiting-state fix;
first VM invocation rebuilt Windows native hook (~216 compilation units), not a
loading defect. No new fix acceptance/push until receipts. Native UI currently
71a source; matching pending-notice APK after regression/push. Large full export,
picker invalid/cancel/gallery/camera matrix continue. Native large export
28,511,765bytes SHA25639E568A5... matches original; Keep/Remove TXT confirmation
reaches2 Ready/All synced with body retained. Actual invalid native picker rejects
bytes but feedback is absent after lifecycle; fix next. Chrome owner
closed during TXT download; no browser/export receipt from that interrupted run.
Graph connector recovered but generation02/10 stale/untracked for M03, exact
source fallback used. `_agent_ops/` still absent; this file is continuity.

Owned runtime fixture26508; Web11717 stopped to serialize Flutter testing.
AVD emulator-5554 online with data preserved. M09 stays deferred.

## Current continuation — export forwarding QA fix

d45e02a is pushed/remote verified. Its APK built94.9s, sourceDirty=false,
SHA2562120A0B13B0DC502F93B7F2505B612B3B0DD70AA6F6BA09D3207BD250342E8A8;
install-r/cold start preserved data. Native old Pending PDF auto-ACKed, now8
Ready across devices. Cold owner Download controls exist. Actual recipient
Viewer/Editor attachment read-only, protected WebP render; role change/revoke
while preview open closes preview/masks contents. Native protected TXT preview,
MP4 actual play and seek15s end→5s, preserved full body verified in UI.

Confirmed next bug: NoteSecurityRuntime.attachmentGrant denies export even
for owner with export scope; protected remote/cache-miss export fails. Added
owner-only export forwarding, preserving fresh session/access/protection checks.
New4 regressions: protected/unprotected owner, recipient denial, lock/session
fences. Corrected HTTP mock Unicode response with Response.bytes; red run2
owner failures/2pass proves whitelist defect. Fixed VM22/22 pass across4 targets.
Direct Flutter Chrome launches stuck at loading; diagnostics confirmed existing
Windows test-server URI defects (CanvasKit404 and missing backslash selector).
Use existing tool/run_chrome_tests.py --aggregate overlay; installed SDK unchanged.
Own headed browser sessions closed (profiles retained), emulator stopped after
native media receipt for resources. Correct runner Chrome22/22 and latest
VM22/22 passed after initializing masked protection metadata in the new-device
fixture before unlock. Scoped analyzer2 items clean66.5s. Publish this accepted
fix batch, then matching APK install-r.
Continue actual
native/protected Web export hash. Final large/offline/picker/permission/remove
matrix and full current regression remain pending. M03.2–5 source/local progress
ticks now recorded; full UI/M03/AWS live not ticked. M09 deferred.

Runtime fixture7293; Web98124 stopped; emulator stopped, keeps app/data. Browser
m04-owner/m04-recipient closed for test resources. Open retained profiles after
matching APK build and new Web startup. Unrelated macOS72E079... unchanged.

User request05/10/2026 authorizes finishing M03 after accepted M04. Baseline
final-tuankiet82625b0; retain unrelated macOS generated file, .playwright-cli/
and final_project.md. R: aliases this D: checkout. M09 deferred.

Notion progress (verified directly under final flutter):
https://app.notion.com/p/3eff9c7a1aa08170856afa612fd3f271
Source plan: https://app.notion.com/p/3eff9c7a1aa080e5979ec1122d5cc88f
Rubric: https://app.notion.com/p/3e9f9c7a1aa080ec8394d4390367e266

## Audit

Existing foundation has encrypted256KiB staging, quota/type validation, M05
scopes and canonical atomic manifest writer. Runtime upload throws unavailable;
backend rejects all manifests; remote reader is not composed; UI only previews
Pending images/text for owners. No durable server attempt/verified association,
video/PDF/export or full cache lifecycle acceptance exists yet. The indexed
graph generation02/10 predates these files; reported not-tracked/changed source
is read directly. `_agent_ops/` remains absent.

## Checkpoint — M03.1 contract and backend foundation

Policy/contracts frozen in CONTRACT.md. Server now implements durable attempts,
quota CAS, version-pinned staging/final verification, authenticated bounded Range,
atomic association/unlink via the existing sync transaction, legacy preservation,
manifest-aware fingerprints and metadata masking. CDK composition is source only;
upload origins must be configured by the AWS operator. New dedicated attachment
tests18/18 (12 authority/transaction +4 SDK/CDK +2 prior storage-template) passed.
Fresh combined backend80/80 passed, TypeScript clean. No browser/
Android attachment Ready claim yet. Client transport/cache/UI remain next.

## Current step

Client transport/cache now has bounded upload, sparse encrypted remote Range,
durable cancellation intent and Ready after server association. Binary DEK is
independently wrapped inside the M05 envelope and atomically rewrapped with
protection changes; v1 packets migrate before administration. Fresh VM attachment
+security75/75 and Chrome13/13 passed, including offline enable/change/disable,
restart, legacy conversion, failed key CAS and remote reset denial. Backend83/83
and TypeScript passed with cancel-before-begin and fresh-epoch retry coverage.
This is adapter/source acceptance; IndexedDB/UI/Android acceptance remains next.
Accepted/pushed/remote verified:9a10b86c74ddc9108bf4a9d9510c6cdf44b1c3a2.
Current batch adds AbortableRequest timeout/access-loss cancellation, fresh
association checks during cached reads, full-read checksum and faster cancel
cleanup. Chrome23/23 passed, including2 real IndexedDB reopen/offline password/
concurrent reservation scenarios. Backend86/86 and tsc passed after adding pinned
staging-expiry recovery without duplicate quota; transient lookup preserves ACKs.
Fresh broader VM79/79 passed with2 browser-only skips. Chrome23/23 covers those
IndexedDB scenarios. TypeScript and scoped analyzer are clean after style fixes.
This batch is adapter/source acceptance; full UI/platform matrix remains next.

## Planned media/export adapter boundary

Application supplies scoped bounded reader/session ports. Presentation receives
ephemeral media handles and never imports Infrastructure. PDF: pdfrx custom read
callback (official2.6.5 API verified) to avoid needless whole-file buffers.
Native video: transient random-capability loopback Range server; Web video:
worker scoped attachment_media/ with a controlled iframe host, MessageChannel
reads through Application, bounded256KiB stream, no credentials/storage URLs in
the media URL and no persisted plaintext. Separate child worker scope preserves
the main app's worker/offline behavior. Native owner export: Android29+ MediaStore Downloads with pending entry and
256KiB writes (no Activity pause); other native platforms report unavailable (Chrome/Android are the target scope). Web controlled-host download stream. Explicit export
scope AND attachmentRead are required, recipients denied. These adapters are
implemented in an unaccepted working batch: pdfrx2.6.5 dependency, Application
scoped media handles, native bounded loopback video, child Web worker/host,
separate export read scope/backend mode and Android pending MediaStore writes.
Scoped analyzer found one Web JS interop type error and style items; now fixing
those and adding close/cancel of actual reads, worker registration ACK and
abandoned pending export cleanup added. Application media tests4/4 passed within
the33/33 selected VM suite; export backend18/18 passed, tsc clean. A broader
attachment/protection/sharing/sync selection62/62 passed (not all backend suites).
Pending new tests: native real loopback Range/wipe/close, reader abort/export.
UI source is now split into panel state/actions/rows/preview and native/Web
rendering surfaces: shared read, owner controls, per-file upload progress, Ready
after ACK, confirmed cancellation/removal, media/PDF/export and plaintext cleanup.
THIS UI BATCH IS UNACCEPTED. Analyzer/tests and actual runtime still pending.
Web pdfrx custom reader is unimplemented in2.6.5; Web PDF uses locally bundled
Mozilla pdfjs-dist6.4.299, Range with disableStream/disableAutoFetch, no PDF script/
links/forms/download UI, one bounded canvas. Native uses pdfrx custom reads.
Inspect/fix
protected picker lifecycle and same-resource reauthorization before accepting.

Recovery/cache checkpoint c205288 is pushed and remote-verified. Next: media lifecycle/UI,
then full UI and actual Chrome/Android QA. Complete IndexedDB, retry/lost-ACK and
cleanup matrix before major milestone acceptance. Every milestone needs fresh
tests, Notion evidence and explicit-file commit/push. AWS deployment/live evidence
is separate; no operator credentials/deployment is assumed.

## Runtime continuity

Existing local fixture8796/relay8797-8798 and web8776 main_dev.dart; preserve
encrypted output/m06-local state/key and Chrome owner/recipient profiles.
Android emulator-5554, SDK D:/tools/AndroidSdk; preserve installed app data.
Prior M04 baseline VM1151/2 configured skips, browser956/1 skip, backend64
passed; do not substitute these for new M03 acceptance.

## Continuation 05/10 — current uncommitted media/removal batch

Bounded native video/PDF, Web child worker + bundled PDF.js6.4.299, owner export,
close/read abort and per-file progress/retry/Ready are implemented but unaccepted.
Public viewer assets are precached by the child worker; private bytes and
capabilities never enter CacheStorage.

Removal persists a binary-only `removing` intent before the canonical Note
writer; after commit it removes local bytes and retains `remoteCancelled`
for background server cancellation. Crashes/local CAS failures preserve the
intent; restored authoritative manifests keep their immutable objects. Remote
cancel does not block local Pending listing. Four recovery tests initially pass.

Fresh backend87/87 and tsc pass. Scoped analyzer clean after style/test compile
fixes. VM77 PASS/2 browser-only skips/1 FAIL: old media test expects StateError
after remove, but removal now explicitly closes the capability with
NoteSecurityFailure. Update the precise regression expectation and rerun.
Chrome seven-target run is still compiling native hook under D:, session67570.
Do not change Dart source while that run is active.

Avoid concurrent Flutter tests/builds: shared native hook lock caused Web debug
timeout and interrupted APK build; neither is QA acceptance. Switching D:/R:
recompiles host native assets. Keep browser/VM/Web on D:; R: for Android build.
No SDK/build-hook source change is needed.

Backend restarted preserving output/m06-local data, live session7755.
Emulator-5554 booted, M04 app/data preserved,8796/8797 reverse restored.
Web31886 exited due hook lock; APK20287 interrupted, no receipt. Start fresh
sequentially after source tests. Headed Chrome m04-owner preserves
output/m04-integration/chrome-owner but last navigation has connection refused
because Web exited. Actual new media UI QA has NOT begun.

Synthetic files ready in ignored output/playwright/m03-20261005: JPG/PNG/WebP,
TXT/CSV, fake-MIME TXT, three-page PDF,15s MP4 and40s27.2MiB MP4.
Next: correct the test after Chrome ends, review picker-owned temporary copy
cleanup/read progress, rerun suites; source checkpoint + Notion/push, then
APK/Web actual QA and full regression.

## Media source checkpoint — current acceptance

Fresh Chrome55/55 across8 explicitly aggregated browser-compatible targets passed
(including real IndexedDB and bounded Blob selection). VM81/81 with2 browser-only
skips passed before the bounded picker adapter; its new focused picker/cleanup
run4/4 passed, with one overlapping cleanup test. These subsets are not added.
Backend87/87 + tsc passed. Final scoped analyzer clean after style-only fixes.
Earlier StateError expectation was corrected to the explicit closed-capability
NoteSecurityFailure; no failure remains in these focused selections.

Picker-owned Android temporary copies now release after stage/rejection and
preserve originals. cross_file's whole-Blob slice behavior was confirmed from
installed0.3.5+5 source; selection now requests/wipes at most256KiB per call.
Reading/Saving progress includes cached reads. MEDIA.md and DEV_SETUP.md describe
source boundaries, setup, accepted target scope and separate AWS live gates.

This is SOURCE/ADAPTER acceptance, not full M03 acceptance. New actual headed
Chrome/Android media QA and full regression remain. Current APK build session43086
is running sequentially from R:; do not start another Flutter build/test/run
until it finishes. Backend7755/emulator/data remain as above. After the build,
install-r the new APK, restart Web sequentially and perform the actual UI matrix.

## Actual UI QA started —2930639

Source checkpoint2930639 was pushed and remote SHA verified. Current APK built
successfully527.3s (main_dev/android-x64), SHA256
7D6B360FEA93CCF3A1C3FD1A1E35904596D72AA5DA8385F044D6ED5E9BB7B443;
install-r and cold start retained app data. Receipt m03-apk-provenance.json.
Web64830 at8776 and fixture7755 at8796/relay8797 are running. Chrome m04-owner
with retained profile reopened current Web. Android created QA-M03-Android,
saved on Back, reopened with attachment controls; same note arrived in Chrome.
Actual file picker/media/export/offline/protected/shared QA is now in progress;
no full M03 acceptance yet. Continue from current native and Web picker menus.

## Actual QA defects — local transport / accessible iframe / Web export

Confirmed real Chrome + Android picker files remain encrypted Pending because
logical dev API composition did not enable the exact loopback staging URL.
Added explicit debug-only composition flag; dev transport accepts only anonymous
PUT to127.0.0.1:8796/dev/attachment-put with redirects disabled, and preserves
abort signals on rewritten API requests. VM16/16 + Chrome16/16 and scoped
analyzer passed. Chrome reload auto-retried all7 old Pending files to Ready after
verified upload + canonical association ACK. Android rebuild/retest pending.

Confirmed accessibility-enabled Chrome PDF controls were blocked by full-screen
barrier tap semantics merged over editor. Excluded only barrier semantics; Back
remains accessible. Actual Page2/3 click passed after bringing preview into view.
MP4 plays real15s media with readyState4; seek still pending recorded UI evidence.

Web export click incorrectly downloaded Flutter fallback HTML through a
`download`-attributed anchor bypassing the child worker. Changed controlled
iframe navigation to rely on guarded streaming Content-Disposition, bumped
public viewer cache to v2. This fix is NOT yet accepted: actual download/hash
retest pending. Fresh VM focused combined UI/composition/transfer suite running.
No full M03 acceptance yet; AWS live remains separate.

## Accepted UI fix checkpoint — awaiting commit/push

Combined UI/composition/transfer VM28/28 and Chrome28/28 pass. Actual cold Web
export retest with public viewer cache v2 downloads qa-text.txt75 bytes, no
browser failure, SHA2569D467DD58D9B40F0D2246CCC21E5660158DED08AC95F4122DB0962E63714FCF0
matches original. All3 confirmed fixes now accepted for source/focused/Chrome
scenarios. Stage only owned composition/semantics/export/test/docs files; keep
unrelated macOS bytes72E079.../.playwright-cli/final_project.md. Native APK still
2930639: rebuild after remaining browser QA/full regression, install-r and
retest Pending/protected/pickers/media/export. Full M03 remains in progress.
Runtime Web57655/fixture7755; Chrome m04-owner export preview open.

## Confirmed typed protection sync defect

2d2e302 pushed/remote verified. Actual Chrome enable protection on the7-file
note persisted local keys/content but failed422 at legacy protected-mutations.
Client typed-wire decision only checked includesLabels, while the M05 payload
includesAttachments and no labels. Added shared requiresSyncWireV2 mapper/route
decision for attachments OR labels, including empty unlink. Legacy text-only
shape unchanged. New5 route/encoding regressions + adapter/security VM47/47 pass.
Full VM and all backend suites now running sequentially with Web stopped.
Protected Pending retry on fresh browser, full Chrome and Android remain next.
Web57655 stopped; fixture7755 remains, profiles/data preserved.

## Fresh full regression / current runtime — continuation
Full VM1190/4 configured skips, all15 backend files87/87 +tsc and dev config14/14 pass.
Full Chrome123 compatible targets: app342 +storage408 +UI305 =1055 PASS/1 real-model skip/0fail.
Real M03 IndexedDB and Web canonical encrypted store included; focused subsets not added.
Analyzer26278 running; Web stopped, backend7755 live. Restart Web after analyzer,
retest old local protected Pending with corrected typed v2 route; seven attachments
must retain keys/data. Android still293 APK; incoming Ready rows uncertain until
proper scroll/current build. Rebuild/install-r after Web acceptance. No full M03 yet.

## Actual rejected protection recovery — new confirmed issue
Web restarted94382; original QA-M03-Android local protected note retained7 Ready.
Cold unlock works. Explicit Sync protection only clears forbidden/null blocks,
not historical invalidMutation422; fresh edit remains behind blocked predecessor.
Added bounded explicit owner protection+attachment retry; automatic unlock/ordinary/
shared invalid writes stay blocked. Stable ID/payload/retryCount retained. New2
regressions test explicit retry preservation and no automatic retry. Initial test
load lacked extension library import (harness compilation), corrected. Focused
VM89807 running; Web stopped exact scoped PID31328 (non-TTY stdin was closed).
Actual native manifest7 confirmed after correct editor scroll; JPG/PNG render.
No stale-manifest product defect. Backend7755 retains data. Restart Web with tty
next, retest original rejected queue; commit/push then APK current source.

## Resume after user-interrupted runtime
New2 recovery regression fixtures corrected (extension import/secure storage mock/
explicit typed-empty payload); focused VM11/11 and Chrome11/11 pass.
Last CLI unlock/protection retry was interrupted; no actual pass or push claim.
All runtimes stopped with interruption; restarted fixture7293 and Web76771 tty;
emulator-5554 cold boots retained data, ADB reverse restored. Profiles remain
output/m04-integration/chrome-owner and chrome-recipient. Graph transport closed,
use exact source fallback with prior stale coverage. Current Git2d2e302, typed
route/recovery/tests/docs uncommitted. Original macOS72E... preserved. Retest
original local protected Pending, then publish accepted fix and build APK from R:.

## Actual protection retry accepted; online-owner export scope issue
Web cold reload/unlock now reaches All synced with7 Ready. Original rejected
protection mutation completed during interrupted run; second ordinary text
mutation was initially403 under a predecessor grant, then full-scope refresh
retried successfully. Android independently receives protected metadata/unlocks
QA-M03-Android; cached JPG renders. Protected WebP renders expected fixture.
Cold online owner unlock lacks export scope, hiding Download on Android; added
owner-only export request and full owner scopes for predecessor/protection
retry, shared scope set stays read/summary/(editor edit)/attachmentRead only.
New first-online-owner export regression; focused VM85756 running. Web76771
stopped cleanly via q. Backend7293/emulator/data/profiles retained. Graph coverage
connector recovered, index still stale2026-10-02; exact source read for flagged.
Need focused Chrome/static acceptance, publish fixes then matching APK/new QA.

## Ready to publish protection integration fix
Focused current VM12/12 and Chrome12/12 pass; scoped analyzer7 items clean3.4s
(after unused test import removed). Original Web protected queue reaches All
synced7 Ready; Android independently receives/opens protected note. Cold owner
export scope fix is source/unit accepted; native matching APK retest pending.
Browser old loaded program stays live while Flutter tests/analyzer ran; dev
WebSocket errors after stopping server are harness state, not product failures.
Local synthetic Viewer share submitted for QA-M03-Android; inspect fresh dialog
ACK before recipient/revoke acceptance. Source/UI QA incomplete, M09 deferred.
Commit/push only owned5 Dart source +2 test +MUST/docs; preserve macOS72E...,
.playwright-cli/final_project.md. Then build R: current debugAPK serially.
