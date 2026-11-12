# M09 rich editor checkpoint — 17 October 2026

Verified source/local editor checkpoint. M09 final UI acceptance remains open.

## Implemented

- Presentation adapter for the existing local-first note writer, autosave,
  encrypted drafts, outbox/cursor, conflict, sharing and protection contracts.
- Thirteen Basic blocks; independent notes, no Page/Link to page/child notes.
- Selection marks, semantic colors/highlight, link, inline equation and selected
  text sizes12–48; guarded dialogs, clipboard, undo/redo and table operations.
- Full-page note layout, one compact sync/header action, metadata after the
  document, EN/VI editor copy and stable editor/input across local acknowledgments.
- Native caret auto-scroll bounds/frame/disposal fixes, touch block sheet,
  accessible action ownership and root-overlay popup coordinates.
- Automatic table height measurements no longer enter Undo or erase Redo.

## Frozen source and regression

Runtime807-file fingerprint:
`4ee0a0ed21eedc8093b7ad92ab2d7c1bba11a7beeb269013195bc1ef6baa2101`.

| Check | Observed result |
| --- | --- |
| Full VM | 1898 pass,5 configured skips,0 failures;2m46s |
| Installed Chrome199 original test mains | 1700 pass,2 configured skips,0 failures;2m01s test runtime |
| Static analysis | lib/test/integration_test/golden tool/modified TableCol: No issues found |
| Android x64 debug build | 63.7s; installed-r, on-device APK hash matched |
| Web debug build | 104.2s; JS build succeeded |
| Regression reproduction | AX duplication4/4 fail before; focused82/82 after |
| Table Undo reproduction | rendered table2/2 fail before; table/controls/identity/scroll54/54 after |
| Editor/layout subset | 144/144 after table and popup corrections |

Chrome includes actual local HTTP rich sync/share/revoke/protected-read transport,
real IndexedDB/encryption/migration and the existing module regression tests.
The two configured Chrome skips are the absent real GGUF model and the
platform-specific avatar codec case. The default VM skips are retained in its
receipt; they are not counted as passes. Browser test compilation/startup time
is separate from the listed test runtime.

The local fixture needs its existing `M09_QA_BROWSER_ORIGINS=1` flag for random
Flutter browser-test ports; the human app URL remains localhost8776. A first
opt-in run without that fixture flag failed preflight; the corrected run above
passes. No deployed CORS policy was changed.

## Actual UI evidence

Matching APK SHA256:
`A76328E3ACC42C6B648018D7A3AA1D5F9CF644E1F56FA00662175BE134379096`.
Target `lib/main_dev.dart`, local owner fixture; API35,1080x2400,420dpi.

- Matching APK cold-open keeps the synthetic equation/color/table and the
  separate Q28/H4/`A1 tiếng việt 😀`/B1 note. No layout-only Undo on opening.
- Physical touch Add row/Undo/Redo/Undo gives4→5→4→5→4 rows. The previous
  layout-history trap is fixed on the actual device.
- Longpress Q shows the selection controls above it: controls endy677,
  selected field startsy750. The earlier overlay covered the selected glyph.
- Earlier actual Native core captures cover all13 touch choices, todo toggle
  and Undo, marks/clear, colors/highlight, size49 refusal/28 apply, invalid URL,
  HTTPS apply/reopen, invalid equation and painted square root. These used the
  preceding build; matching final adaptive/permission UI QA remains in progress.
- Earlier actual Native Telex/emoji/offline/cold reopen/reconnect and installed
  Chrome cross-device table sync are recorded in `P4_UI_QA.md`.

Receipts/screenshots are local, ignored QA output under `output/m09/` and
`output/playwright/`; raw logs, private reference images, data and keys are not
published. Current build/hash details are in the local provenance JSON.

## Remaining M09 work

- Native phone landscape currently selects desktop navigation and is cramped
  with the keyboard. Polish that responsive choice and title/body/control spacing
  using the existing controls and callbacks.
- Finish actual Chrome/Android protection, sharing, files/labels/search/settings,
  resize/rotation/text-scale/navigation-mode and light/dark UI matrix.
- Updated order19 October: open Notion Web AND the actual Notion Android app,
  compare matching screens/states and refine UI until EACH resembles them by
  >=95%, with current paired evidence and Android/iOS safe zones. Old point
  ratings are withdrawn. Only after this UI gate resume functional acceptance;
  see MUST_REMEMBER.md and CURRENT_WORK.md for the authoritative next step.
- Update Notion/checklists and publish each verified checkpoint, then final handoff.

This checkpoint does not establish live AWS/RAG acceptance. The previously
recorded provider/deployment and exact RAG-manifest gates remain separate.
