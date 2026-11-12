# M09 UI guard review — 21 October 2026

## Scope and evidence

- Bounded source review of the editor popup guard, touch block sheet, native
  editor rail, workspace/detail IME and safe-area path, recent-note masking, and
  packaged font inputs.
- The code graph is at generation `2026-10-18T13:23:32Z`; all source paths used
  here were marked `metadata_changed` or `not_tracked`. I read the current
  workspace source directly and treated graph results only as navigation leads.
- I did not operate the browser/emulator or run a build/test in this bounded
  review. The lead supplied verified source16 evidence: the packaged APK was
  installed and hash-checked; tapping the open picker control dismissed it,
  while the body remained `Local first comparison`. Actual Notion native21
  showed Plus as the picker toggle and a separate far-right Close control.
  This report is not M09 acceptance or a 95% similarity claim.

## Corrected interpretation — Plus is the picker toggle

My initial review misread the touch-sheet callback as an Add block action. The
current control passes `blocksOpen: onBlocks != null`, and labels that same Plus
button “Close block menu” while the sheet is open; the ordinary rail labels it
“Add block” (`rich_note_editor.dart:297-305`; `editor_controls.dart:15-26,113-119`).
The sheet callback pops the route (`rich_note_editor.dart:166-174`). The caller's
null result closes the ephemeral slash state (`rich_note_editor.dart:138-140`;
`slash_command_controller.dart:96-104`). The lead's source16 device evidence
confirms that the tap closes the menu without changing the note body.

Therefore the dismiss path is the intended toggle behavior, not a defect and
does not need a feature change. The stale “Add block” label concern is addressed
by the open-state label. Direct runtime evidence was supplied by the lead; I did
not independently reproduce it in this bounded review.

## Static checks that remain intact

- The guarded sheet defaults to Flutter's normal barrier and accepts an optional
  barrier color; only the native Basic blocks sheet passes transparent
  (`editor_popup_guard.dart:21-37`, `rich_note_editor.dart:131-137`).
- Guard closure observes adapter lifetime and `accepts(snapshot,
  popupOwnsFocus: true)`; that check includes editability, composition, document
  revision, access generation and the captured selection
  (`editor_popup_guard.dart:52-78`, `rich_editor_adapter.dart:162-168`). Block
  conversion checks the snapshot again before applying its transaction
  (`basic_block_commands.dart:69-80,132-137,190`). I found no source path here
  that bypasses these access/snapshot checks.
- The native rail is shown only for an editable, focused editor with the IME
  visible and a collapsed selection; it coalesces pending show/hide requests,
  removes/disposes its root overlay entry on hide/dispose, and paints above the
  computed keyboard-safe bound (`native_editor_rail.dart:34-63,66-110`).
- The workspace consumes the top inset once, retains the body context's
  `MediaQuery`, and applies bottom SafeArea when the compact bar is absent;
  the compact bar itself uses SafeArea (`workspace_shell.dart:327-378,562-576`).
  Embedded NoteDetail avoids adding a second Scaffold
  (`note_detail_view.dart:12-25`; `notes_workspace_view.dart:177-190`). These
  are static observations only; Android gesture/3-button and iOS safe-area
  behavior still require actual runtime evidence.
- `DashboardRecentRail` receives the existing `readable` predicate and replaces
  unreadable titles with the protected-note label; it renders no note preview
  (`dashboard_recent_rail.dart:10-24,56-60,87-94,130-142`). Its caller supplies
  `DashboardContent._readable` (`dashboard_content.dart:78-79,709-716`).
- Roboto Medium/Bold and italic files plus Apache-2.0 license match the local
  Flutter SDK `material_fonts` bundle byte-for-byte (SHA-256 verified).
  Arimo asset hashes match the recorded official-font hashes, with the OFL
  present. `pubspec.yaml` declares both families as bundled assets, so rendering
  does not need a runtime font download. This verifies the current files and
  license payloads, not their Git history (`assets/fonts/roboto/README.md`,
  `assets/fonts/arimo/README.md`, `pubspec.yaml:108-140`).

## Unverified layout risk to check in the visual pass

When the keyboard reduces usable height in landscape, the touch sheet combines
a 48dp header with a BasicBlockMenu whose height is clamped to at least 240dp
(`rich_note_editor.dart:156-188`; `basic_block_menu.dart:121-146`). If the route's
remaining height is below that combined minimum, the flexible child may be
clipped or overflow. No reproduction was made. Check landscape with IME open and
small-height/text-scale configurations; if confirmed, size the grid from the
route's actual available height while keeping its choices scrollable.

## Review disposition

No confirmed picker regression remains; its close-toggle behavior and source16
body preservation were verified by the lead. The landscape layout case remains
a static hypothesis without reproduction. No access-guard, recent-note masking,
font license or offline-loading regression was found in the bounded paths
reviewed. Do not use this report as evidence that source17 passed runtime checks,
met the safe-zone matrix, or reached the Notion similarity threshold.
