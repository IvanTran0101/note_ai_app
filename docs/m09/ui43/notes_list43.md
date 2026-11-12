# UI43 Notes list audit

## Status

Owned implementation is complete for the lead's bounded list refinement. The
current direct reference captures the Web document/popup, while the project
mapping supplies older supporting home/list refs. The report below does not
claim that the Notes list itself was directly compared on Web or Android, and
does not claim parity or a similarity percentage.

The requested `docs/m09/ui43/REF_MAPPING.md` is absent. The available supporting
mapping is `docs/m09/REF_MAPPING.md`; its 19 October notes-list row points to
Web `notion-web-001-home.jpg` for sidebar/list hierarchy and Android
`001_01_home_recents-favorites-private.png` for list density. The mapping says
those files do not replace current direct inspection. Do not use their private
reference text as app demo data.

## Baseline and changes

- `NotesListPanel` retains its constructor, callback wiring, existing keys,
  error/empty states and `AnimatedNoteList` composition.
- The title can use two lines with ellipsis. Header action density now adapts
  to compact/local width and enlarged text; the same New note action, tooltip,
  key and busy-state rule remain in place.
- Injected query controls now scroll inside a height bounded by one third of the
  available panel height when the viewport is bounded. At ordinary heights the
  controls keep their natural size; a short/scaled viewport can scroll them
  while leaving the remaining panel space for note rows.
- `AnimatedNoteList` preserves note identity and insertion/removal animation.
  Rows remain plain `ListTile`s with the existing protection icon, title,
  labels, preview/share metadata, selection state and tap callback. Readability
  masking and availability handling are unchanged.
- Selected rows now use the existing `selectedSurface` token, and pointer hover
  uses the existing `subtleSurface` token. No card treatment, grid mode, pin
  control or row menu was added.
- Within these two owned files there is no grid mode, pin action or per-row
  menu. The queried panel currently provides search and label filters only.
  Do not introduce those capabilities in this slice.
- Text styles continue to inherit Flutter text scaling. Row title/preview line
  limits and label ordering are unchanged.

## Evidence and limits

The current 26 October 2026 graph generation finds `NotesListPanel` callers in
`NotesPage`, `NotesWorkspacePage` and `NotesQueryPanel`; `AnimatedNoteList` is
rendered by `NotesListPanel`. The owned source and relevant test paths report
`no_recorded_issue/metadata_changed`, so current source was read directly. The
graph and coverage response are best-effort, not proof of completeness.

`test/presentation/ui43/notes_list43_test.dart` covers the narrow 360x480,
200%-text query-scroll case, verifies New note and row callbacks, and checks
selected/hover token wiring. Root owns execution; the test has not been run.
Only the two allocated runtime files, this report and the allocated test file
were edited. `dart format` was run on those three Dart files; no shared Flutter
test, analyze, build, package, Git, browser, or device command was run.

## Pending after lead reference

Root should run the owned test and review the combined Web/Android runtime.
Remaining evidence includes current direct Home/Search/Android observations,
behavior with the real label filters at narrow/high text scale, and pointer/
keyboard focus presentation. The root agent owns all shared checks, browser/
ADB/Notion inspection and final integration.

Lead review: the initial half-height filter viewport left a106px note row at y418–524 in a480px host, so its center could not be tapped. The one-third cap retains query scrolling and makes room for that row; root rerun records the result.
