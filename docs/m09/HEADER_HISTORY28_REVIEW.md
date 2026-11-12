# Header History and More Menu — Review 28

## Scope

Wide Web note-detail header and secondary More menu, plus preservation of the existing compact/native action flows. This slice does not claim the M09 visual similarity target or final acceptance.

## Changes

- Wide Web keeps Share and sync status in the header and exposes secondary actions through More, including Undo/Redo, Summarize, and eligible security/RAG actions.
- Undo/Redo rows reflect the current history stacks and are disabled when the note is not editable/readable, the adapter is stale or absent, an action is busy, there is a conflict, or the corresponding history stack is empty. After a tap, the menu closes once and the captured adapter/access state is revalidated before the history operation runs.
- The desktop secondary-actions menu uses a custom `PopupMenuEntry`; its child controls own their semantics and taps. Delete is omitted when `allowDelete` is false, including on desktop.
- Summarize and security/RAG actions move into More on wide Web. Native compact bottom-sheet behavior and native history controls remain unchanged. The Web Add Block footer remains available.

## Verification

- `flutter test --no-pub test/presentation/notes/note_detail_secondary_menu_test.dart --reporter expanded` — **2/2 passed**. Covers one-shot child action dispatch, hidden unauthorized Delete, and authorized Delete selection.
- `flutter analyze lib/presentation/notes/note_detail_view.dart lib/presentation/notes/note_detail_surface.dart lib/presentation/notes/note_detail_more_actions.dart lib/presentation/notes/note_detail_compact_actions.dart test/presentation/notes/note_detail_secondary_menu_test.dart` — **No issues found** after correcting the AppFlowy history stack API usage and test imports.

## Review limits

This focused test does not exercise real editor history mutations or the browser/native visual layout. No Web/Android visual score or M09 acceptance is claimed here; those remain part of the parent task's integration and UI review.
