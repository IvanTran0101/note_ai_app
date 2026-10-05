# M03 media and binary lifecycle

## Boundaries

Application owns fresh note/session/access/protection guards and scoped streams.
Infrastructure implements picker, encrypted cache, HTTP and platform media/export
ports. Presentation renders transient handles; it never imports Infrastructure.
One canonical Note writer/outbox/cursor remains authoritative for the manifest.

Selection requests at most256KiB from XFile at a time, including on Web where
cross_file converts an entire requested Blob slice into an ArrayBuffer. Source
buffers are erased after consumption. Android plugin-created selected copies
inside the confirmed private app cache are released after staging/rejection;
original user files and cache folders are never deleted by that callback.

## Preview

- JPG/PNG/WebP: bounded10MiB collected preview and1024px decoded cache target.
- TXT/CSV: at most64KiB text prefix, no active document execution.
- Android video: random transient capability on a loopback Range server. Each
  authorized read streams at most256KiB; close aborts reads and shuts the server.
- Android PDF: pdfrx2.6.5 custom read callback, no whole-file disk cache,16MiB
  rendered-image cache. Links/context-menu exports are disabled in this preview.
- Chrome video/PDF: a child service worker controls only attachment_media/.
  Requests go through MessageChannel to fresh Application guards. Video uses
  native controls; PDF uses locally bundled pdfjs-dist6.4.299, bounded Range,
  one canvas of at most4Mpixels, no PDF scripts/forms/links/download actions.

The child worker precaches public viewer/PDF.js assets only. Private content,
capabilities, passwords, JWTs and grants never enter CacheStorage. Private offline
bytes remain in the account-scoped encrypted IndexedDB cache. Losing a transient
worker capability requires reopening the preview under fresh authority.

## Export and progress

Owners require both attachmentRead and export. Viewer/Editor may only preview.
Cloud export reads request mode=export and the backend verifies both scopes
before/after reading bytes. Native Android29+ writes256KiB into a pending
MediaStore Downloads/NoteFlow entry, publishes only after exact size/final guard,
and removes incomplete entries on failure/cancel or recovery. Completed deliberate
exports are retained. Other native platforms report export unavailable; the
accepted target scope is Chrome and Android. Chrome uses a controlled explicit
download action and the browser's stream/download UI.

Per-file events report upload/verify/association phases and Reading/Saving byte
positions, including cache hits. Pending is durable local staging; Awaiting note
sync is optimistic manifest; Ready requires authoritative association ACK.

## Cancellation and removal

Cancel aborts reads/uploads, deletes local bytes and retains a tiny remote intent
until acknowledgement. Removal first persists a binary-only removing intent,
then uses the canonical fresh Note writer. Only after local commit are ciphertext
chunks deleted and remote cancellation retried in the background. Crash/local CAS
failure cannot resurrect Pending. Unlink ACK is required by the backend before
canceling a linked attempt. An explicit authoritative cloud restore retains its
immutable object. No speculative final-object deletion is implemented.

Lock/logout/expiry/revoke invalidates preview/read capabilities, clears displayed
plaintext and closes handles. Durable encrypted data/drafts remain recoverable
under the existing M05/M06 rules. Each future Range request rechecks authority;
bytes already authorized and delivered cannot be recalled.

## Evidence status

Adapter/source receipts and actual Chrome/Android QA are tracked separately in
CURRENT_WORK.md and the M03 Notion progress page. This document describes source
behavior, not deployed AWS or full human UI acceptance.
