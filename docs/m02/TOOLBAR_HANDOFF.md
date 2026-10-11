# Editor Toolbar Handoff

Historical pause snapshot. This describes the earlier quota-related stop, not
the resumed implementation's current status. See `TOOLBAR_QA.md` for the current
verification and publication record.

## User Request And Stop Point

Add a Notion-like in-note taskbar: headings, font size, text color, text editing,
and attachments. Reuse existing attachment functionality. Then push the current
working content to `final-TanMinh`. User explicitly authorized replacing that
branch with this version, including overwriting its content. User subsequently
asked to stop quickly and prepare a handoff because quota was nearly exhausted.

The feature is implemented locally but NOT finished/verified or committed/pushed.
Do not describe this as complete. No backend deployment was performed.

## Checkout And Publication

- Work here: `C:\Users\Admin\Documents\ChatGPT\note_app_ai\module01-polish`.
- Active branch: `final-tuankiet`.
- Remote: `https://github.com/IvanTran0101/note_ai_app.git`.
- HEAD and fetched `final-TanMinh` tip: `f23e810a12c2fbd55c2a75b93ca66ce7b24a0f7f`.
- Fetch used `git fetch origin final-tuankiet final-TanMinh`; remote tracking
  `origin/final-TanMinh` was not created by that command. FETCH_HEAD had its tip.
- Existing dirty Module 1 and completed Module 2 polish changes predate this turn.
  Preserve them and include them in the requested current-content publication.
- Do not work in/revert the original dirty checkout at
  `C:\Users\Admin\Desktop\Flutter\final`.
- Before publishing, inspect status, rerun checks, commit the intended source,
  tests and QA docs, then push HEAD to `refs/heads/final-TanMinh` with an explicit
  lease using a freshly observed remote SHA. User authorized replacement, not
  overwriting any newly arrived concurrent work without reviewing it.

## Implemented This Turn

- `flutter_quill: 11.6.0` added (locked); proven editor engine, no bespoke parser
  for editing operations. Pub get completed; generated macOS plugin registrant
  also changed legitimately. Binary attachments still use existing service.
- `lib/domain/notes/note_body.dart`: versioned text-only Delta envelope inside
  the existing content STRING (`noteflow:rich:v1\n` + JSON). Unformatted content
  stays plain; unknown/malformed formats stay literal, avoiding silent data loss.
  Attribute validation and readable-text extraction added. Blank styled content
  remains invalid under the original required-body invariant.
- `lib/presentation/notes/note_rich_text.dart`: scope bridges Quill edits to the
  existing TextEditingController/autosave lifecycle. Native plain TextField is
  retained until formatting is invoked; stored rich notes reopen in Quill.
  Headings 1-3/default, bold/italic/underline/strike, sizes, color swatches,
  undo/redo. Horizontal taskbar with 48px actions, tooltip/selected/disabled
  states, native menus, reduced-motion dialog styles. Colors adapt on dark theme.
  External rich paste disabled so binary media cannot bypass secured attachments.
  Clipboard config is experimental in pinned Quill and narrowly annotated.
- `note_detail_surface.dart` and form: toolbar top on desktop, bottom above the
  keyboard on compact; retains title/body focus, feedback and secondary widgets.
  Rich bodies do not use the plain-text AI breathing overlay (would expose JSON).
- `note_editor_panel.dart`: legacy editor also supports formatting and rich notes.
- `note_detail_page.dart`, labels/view parts: plus menu reuses file/gallery/camera
  picker, saves drafts first, checks edit/manage permissions and busy state.
- Attachment panel state made public for its `pick` entry point; existing picker,
  upload/retry/removal/security/cancellation logic retained. Add action hidden
  only in the detail panel because the toolbar now owns it. Transfer busy feeds
  the toolbar's enabled state. Reduced-motion transfer progress is static.
- Search, collection/dashboard previews, conflict display and local/cloud AI
  request inputs use readable text. Stored snapshots, sync/encryption and revision
  comparisons retain the full serialized content and formatting.
- `amplify/ai/note_body.ts` plus canonical summary authority decode: necessary
  so cloud authority compares readable input against readable saved content;
  authorization/revision/contiguous section checks and API schema unchanged.
  `summary_note_lineage.dart` source offsets now use readable text too.

## Tests And Current Verification

New tests: `test/domain/notes/note_body_test.dart`,
`test/presentation/notes/note_rich_text_test.dart`, shared JSON fixtures in
`test/fixtures/note_body_cases.json`, server codec parity test and rich-summary
authority test in `amplify/ai`.

First focused Flutter run: codec tests and three new rich formatting/history
flows passed. Four disabled-control assertions used a nested RawTooltip finder
and failed; fixed to typed widget predicates. One desktop geometry expectation
needed +48 for toolbar; fixed. Detail-page tests initially failed compilation
because NoteFlowMotion import was missing; fixed. Analyzer initially found that
import, a selected-token typo, three guard braces, and experimental API warnings;
all addressed. Final focused rerun completed: **67 tests passed**, covering the
codec, toolbar, detail surface and detail page. Final analyze was interrupted at the user's stop request before a result; rerun it.

Normal Flutter test remains blocked by the PREEXISTING Windows native LLM hook
unquoted compiler path (`C:\Program` not recognized). Existing scratch runner:

```powershell
$env:FLUTTER_ROOT='C:\Users\Admin\Desktop\Flutter\flutter\flutter'
dart --packages='C:\Users\Admin\Desktop\Flutter\flutter\flutter\packages\flutter_tools\.dart_tool\package_config.json' '..\notion-transition-checks\flutter_ui_test_runner.dart' test --no-pub --reporter expanded test/domain/notes/note_body_test.dart test/presentation/notes/note_rich_text_test.dart test/presentation/notes/note_detail_surface_test.dart test/presentation/notes/note_detail_page_test.dart
flutter analyze --no-pub
```

Backend `npm run typecheck` and `node --import tsx --test ...` initially could not
run because this clone had no installed Node dependencies. `npm ci --ignore-scripts
--no-audit --no-fund` was interrupted at user stop request; dependency installation
may be partial. Re-run it, then typecheck and existing AI/sharing tests.

## Remaining Before Push

1. Finish analyze and targeted tests, then broader affected regressions (notes,
   labels/search, summaries/application and runtime, sharing/security, attachment
   picker/transfer/removal, dashboard, conflict previews).
2. Review codec client/server parity beyond fixture cases (e.g. size-string
   parsing/link case). Exercise malformed stored rich input in the actual editor.
3. Add/verify integration coverage for toolbar attachment pick after draft save,
   cancellation, unauthorized recipients, busy transfers, and formatted autosave
   plus reopen. Existing tests cover core service behavior but not every new path.
4. Inspect actual rendered rich editor across desktop/mobile/dark/reduced-motion;
   select text, apply heading/color/size, type, undo/redo, autosave/reload, and add
   attachment. Confirm bottom toolbar stays above mobile keyboard and no overlap.
5. Build web, run browser QA, update docs and `git diff --check`, inspect diff,
   commit and push only once verification is satisfactory.

Preview `http://127.0.0.1:8772/` still serves the PREVIOUS Module 2 build, NOT this
toolbar. Existing headless Edge Playwright scripts and screenshots are in the
parent workspace; see `docs/m02/UI_QA.md`. Build uses local auth; live Cognito,
native hardware and cloud deployment are not verified. New server decoder must
be deployed alongside rich-note clients for cloud summaries of formatted notes.
Older clients without this decoder/editor may show serialized rich content.

## Tool Notes

PowerShell shell calls need `sandbox_permissions: require_escalated` because
default sandbox initialization/reparse handling is broken. Manual edits must
still use apply_patch. Direct apply_patch also hits the reparse problem; approved
CLI workaround uses `C:\Users\Admin\AppData\Local\OpenAI\Codex\bin\9691020b546a15b2\codex.exe`
with `--codex-run-as-apply-patch` and a PowerShell here-string patch argument.
Do not use shell file-write tricks or revert unrelated changes. No subagent was
requested or used. End user replies with verification limits (Ponytail full).
