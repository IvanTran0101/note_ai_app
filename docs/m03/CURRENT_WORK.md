# M03 completion — active work

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
