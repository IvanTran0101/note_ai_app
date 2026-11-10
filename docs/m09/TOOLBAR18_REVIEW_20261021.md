# Selection toolbar source18 review — 21 October 2026

## Result

No material defect found in this bounded **static source review** of the toolbar split. This is not a build, widget-test, browser, Android, or UI-similarity acceptance result.

## Evidence reviewed

The code index is at `2026-10-18T13:23:32Z`; coverage marks the three toolbar files as `metadata_changed` or `not_tracked`, and the immediate dependencies as `metadata_changed`. I therefore read the current source directly; graph results are not treated as current evidence.

- [`selection_toolbar.dart`](../../lib/presentation/editor/selection_toolbar.dart#L18) declares the part and keeps toolbar construction and sizing/layout selection in the original library. `SelectionToolbarLayout` remains the existing layout boundary (`selection_toolbar_layout.dart:10-38,44-109`). The equation still calls `onPopupOpen()` at line 110.
- [`selection_toolbar_dialogs.dart`](../../lib/presentation/editor/selection_toolbar_dialogs.dart#L4) contains four moved dialog methods. Each calls `onPopupOpen()` once (style, size, link, color); together with the retained equation call there are five call sites in the library. The moved methods contain three `guardedEditorDialog` calls and two `editorValueDialog` calls. Both value dialogs pass the adapter and captured snapshot, so `editorValueDialog` wraps them with the same guard (`editor_value_dialog.dart:10-28`).
- Style selection remains Text/H1–H4 and applies through `BasicBlockCommands.choose` with the captured snapshot and `popupOwnsFocus: true` (`selection_toolbar_dialogs.dart:4-27`).
- Size offers 12/14/16/18/24/32, custom 12–48, and reset (`selection_toolbar_dialogs.dart:30-83`). Preset and custom values both call `SelectionFormattingController.size` for the captured selection. Validation delegates to `DocumentMarks`, which enforces finite sizes from 12 through 48 (`editor_value_dialog.dart:119-123`; `document_marks.dart:39-41`).
- Link, color, and highlight still use their existing validators/enum attributes and the same captured selection (`selection_toolbar_dialogs.dart:86-155`).
- [`editor_popup_guard.dart`](../../lib/presentation/editor/editor_popup_guard.dart#L7) closes the route when the adapter is inactive or the captured snapshot no longer passes. `RichEditorAdapter.accepts` checks editability, composition, revision, access generation, and selection (allowing a null selection only while the popup owns focus); `apply` repeats that check before mutation (`rich_editor_adapter.dart:162-180`).
- Formatting still writes selected Delta ranges in one editor transaction and delegates to `adapter.apply` (`selection_formatting_controller.dart:110-145`). The adapter's transaction listener decodes a changed document and invokes its `onChanged` callback (`rich_editor_adapter.dart:43-47, 96-105`). The note-detail callback records the edit and schedules the existing autosave route (`note_detail_document.dart:33-60`; `note_detail_autosave.dart:54-76`). This confirms callback wiring in source, not durable local persistence at runtime.

## Limitation

I did not build or run tests or operate Web/Android, as required by this review task. Runtime correctness, persistence, visual similarity, and compatibility of the split remain for the lead's current-candidate verification.



## New-note title loses Web focus after first character — static diagnosis

### Observation and confidence

The lead observed in Chrome static18: after selecting New note, clicking Title and typing `M09 Final UI21` produced only `M`; `document.activeElement` was then `BODY`. Clicking the title again and typing the full title worked. I did not repeat this in a browser. Current source does **not** prove why the initial focus loss occurred; harness timing and a first-edit Web focus regression remain distinguishable only with a controlled repro.

### Source trace

- New-note state stays `note == null`: `_startNewNote` clears `_selectedNoteId`, sets `_editingNewNote`, and resets the detail-key identity (`notes_workspace_page.dart:289-304`). Workspace rendering therefore keeps calling `_detailKeyFor('new')` (`notes_workspace_view.dart:177-191`; `notes_workspace_page.dart:119-127`). The dirty callback only changes `_detailDirty` (`notes_workspace_page.dart:382-385`); it does not select a saved note or replace the `NoteDetailPage` key. `_handleDetailExit` is the path that resets workspace selection after save/cancel/exit (`notes_workspace_page.dart:388-426`). I found no evidence of a parent-host replacement on the first title keystroke.
- For a new note, `_capabilities` explicitly permits read and edit (`note_detail_security.dart:31-46`). `readOnly` is computed from security busy/loading or `!_canEdit` (`note_detail_view.dart:125-145`), so `hasSavedNote` changing is not the mechanism that makes this title read-only. The title field is always built when `includeTitle` is true and has a stable key plus the page-owned focus node (`note_detail_editor_form.dart:128-167`).
- A real title focus loss has an immediate side effect: `_titleFocusChanged` calls `_saveWhenEditorLosesFocus`; when neither title nor content is focused, it schedules an immediate autosave (`note_detail_autosave.dart:36-50`). That starts `_save`, creates the new document through the existing controller (`note_detail_actions.dart:29-30,90-100`), and assigns the returned note to `_note` (`note_detail_actions.dart:47-57`).
- The new-note-to-saved transition then changes the detail surface branch. An unsaved note returns `editor` directly; after `_note` is assigned, `_buildSurface` instead wraps it in `LayoutBuilder`/`Column` (`note_detail_view.dart:195-231`). This is a plausible **post-blur remount/focus-loss amplifier**, but it occurs after focus loss has already scheduled the save, so it does not establish the trigger for the first `M`-only event.
- The first title edit rebuilds the detail page. Its title is in the rich editor header (`note_detail_surface.dart:251-258`; `rich_note_editor.dart:288-299`), and `RichNoteEditor.didUpdateWidget` replaces the header value on updates (`rich_note_editor.dart:82-87`). `RichNoteEditor` otherwise caches the AppFlowy editor and comments that replacing its services per keystroke loses Web IME focus (`rich_note_editor.dart:231-252`). The title TextField uses the same key/controller/focus node, and I found no explicit `unfocus()` in this header path. The header update is a candidate to inspect if a focus-verified UI repro repeats, not a proven cause.

### Recommendation

Do not change `readOnly`, autosave, note selection, or security guards based on this single event. In the next controlled Chrome attempt, wait until the title's actual input has focus after the click, then type and check both the controller text and `document.activeElement` immediately after the first character. If it still blurs, isolate the title/header rebuild first. Separately, if the saved-note transition is observed remounting the active editor, the smallest structural fix is to keep the `NoteDetailSurface` root/`RichNoteEditor` subtree stable across draft-to-saved state; this would address only the post-save remount, not prove or fix an earlier blur.

No source or runtime state was changed; no tests, build, browser, or Android emulator were run for this diagnosis.

### Evidence scope clarification for this diagnosis

No graph coverage query was run for the note/workspace paths in this diagnosis. The earlier successful query in this conversation covered the toolbar and immediate editor dependencies only; this section is based on direct current-source reads, not fresh graph evidence. The app composition root keeps the keyed `NotesWorkspacePage` mounted in the workspace shell's `IndexedStack` (`main.dart:1656-1658`; `workspace_shell.dart:443-449`). The workspace dirty callback changes only `_detailDirty` (`notes_workspace_page.dart:382-385`), and the detail key remains based on `'new'` while its selected note is null (`notes_workspace_view.dart:177-191`; `notes_workspace_page.dart:119-127`).

## Controlled Chrome result and source20 fix

The lead's follow-up Chrome run confirmed title focus before typing: clicking
the title produced an empty `TEXTAREA` as `document.activeElement`; typing `F`
immediately left `F` in that textarea. After autosave completed, the active
element became `BODY` and the saved title was `F`. This looked like focus loss
on that attempt; the later controlled Chrome run below did not reproduce it
after verifying the input was ready. Treat the earlier event as run-specific,
not evidence of a confirmed product defect.

Source20 removes the draft-only direct return in
[`note_detail_view.dart`](../../lib/presentation/notes/note_detail_view.dart#L193-L205):
drafts and saved notes now both use the existing `LayoutBuilder`/column path.
This preserves the saved-note layout and keeps the `NoteDetailSurface` at the
same element path when first local save assigns a `NoteDto`. The existing
autosave path, access checks, and security state are unchanged. This structural
change has not been shown necessary by the latest browser evidence and should
not be treated as a confirmed product fix. A focused widget regression was added at
[`new_note_focus_test.dart`](../../test/presentation/editor/new_note_focus_test.dart#L10)
to check title focus and `RichNoteEditor` state identity through that autosave.
The lead reports 6/6 focused widget cases pass after adding a Material
`Scaffold`; the direct-page test still does not cover the production workspace
`onDirtyChanged` parent rebuild or actual Web DOM input lifecycle. It is not a
UI-similarity score or broad M09 acceptance.

The controlled Chrome observation was supplied by the lead, not independently
reproduced here. No fresh graph query or coverage result was obtained for these
note-detail paths; claims above are bounded to the supplied browser observation
and direct source reads. The prescribed `_agent_ops/tools/session_start.py`
was absent when the repository session-start command was attempted.

## Source20 follow-up — readiness evidence and widget harness gap

An earlier source20 Chrome attempt left only `M` after a semantic click and
later showed `BODY` after autosave. In the lead's latest controlled run the
first click left `BODY` active; a second click on the blank Title parent yielded
an empty `TEXTAREA`; typing `Z` left it active; it remained connected as the
same node326 through autosave and a long wait; then ` — M09 Focus20` entered
completely. The lead reports no `focusout` or node removal during that interval.
The event log is `output/playwright/p6-parallel20-title-focus-events.json`.
The earlier M-only result may have been a click/readiness race. These runs do
not establish a production focus defect or justify treating the static
candidate as its cause.

The lead reports the focused VM new-note suite passes6/6 after adding a
Material `Scaffold`. This result does not model the production workspace
callback described below.

The current `new_note_focus_test.dart` mounts `NoteDetailPage` directly and
does not provide `onDirtyChanged`; it therefore does not reproduce this
production callback. On a new draft's first edit, `_recordEditorChange`
rebuilds the detail and calls `_notifyDirtyChanged` (`note_detail_document.dart:47-60`).
The dirty callback then calls workspace `setState` once when clean becomes dirty
(`note_detail_autosave.dart:19-25`; `notes_workspace_page.dart:382-385`). This
parent rebuild is a coverage gap in the direct-page widget harness, but the
latest Chrome run does not support it as a production cause. The workspace's
`_detailKeyFor('new')` returns the same `GlobalKey` while the draft is selected
(`notes_workspace_page.dart:119-127`; usage at
`notes_workspace_view.dart:177-190`).

The smallest added harness would wrap the current `NoteDetailPage` in a
`StatefulBuilder`, give it a stable `GlobalKey<NoteDetailPageState>`, and pass
`onDirtyChanged: (_) => setState(() {})`. Capture the page State, title
FocusNode, and `RichNoteEditor` State before typing; after first-dirty rebuild
and autosave, assert that the key still resolves to the same page State, focus
stays true, and editor State is identical. This simulates the host rebuild
while retaining the same child key. Using `NotesWorkspacePage` with its
existing GlobalKey and `startNewNote()` is a more integrated but larger test.

Other inspected paths narrow the candidates. `_notifyNoteEdited` returns while
`_note == null`, so the RAG root callback is not invoked for a new draft
(`note_detail_rag_part.dart:145-148`). `refreshAccess()` is only used by the
RAG selection-reveal path, not title edits (`note_detail_rag_part.dart:88-90`).
The security path calls `unfocus()` only after session change or a read/edit
capability failure on the selected note (`note_detail_security.dart:73-88`);
the first edit of an unsaved draft does not meet those conditions in source.
`RichNoteEditor.didUpdateWidget` republishes changed header/footer widgets
through `ValueNotifier`s (`rich_note_editor.dart:82-87`); the cached AppFlowy
view remains stable unless theme, editability, compact/short mode, or text scale
changes (`rich_note_editor.dart:235-252`). The title widget keeps the same key,
controller, and page-owned focus node (`note_detail_editor_form.dart:131-139`).
This leaves a header/EditableText Web input-connection update as a candidate,
not a source-proven cause.

The latest controlled Chrome run instead supports a readiness race in the
earlier attempt: verify the active textarea before sending the typing batch.
The proposed `StatefulBuilder` regression can still cover the host callback,
but a pass establishes only widget-level focus/state retention, not Web DOM
input behavior. No runtime instrumentation or source/test change was made in
this review. No fresh graph or coverage query was available; these conclusions
use direct source reads and lead-supplied browser/test results.
