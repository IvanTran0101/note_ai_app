# M04 actual UI QA — in progress

2026-10-05, final-tuankiet. Matching local HTTP/socket backend, real headed
Chrome persistent owner profile and Android emulator-5554; installed/encrypted
data preserved. This receipt covers observed UI flows, separate from source
tests and deployed AWS acceptance.

## Accepted observations so far

- Chrome/Android each created a Label through Manage labels; the other client
  received its catalog. Android attached a Label to the existing synthetic QA
  Note; Chrome displayed its chip after a cold browser reload.
- Chrome Home list/grid: one selected Label returns the associated Note;
  selecting both Labels returns zero because membership uses ALL. Notes page
  live body keyword `cloud` plus the Android Label returns that same Note;
  adding the second unassociated Label removes it immediately.
- Android M03 picker now survives the native picker pause: Pending file added,
  encrypted text preview opened, and Retry upload explicitly reports cloud
  unavailable. This is the collaborator's partial M03 boundary.
- With Android wifi/data disabled AND loopback ADB reverses removed, the cached
  Note, chip, Pending descriptor and actual text preview remain readable.
  Cold process reopen and reconnect verification continues.
- Chrome network offline: text and Label association changes save locally and
  show durable pending changes. No cloud request is required for association.

## Confirmed fixes in this batch

1. Filtered empty Notes incorrectly said there were no saved Notes and offered
   the first-note action. Query now says No matching notes (localized).
2. Manual coordinator sync bypassed the runtime-only catalog callback. Notify
   the cache on every terminal sync result, including partial failed passes,
   guarded by the captured actor/session. No additional writer or store.
3. Dashboard selection/keyword now clears on actual actor change; temporary
   catalog loading does not discard selection. Notes wrapper does the same.

Focused query/catalog/actor widgets + terminal sync regression10/10 PASS;
dev configuration14/14 PASS. Full source regression and final actual QA pending.

Latest source1144 PASS/2 configured skips; final stale-catalog defence and Home
actor change widgets52/52 PASS. The new Home actor fixture exposed stale foreign
rows in a manually supplied catalog; filter and manager now also enforce owner
scope directly. This does not replace source session/store fences.
Chrome duplicate-name creation and associated Label rename propagated immediately
to the selected filter and Note chip. Native cold reopen without loopback retained
Pending bytes and opened the real preview; restoring loopback/network and Retry
pulled the Web text change while keeping the local Pending file. Old native APK
did not refresh renamed catalog after manual sync: rebuild contains the observer
fix and must be retested before final acceptance.

## Harness/development artifacts

Hot-restarting Flutter Web while keeping an old DDC page produced disposed-view
and duplicate module errors. Cold restarting the server and reloading Chrome
restored a clean app runtime. Offline request failures are expected network
events. Use fresh snapshots after dialog selection; the chooser closes when
an association is saved. For Flutter text use real keyboard select-all/type;
DOM fill can append to Flutter's existing controller text.

## Remaining acceptance

Duplicate/rename/delete with chip propagation, offline cold reopen/reconnect,
protected/shared privacy and owner-only organization, retained drafts, final
regression/analyzer/APK revision, collaborator/canonical Notion ticks and push.
M09 and live AWS deployment remain outside this implementation batch.

## Latest regression fixes and receipts

- Final current source1146 PASS/2 configured skips, analyzer clean61.0s;
  focused Label/query/privacy widgets5/5 and security+Label UI9/9 PASS.
- Chrome physical pointer + native keyboard reached No matching notes immediately
  (screenshot query-pixel-no-match.png), then live body matching. Pure query made
  no HTTP request. Accessibility input originally inherited the whole Notes-area
  geometry/name; a bounded explicit semantics container now gives the input its
  own53-pixel rectangle/Search notes name. Regression asserts bounded geometry.
  Locator keyboard typing into an accessibility proxy may not dispatch a Flutter
  edit; real pointer activation targets the native editing element.
- Native duplicate catalog rows, rename, deletion and selected tombstone pruning
  passed. Associated deletion preserved Note/body/pin. Chrome manual Sync now
  removed the deleted chip while the editor remained open, validating the cache
  observer fix against a Note whose revision did not change.
- Native new synthetic Note with Label protected online, locked with no title,
  body or chip exposure, reopened cold with backend loopback removed. Wrong
  offline password was rejected; correct cached offline unlock restored body and
  Label. Offline edit was saved explicitly on Back, as encrypted pending content.
  Reconnect requires online scoped unlock before sending that protected edit.
- Native password administration uses the existing server-first M05 composition
  (`localFirst: kIsWeb`). Offline administration returns unavailable and retains
  data. This is outside the approved Web-only password administration correction;
  M04 query/cache and encrypted offline Note edits remain local-first.
- Regrant as Viewer displayed the unchanged cloud body, not the old-grant draft;
  blocked encrypted pending draft remains retained. Revoked unprotected share
  previously incorrectly described that draft as an old-password draft. Copy now
  describes earlier access; independent widget regression covers it.

Final rebuilt Android search geometry, protected reconnect and final handoff
receipt remain; do not treat this running journal as completed actual QA.
