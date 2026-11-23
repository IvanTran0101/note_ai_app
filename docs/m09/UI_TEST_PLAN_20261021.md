# M09 focused UI checks after source16

Status: planning only. No tests were run and this is not a PASS report. Keep broad functional regression queued until direct paired Notion/NoteFlow evidence establishes at least 95% visual similarity on both Web and Android.

## Current findings

| Test | Current assertion | Finding and smallest correction |
| --- | --- | --- |
| `test/presentation/dashboard/dashboard_page_test.dart:869` — “workspace desktop Search opens a dismissible overlay” | At lines 914–917 it expects 1008×704 at top 78 for a 1200×900 viewport. | The current production overlay in `lib/presentation/dashboard/dashboard_page.dart` caps width at 600, uses `height = min(viewport - 80, 704)`, and has top inset 60. Update only width to 600 and top to 60; retain height 704 for this viewport. This matches the directly inspected Notion Search with its preview pane hidden (600px wide, top 60). Keep the existing dismiss and query assertions.
| `test/presentation/notes/note_detail_surface_test.dart:292` — “composes editor fields and action bar at 1024x700” | At lines 307–312 it expects form 704 and content field 692. | Do not replace these values globally with 720. `notes_theme_tokens.dart` defines fallback widths 704/692 and the Web document width 720. `note_detail_surface.dart` selects 720 on Web; `note_detail_editor_form.dart` also uses the 720 Web content width. Split or make expectations explicit by target: non-Web fallback 704/692; Web 720. Add a separate rich-editor-builder assertion for its 720 Web column if that path is included in the Chrome suite.
| `test/presentation/workspace/workspace_shell_test.dart:299` — “expanded width shows a labelled sidebar with an active item” | Line 307 expects 270. | Already matches `WorkspaceShell.sidebarWidth = 270`; leave it unchanged. Existing assertions also cover labels and active destination.

## Small regression checks to schedule after the UI gate

1. **Recent-card access masking.** No readability/protection assertion exists in `test/presentation/dashboard`. Add one focused DashboardRecentRail/Home test with an unreadable note whose title is a recognizable secret. Assert the secret title is absent and the protected-note label is shown. This matters because `DashboardRecentRail` masks through its `readable` predicate while note DTO queries do not redact returned titles. Preserve the DTO/query contract.
2. **Revocation while the actual block picker is open.** `editor_controls_test.dart` already covers touch block choices after popup focus changes; `editor_sheet_guard_test.dart` covers generic sheet closure on access/document/generation/dispose changes. The combined actual `RichNoteEditor` picker path is not covered there. Add one narrow test: open Add block, revoke edit access or advance access generation before choosing, then assert the picker closes and the document remains unchanged.
3. **Geometry sanity.** Keep the corrected desktop Search check. If adding one responsive assertion, use a small viewport and verify the capped width/height plus bottom clearance; do not add a second broad layout matrix here.

## Execution boundary

- These are focused UI/regression checks, not a substitute for comparing the current Web and native Android screens directly with Notion.
- After source16 is packaged/current in each runtime, capture matched Search, Home/Notes, note editor and menu states with viewport, text scale, theme and safe insets recorded. Keep Android gesture and 3-button navbar checks distinct.
- Run only the small affected UI checks once both visual similarity gates are met. Broader protection, sharing, offline and final regression remain queued.
- Similarity stays unverified until evidence supports a reasoned percentage for each platform; do not tick 95% from widget test results.
