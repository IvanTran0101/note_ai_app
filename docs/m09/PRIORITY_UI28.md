# Label, attachment and editor controls — UI round28

## Latest continuation —22 October, candidates29–33

Priority Label/File/Add/Undo/Redo presentation is implemented and exercised.
Main Notion ticks for those three UI items are now checked with bounded receipts;
the separate review/push item is still open. Both whole-platform95% gates stay
unverified. Existing attachments remain note metadata, not document blocks.

29 removed the generic Web semantic tap node: actual Chrome pointer now reaches
the iframe with accessibility enabled. Focused Chrome14/14 passed with no skips;
its aggregate was restored. 30 root focused VM rerun16/16 passed, including
native style properties and the unchanged desktop/Web branch. Initial authored
style tests restored a debug platform variable too late; root fixed finally
cleanup. An initial CLI target had the wrong labels directory; corrected full
six-file rerun passed. These were harness/test errors, not product failures.

31 runtime1053 paths65e9ce70...e6070, analyzer clean91.7s; Web82.7s/APK39.3s,
drift[]. APK9932dee6...c9fdb is byte-identical to installed30, device SHA matched.
Actual FIRST file open through v4->v5 upgrade showed current Light CSS and48px
button; normal mouse click with semantics downloaded exact67B/96fbf4c9...ecc7278,
failure:null and page/console errors[]. Same iframe retained identity when
Settings changed Light->Dark; actual button/background colors changed correctly.
29/30 exposed stale-worker/CSS upgrade races before that fix. 31 awaits update
settlement then activation; public asset cache reloads current bytes. Offline
update rejection can retain an already activated worker. A later replacement
after handle return still fails closed/reopen; no atomic handshake is claimed.
Root split bridge registration/URI/cleanup helpers in32; analyze70.9s and Web71.7s/
APK45.2s passed, drift[]. No access, capability, sandbox or byte-cache bypass.

Native29 file/menu at200% system text is readable, no overflow; file and More
48dp at font1. Native30/31 longpress now shows range handles, but dragging did
not change range and hid formatting rail. This remaining M09 UI issue is under
diagnosis, not a pass. TEMP pan logs in32 asserted bodies produced no evidence;
33 kDebugMode service.init appears, but neither parent nor child pan callback
logs appeared for the attempted handle drag. Parent recognizer hypothesis is
therefore unconfirmed; inspect transformed hit bounds/ancestor routing next.
All TEMP M09_HANDLE diagnostics must be removed before committing those files.

Actual app31 Web/file and native30/31 file images are attached to the comparison
board (now17 images/1 childpage, preservation fetched). Progress updates and main
three priority ticks succeeded. No whole-platform percentage assigned.

## Scope and reference

User priority: finish the existing Label/File/Add block/Undo/Redo presentation,
then resume the remaining M09 reference work. Both overall Web/Android >=95%
similarity gates remain unverified. This is not functional acceptance.

Direct reference inspection on22 October2026:

- Notion Web, current synthetic QA page, dark,1280x720: flat icon/name/size file
  row; contextual file menu includes Download/Delete and other Notion-only
  actions. Only the existing NoteFlow actions are retained.
- The current idle Page Actions > More submenu did not show Undo/Redo. Earlier
  history observations are state-specific; do not claim all menus show them.
  NoteFlow keeps its existing Web history available through its own More menu.
- Notion Android0.6.4222,1080x2400,420dpi, Light, gesture: its editor rail puts
  Redo before Undo; + opens Basic blocks and Media > File. The normal picker
  uploaded only `m09-ui-sample.txt` (67 synthetic bytes, no personal data).
  Its visible file row is flat with filename and muted inline size.
- The inspected independent-page state has no matching Label area. Existing
  NoteFlow labels use a minimal neutral adaptation; no database is added.

Reference captures in ignored `output/m09/`:
`notion28-web-file-reference.png`, `notion28-web-file-menu-reference.png`,
`notion28-web-history-reference.png`, `notion28-edit.png`,
`notion28-add-block.png`, `notion28-block-files.png`,
`notion28-file-picker.png`, `notion28-file-reference.png`.
Early WebView XML retained Uploading after the PNG already showed the file;
use the stable PNG and later file-button XML, not stale upload text.

## Implementation and review

- Labels/files are visible below the document, outside the folded Note details
  group. They are not a new document block or a storage/schema change.
- Neutral bounded label chips, inline chooser and quieter manager preserve
  create/rename/delete/attach/detach, actor fences and existing permissions.
- Flat file rows replace the outer card and trailing action cluster. Supplied
  callbacks alone determine Retry/Download/Remove; opening and preview use the
  same access, transfer, cache and invalidation owners as before.
- Existing unknown association state now says Waiting for sync confirmation,
  rather than asserting that every failed probe is an unsynced note.
- Desktop Add block is quiet when idle and reveals on hover/editor focus/
  keyboard control focus/accessibility navigation. Compact Web keeps it visible.
  The wrapper cannot itself receive focus; Tab reaches the actual button.
- Web More contains the existing guarded Undo/Redo and secondary note actions;
  the header keeps primary Share/sync/More. A custom PopupMenuEntry gives each
  child its own enabled semantics and tap owner. Delete remains conditional.
- Native history stays in its editor rail, Redo then Undo, with touch targets.

Luna Max header_history28 owned four note-detail files, its focused test and
review. Root reviewed/integrated it and owned the other changes. Luna Max
priority28_review independently read the attachment/label/footer diff; no
confirmed new guard regression was found. Its existing status-copy caveat
prompted the clarification above. No overlapping file ownership.

## Focused checks and limits

Root rerun after integration:13/13 VM widget cases passed across file-row(4),
Web-control(3), secondary-menu(2) and label-widget(4) files. An initial run
found the wrapper's extra keyboard focus stop; it was corrected and the whole
targeted set rerun. These are bounded UI checks, not broad regression.

Frozen runtime manifest:837 paths,
`09ba42cec5dc7f2bb736f8edc2f11fe17c635f5f205dfb7be7a1a433e60cac11`.
28 analyzer clean97.8s; Web74.5s/APK84.9s, no source drift. APK
`d145ba1145ead4887e8623558061e8f9d40b29d31a746ac9414758f549f55fa5`
installed-r with matching device/local SHA. Actual Chrome/native label chooser,
file menu/preview/Download and history exercised. Both exported67B samples match
SHA256 `96fbf4c9f79c7137d7f3c424b45ac08fb21ee21f344dfe6b74cb815a0ecc7278`.
Web temporary UI28 text was undone, redone and undone again; native H2 conversion
was undone, redone and undone back to paragraph. QA content restored.

A test-created concurrent label conflict was resolved using the existing Use
remote action before continuing. It is not evidence of a product regression.
Chrome media requires its narrow Service Worker: keep CDP bypass=false. The
initial bypass=true reload loop was test configuration, not download failure.
Normal pointer export then succeeded without bypass/force-click. With Flutter
semantics enabled, however, the generic editor tap node intercepted iframe
controls; this is a real remaining UI issue and prevents signing off the slice.

29 is addressing that Web-only semantic overlay, terminal read progress wording,
48dp native file row,100px export panel, and matching viewer theme. A new focused
semantics VM case passed after correcting the authored test's API/focus lookup;
focused Chrome14/14 passed, exit0; no skipped cases, original aggregate restored.
Full29 analyzer then found only2 deprecated test flag calls; they were migrated
to flagsCollection (no runtime change). Final test-only analyzer/build/install
and actual29 semantics-enabled iframe interaction are still pending.
Both whole-platform95% gates remain unverified.
