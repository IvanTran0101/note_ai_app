# Core Note Management: Editor Toolbar

## Scope And Verified Requirements

This extends Module 02, Core Note Management, using the user's Notion phone
screenshots as the toolbar reference. The earlier portfolio study and module
planning are recorded in `UI_QA.md`. New explicit requirements are headings,
text color, font size, text editing and attachments. This report does not claim
completion of other modules or the whole project rubric.

Existing flows inspected: required title/body, revision-safe debounced autosave,
save failures/retry, dirty-back confirmation, security/read-only projection,
attachment picker cancellation, encrypted local staging, upload/retry/removal,
search/previews, and local/cloud summary inputs. No new camera, upload, sharing,
AI or backend API capability is claimed.

## Implementation

- `note_rich_text.dart`: pinned Flutter Quill 11.6.0 editing engine, with a
  Notion-like horizontal icon toolbar. Normal text and H1-H3; bold, italic,
  underline, strike; default and 12/14/16/20/24/32 sizes; default and four colors;
  undo/redo. Plain native editing stays available until formatting is used.
- `note_detail_surface.dart` and the legacy `note_editor_panel.dart`: existing
  shared tokens, 48px action targets, tooltips, selected/disabled states,
  checked menus, dark-mode text colors, visible horizontal-scroll affordance,
  native hover/press/focus feedback and reduced-motion popup behavior. Desktop
  toolbar is above writing; compact toolbar is bottom-anchored above the keyboard.
- `note_detail_labels.dart` and the existing attachment panel: the plus menu
  delegates to files, gallery, photo and video selection. A draft saves first;
  a focus-loss save is awaited instead of dropping the selected action. Saved
  permissions and editor/account generations are rechecked before picking.
  Picker/transfer busy state disables the toolbar action. Cancellation, encrypted
  staging, retry, removal, quotas and authority checks retain their existing logic.
- Attachment management now lives in a paperclip tray beside the toolbar, closed
  by default. Its badge counts actual associated and pending files; selecting an
  attachment source opens the tray. A bounded, scrollable area retains existing
  file preview/error/retry/removal controls without a permanent empty card or
  quota paragraph in the writing area. Closing it excludes hidden keyboard focus,
  but keeps pending-transfer state alive. Expansion respects reduced motion.
- Editor lifetime: first draft save and responsive wrapper changes retain the
  active editor, selection, focus, undo history and open menus. Switching note or
  controller identity resets history so another note's text cannot be restored.
- Escape/back dismisses an open toolbar popup before requesting editor closure.
- `NoteBody`: text-only Delta stored as a versioned envelope inside the existing
  content string. Plain notes remain plain. Invalid/unknown envelopes stay
  literal rather than losing data. Blank styled content remains invalid.
- Search, collection/dashboard/conflict previews and summary inputs use readable
  text. Persistence, encrypted snapshots, sync payloads and revisions retain the
  complete formatted string. No API schema or infrastructure configuration changed.
- `amplify/ai/note_body.ts` uses the same fixtures/validation as Dart. Canonical
  summary authority compares readable request text against readable saved text,
  retaining authorization, revision and contiguous-source checks. A test fixture
  helper now uses Node's `fileURLToPath` for Windows compatibility.

## Verification

- Final `flutter analyze --no-pub lib test`: no issues.
- Broad affected Flutter run: 516 passed, two existing skips, and two newly added
  draft-toolbar failures. Both failures were fixed and rerun successfully in the
  66-test editor/attachment suite. Counts overlap and are not unique requirements.
- Added automated coverage for rich autosave/reopen, note-change history isolation,
  save-before-picker, invalid draft, cancellation/busy state, first-save editor
  lifetime/open menu and mobile keyboard insets. The extended auth/common/root
  and editor run passed 148 tests; the final editor/workspace/attachment run
  passed all 109 tests, including tray dismissal and keyboard-inset layout.
- Backend typecheck passed. All 42 AI/sharing test entries passed, including
  client/server codec fixtures and formatted canonical-summary security.
- Final local-auth Flutter web build passed. Headless Edge rendered checks passed
  at 1440x900, 768x1024 and 390x844, including a separate touch context, dark mode
  and reduced motion. Nonblank-pixel assertions and screenshot inspection were
  used. H1, size 24 and blue selection survived reopen; card previews did not
  expose the serialized envelope. Real file selection staged a synthetic TXT
  file, showed its pending row and badge, and retained it across tray dismissal.
  Touch menus and the empty tray were checked with the bottom toolbar in place.
- A separate native-canvas Edge check verified actual key typing into a stored
  bold rich note, autosave, back navigation, reload and reopening with the new
  text retained. The engine's terminal newline was included in that assertion.

## Compatibility And Limits

### Local Attachment Entry-Point Follow-Up

The tray now has a visible Add attachment command alongside the toolbar plus.
Both use the same source menu, capability/busy gates and save-before-pick path.
Gallery is labeled Photos & videos because the existing adapter already uses
`pickMultipleMedia`; Choose files, Take photo and Record video remain available.
No attachment service, S3 transport or backend configuration changed. This
follow-up is prepared for publication to `final-TanMinh` at the user's request.
Its 101-test focused run and Flutter analysis passed, and the updated local-auth
web preview built successfully.
Rendered Edge checks opened the visible tray source menu on desktop and touch,
verified all source labels, dismissed it without losing the note, and retained
successful TXT staging, tray dismissal and dark/reduced-motion layout checks.

The pre-toolbar source commit already contains the attachment picker, encrypted
cache, HTTP upload/read, retry/cancel/removal and S3 backend implementations.
`docs/m03/PROGRESS.md` records source/local acceptance separately from the pending
AWS deployment/live gate. Local Pending in this preview is not an S3 upload
receipt; deployment, API/auth/permission configuration and live acceptance must
be verified, not assumed to be only a bucket connection.

The cloud summary decoder must be deployed with rich-note clients before live
cloud summaries of formatted notes can work. No backend deployment is performed
by this change. Older clients may display the serialized rich-note envelope.

The normal Flutter test command is blocked by the preexisting Windows native LLM
asset hook (unquoted compiler path under `C:\Program Files`). Tests use the
existing Flutter test-command runner with only the native asset builder bypassed.
Native LLM binaries, physical phone keyboards/cameras, live Cognito and live cloud
uploads/summaries are not verified. No abrupt-termination write guarantee is added.

Rich typing through Flutter's enabled web accessibility/semantics overlay did
not attach a native input field in the automated Edge check. This is a known
verification limitation, not a claim of screen-reader editing support. Normal
canvas text input is checked separately; toolbar keyboard/menu checks and the
readable attachment-row semantics passed. Investigate overlay text input before
claiming fully accessible web rich editing.

## Publication

User authorized replacing `final-TanMinh` with the current working content,
including the prior Module 01/02 polish. Remote tip `6dd25d1` was reviewed and
preserved locally as `codex/final-tanminh-before-toolbar-20261011` before publication.
The source checkout remains `final-tuankiet`. The requested publication target is
`final-TanMinh`, with an explicit lease against that reviewed remote revision so
an unobserved intervening update cannot be overwritten.
