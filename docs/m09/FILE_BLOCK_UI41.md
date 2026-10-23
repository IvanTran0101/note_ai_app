# UI41 — File in / and contextual block +

Status: PASS for the user's bounded File/label slice on source/build47.
Stop after publishing this checkpoint; wait for the user's next task.
Both platform similarity gates remain UNVERIFIED, with no whole-M09 signoff.

## Scope and direct reference

The user rejected UI40's separate Add attachment footer. Actual Notion Web was
opened on the synthetic reference page: /file filters to Media/File, choosing
File creates an inline placeholder and Upload/Choose a file popover. The gutter
+ inserts below the selected block and opens the same insertion list. Link/embed
is outside the existing capability and is not added. Temporary reference blocks
were removed through ordinary recoverable block deletion; existing file/content
was retained. Labels remain immediately below title.

## QA inventory before signoff

- Web /file and contextual +: insertion at selected middle block, no fixed footer
  Add attachment/Add block; preserve before/after text and the 13 Basic choices.
- Android native + and /file: same File choice, touch targets, keyboard/navigation
  safe area; cancel and reopen Upload chooser.
- Inline file: existing picker/row/menu/preview/download, multiple-file order,
  local-first reopen, no filename/bytes in document projection.
- History: undo/redo insertion, binding and block deletion; legacy files retained,
  deleted references never resurrect as footer rows in inline layout.
- Access/lifecycle: viewer cannot insert; revoke/session change/dispose/removed
  target refuses a late picker bind; unavailable file exposes no old metadata.
- Exploratory: choose file then cancel; move caret while picker is open; long
  filenames/narrow width/text scaling; existing files before first inline insert.
- Build provenance: source manifest, no drift, actual Chrome bundle and installed
  APK match the source used for these checks. Screenshots are ignored artifacts.

## Ownership

Three Luna Max workers: wire/domain codec; menu/insertion; single attachment
panel/controller. Lead: adapter/binding, renderers/gutter, note-page bridge,
review, focused checks, reference/runtime evidence, docs and publication.

## Final checks and build identity

| Check | Verified result |
| --- | --- |
| Focused Flutter VM | 40/40 pass, p6-ui47-vm.log |
| Focused Flutter Chrome | 19/19 pass, p6-ui47-chrome.log |
| Backend document parser | 8/8 pass; node --import tsx --test for the two document suites |
| TypeScript | Scoped strict tsc --noEmit clean |
| Flutter analysis | 11 source/test targets clean,47.3s |
| Web/APK | Debug local entrypoint builds,65.8s /35.7s |
| Source provenance | 1073 runtime paths; drift[] |
| Git whitespace | git diff --check clean |

Runtime fingerprint:
`a12c74dd6c4933693213c73817b448cd0b824e58967c3726e829cc18251d4f0e`.
Chrome received21,347,709 bytes of main.dart.js; SHA256
`e5016d38e6ae7677aac0e938c3c5c6b5aedba3f768d15eb771192bfb8d41da68`
matches the packaged file. APK and installed emulator base APK SHA256 both
`c81b36881c8d021bf9d8681ce21c1645395eff414fdc0d02f1f4dd083f093907`.
Manifests/receipts: output/m09/p6-parallel47-source.json and
p6-parallel47-build.json. No runtime source changed after these builds.

## Actual user interaction evidence

Chrome local1280x740, installed Chrome, semantics enabled, existing guarded
attachment worker enabled. Android native1080x2400,420dpi/font1,3-button,
NoteFlow_API35 emulator controlled through ADB. Synthetic note UI41_Native;
no existing user note was replaced. All following artifacts are ignored under
output/m09 and are not committed to Git.

| Flow | Actual evidence |
| --- | --- |
| Web + query | app47-web-plus-filter.png: inline Type to filter; file stays query-only |
| Web Escape and typing | Escape then Before /file worked without another click; app47-web-slash-filter.png |
| Web /file | Enter preserves Before and opens positioned Upload/Choose a file; app47-web-upload.png |
| Web + to File | Filter file, Enter opens the same inline Upload; app47-web-plus-upload-final.png |
| Web actual picker | System chooser selected the67B sample; third row inline, old rows retained; app47-web-file-added.png |
| Web cancel/reopen | Chooser setFiles([]) retained the placeholder; subsequent Upload reopened |
| Web local persistence | Browser offline, Back then open local note; Before and the three locally known rows retained; app47-web-offline-reopened.png |
| Web download | Menu opens guarded viewer, its Download gesture exported67B with matching SHA256 |
| Android + | Continuous Basic/Media list to File; app47-native-media.png |
| Android Upload | Cancel, reopen same placeholder, Choose a file to system Downloads; app47-native-upload.png / chooser.png |
| Android actual picker | Selected67B sample, fourth row inline; app47-native-file-added.png |
| Android /file | Typed /file, filtered File, tapped File to Upload; app47-native-slash.png / slash-upload.png |
| Android existing actions | Inline menu/download and TXT preview with exact synthetic content; app47-native-file-menu.png / preview.png |
| Android reopen | Back to list then reopened UI41_Native; four file rows and Before retained; app47-native-reopened.png |
| Label and safe area | Label remains below title on both; native Upload options end at2253px before the3-button navbar |

Web and native exports both67B, SHA256:
`96fbf4c9f79c7137d7f3c424b45ac08fb21ee21f344dfe6b74cb815a0ecc7278`.
No JavaScript exceptions or unexpected console errors in the final interaction
run. ERR_INTERNET_DISCONNECTED was expected during deliberate browser offline.
A wrong locator for PopupMenu content caused a harness timeout/restart; no
product pass was inferred from that attempt. The final chooser path used the
observed rendered control and a handled filechooser event.

## Lead review and fixes

- Reviewed all three deliveries and integrated their disjoint ownership.
- Fixed absent runs decoding on File blocks, paragraph split newlines and
  callback remounts that replaced the engine input service.
- Kept one attachment service/transfer/preview owner outside native lazy list;
  scheduled controller refresh requests a frame and never writes the document.
- Allowed harmless content ACK during picking while retaining session, note,
  access, protection and write guards. Binding refuses stale/deleted/overwritten
  targets and retains encrypted pending files for explicit recovery.
- Kept Basic choices13; File is separate Media. Migrated legacy references once;
  deletion/undo/redo never resurrects an attachment footer.
- Fixed Web gutter overlay hit testing and semantics focus loss. + query owns
  temporary input, late engine text edits cannot enter the document, and Escape
  restores only the selected block after query disposal without taking dialog
  or other text-field focus. Guarded deferred composition is cleared before
  rejecting an upstream transaction; a regression proves the draft is unchanged.
- Domain/storage/backend accept only safe positional attachment IDs. No bytes,
  filename, URL or second attachment writer enters the document or AI text.

History and access/lifecycle entries in the inventory are covered by focused
automated cases; they are not a claim of live AWS authorization regression.
Current code graph transport is closed and its recorded generation18Oct was
stale, so exact current source was read for the bounded changed paths.

## Publication and remaining scope

Notion's comparison board preserves all24 prior images, adds7 UI41 images,
and checks only this attachment item (label was already checked). Progress is
under final flutter. Both >=95% gates remain open. No Link/embed, new media,
new attachment policy, dependency or unrelated M09 implementation was added.

The backend parser change is source/local-tested; live AWS deployment is not
verified. Backend support must precede clients syncing the additive inline file
shape to an older strict parser. Overall typing/title-first-focus observations,
global keyboard/navigation safe-area review and iOS evidence stay in the M09
backlog. The existing KGP migration build warning remains; both builds succeed.
No known blocker remains in the exercised bounded File flow. This is not an
assertion that the entire app is bug-free.

## Closure receipt

| Record | Resolution |
| --- | --- |
| MUST_REMEMBER.md | Updated bounded completion and stop condition |
| CURRENT_WORK.md | Updated final source/build/test/runtime identity and next boundary |
| AGENT_IMPLEMENTATION_20261019.md | Updated three worker handoffs and lead review |
| VISUAL_REVIEW.md | Added bounded File evidence; left overall similarity unverified |
| FILE_BLOCK_UI41.md | Added review, checks, runtime evidence, limits and this receipt |
| _agent_ops session/continuity files | Not needed: tools/SESSION_PROTOCOL/records absent in this checkout; no generated pack claimed |
