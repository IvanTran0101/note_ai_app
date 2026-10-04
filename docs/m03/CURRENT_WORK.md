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
256KiB writes (no Activity pause); other native Save picker fallback. Web controlled-host download stream. Explicit export
scope AND attachmentRead are required, recipients denied. These adapters are
PLANNED, not implemented/accepted. UI still baseline Pending panel. Inspect/fix
protected picker lifecycle and same-resource reauthorization before accepting.

Next: abort/progress and cache reader lifecycle, bounded media/export adapters,
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
