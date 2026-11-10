# M09 independent UI gap review — 19 October 2026

## Decision

**No similarity percentage assigned. No acceptance decision.** This review now
includes the saved, lead-captured Notion Android screens and the latest saved
NoteFlow Web selection/settings states, in addition to local reference files.
I did not operate the live Notion browser or AVD myself. The lead's live Web
measurements are second-hand evidence in this review; the saved Notion images
are directly inspected screenshots, not a paired current-build comparison.
Findings must be revisited with equivalent current NoteFlow screens before
visual changes are treated as final.

The previous 96.2/100 ratings remain withdrawn. Filenames, test passes and
different UI states are not similarity evidence. Do not use this report to
claim either platform has reached 95%.

## Images inspected

### Supporting Notion reference images

- Web: `hinhanh/UI_web_ref/notion-web-001-home.jpg`,
  `notion-web-007-page-view.jpg`, `notion-web-008-search-overlay.jpg`,
  `notion-web-011-share-panel.jpg`, `notion-web-014-display-style.jpg`.
- Android: `hinhanh/UI_android_ref/001_01_home_recents-favorites-private.png`,
  `014_06_recent-final-page.png`,
  `103_08_settings-language-offline-privacy-portrait.png`,
  `106_07_share-settings-default-portrait.png`,
  `109_07_comment-editor-formatting-toolbar-portrait.png`,
  `215_search-landing-recent-pages-portrait.png`.

### NoteFlow captures inspected

- Latest Web interaction captures: `output/playwright/p6-parallel1-web-selection.png`
  and `p6-parallel1-web-state.png`. The latter visibly shows the selection
  toolbar painted over the open Appearance and language Settings dialog.

- Latest final7 native captures: `output/m09/p6-final7-native-home.png`,
  `p6-final7-native-table.png`, `p6-final7-native-table-input.png` and
  `output/playwright/p6-final7-recipient-viewer-note.png`.
- Earlier Web captures: `output/playwright/p6-visual5-web-note.png`,
  `p6-visual5-web-search.png`, and `p6-ui6-final-note.png`.
- Earlier native captures: `output/m09/p6-visual5-native-search.png`,
  `p6-visual5-native-landscape.png`, `p6-visual4-native-settings.png`,
  `p6-visual4-native-share.png`, and `p6-ui6-native-toolbar.png`.

The earlier Web owner/edit captures are visual5/UI6 predecessors. The newer
parallel1 Web captures show owner selection and Settings interactions, but the
Settings capture predates the route-dismissal source change. The final7 Web
image is a recipient Viewer table state, while final7 Android images are owner
states; those are different builds/roles/states and cannot be treated as a
paired comparison. Search and Share captures are still predecessors and need
fresh captures after current UI changes.

### Lead-captured Notion Android screens inspected

- `output/m09/notion-native-reference-oct19.png`: Home with profile and four
  navigation pills, horizontal Recents cards, compact Private rows with
  disclosure/title/more/add affordances, and the bottom search/Ask AI/new-note
  rail.
- `output/m09/notion-native-search-oct19.png`: Search heading, Ask AI row,
  Today and September 2026 groups, result title plus location, and the search
  field above the visible keyboard. This screenshot does not show per-result
  right-aligned update dates.
- `output/m09/notion-native-detail-oct19.png`: open note with back/share/more,
  a large emoji and title, checklist content, and the bottom action rail.
- `output/m09/notion-native-share-oct19.png`: native share sheet with invite
  field, member row, General access and Advanced sections, and Share link.
  Publish/public-link controls are Notion-only here and are outside NoteFlow's
  existing sharing contract.

### Lead-reported live Notion Web measurements

These measurements were sent by the lead after direct live Web inspection; I
did not operate the page, so they are not first-hand measurements by this
reviewer: 270px sidebar, 44px header, 720px content column, 40px/48px w700
title, 16px/24px body, 224×110 selection popup with three 32px rows,
324×289 slash menu with 34px compact rows, 458px Share panel at x≈723/y44,
and a thin-outlined 150×28 Preferences dropdown. The live Search screenshot
with preview pane did not show right-side result dates.

## Screen-by-screen gaps

| Priority | Screen / platform | What the references show | What the saved NoteFlow capture shows | Gap and next visual action |
| --- | --- | --- | --- | --- |
| P0 | Evidence setup / both | Lead-captured actual Notion Android screenshots now cover Home, Search, note detail and Share. The lead's live Web measurements are also available as second-hand findings. | Latest NoteFlow Web screenshots cover selection and Settings layering; latest Android screenshots are final7 predecessors and do not represent the current diff. | Capture equivalent current NoteFlow states on Android and Web with build, viewport/device, text scale, theme, orientation, keyboard and insets. Keep similarity `—` until paired evidence exists. |
| P1 | Workspace and note list / Android | Lead-captured `notion-native-reference-oct19.png` confirms a profile plus four navigation pills, horizontal Recents cards, then compact Private rows with disclosure, note icon/title, more and add affordances; a search/Ask AI/new-note rail sits at the bottom. | `p6-final7-native-home.png` has the `LOCAL DEV · owner` banner, three navigation pills, Recents cards, All notes controls, label filters, Manage labels and a two-column note grid. It is an older build capture, not a screenshot of the current diff. | Recents cards are a shared pattern; main-list hierarchy, row density, navigation silhouette and visible instrumentation differ. Keep NoteFlow-specific label/view controls, but refine their grouping and default list presentation using existing features. Capture current Android after source changes before judging the remaining gap. |
| P1 | Note canvas / Android | Lead-captured `notion-native-detail-oct19.png` shows back/share/more, a large emoji and title, checklist content, and the persistent bottom action rail. | `p6-final7-native-table.png` is an owner table test state with back/sync/share/protection/comments/AI/more, a large title, table content, collapsed metadata and add/undo/redo controls. | These are not equivalent document states. The visible action header is much denser in NoteFlow; compare a current ordinary note and selected-text state. Consider grouping existing actions in the existing overflow so key actions remain available without a crowded top row. Do not add emoji/checklist behavior solely from this screenshot. |
| P1 | Workspace shell and note canvas / Web | `notion-web-001-home.jpg` shows a 270px-class navigation rail, a slim breadcrumb/action header and a centered reading column; `notion-web-007-page-view.jpg` shows a page title and compact content rows. | `p6-visual5-web-note.png` has a similarly sized rail and centered note column. The latest final7 screenshot `p6-final7-recipient-viewer-note.png` is a 1280×900 Viewer table screen, not an owner/edit screen. | The visual5 note is the closest saved Web pairing, but it is stale and uses different content; the final7 Web capture is not a valid owner/edit pair. The `LOCAL DEV` banner also changes the top silhouette. Re-capture current final7 owner note at the same viewport as live Notion before judging vertical offset, reading width, font hierarchy or action spacing. |
| P1 | Search / Android and Web | Lead-captured `notion-native-search-oct19.png` shows a Search heading, Ask AI row, Today/month result groups, title/location rows and the keyboard-open bottom search field. It has no visible per-result dates. The lead reports that the live Web Search reference with preview pane also shows no right-side dates. | `p6-visual5-native-search.png` and `p6-visual5-web-search.png` are older NoteFlow builds. Current source groups mobile results by date and suppresses per-row dates in mobile search; there is no post-change capture. | Re-capture current Android and Web states with matching query/keyboard/preview conditions. Compare grouping, row typography, spacing and dismiss affordance. The old local Web date display is a historical reference only, not evidence of a current mismatch. Keep existing search/filter semantics. |
| P2 | Selection toolbar / Android | `109_07_comment-editor-formatting-toolbar-portrait.png` shows a compact horizontal editor action rail immediately above the Android IME. | `p6-ui6-native-toolbar.png` shows selected text, an inline floating format popup and the IME; the screen was captured from UI6, not final7. | These are similar editing contexts but not identical toolbar functions/placement. The reference rail includes controls outside the approved selection-format scope; do not add them from the image. Capture current final7 selected-text and keyboard states, then compare only shared formatting controls, type hierarchy, touch sizing and safe-zone placement. |
| P2 | Sharing / Android and Web | Lead-captured `notion-native-share-oct19.png` shows a tall native sheet with title, invite field, member row, General access/Advanced and primary Share link; Web `notion-web-011-share-panel.jpg` is a compact panel anchored to the top action bar. | `p6-visual4-native-share.png` is an older centered Manage sharing modal. The current diff changes compact presentation to a bottom sheet and desktop Web to an anchored panel, but no post-change capture was provided. | Compare a fresh current capture for sheet height, header/form/member spacing and Web anchoring. Preserve NoteFlow's existing invite/role/revoke flow. Do not add Notion-only Publish, public-link or General access capabilities. |
| P2 | Settings / Android and Web | No direct Notion Android Settings capture is among the inspected native images. The lead reports a live Web Preferences row with flat label/helper text and a thin outlined dropdown measuring 150×28. | Current source lays out a 150×28 outlined Web dropdown in `note_flow_settings.dart`; old `p6-visual4-native-settings.png` shows an Appearance and language subpage with a transient network error. | The outline matches the lead-reported live Web measurement and is not a defect. Capture the current settings root/subpage on each platform before comparing group spacing, control alignment or helper-text hierarchy. Treat the old red message only as transient error-state evidence. |
| P1 | Selection overlay and Settings modal / Web | Notion styling is not the basis for this interaction check; the Settings dialog should remain usable while editor selection is active. | `p6-parallel1-web-state.png` visibly shows the selection toolbar painted above the Appearance and language dialog, covering part of the Theme row. `p6-parallel1-web-selection.png` shows the same toolbar in its intended selection state. | The screenshot proves a layering/dismissal defect in that captured build. The current editor diff now tracks route-current changes and dismisses transient editor UI at `rich_note_editor.dart:62-74,166-177`; no post-change screenshot proves the fix. Re-capture with active selection, open Settings, and verify the toolbar disappears while selection state and modal controls remain usable. |
| P1 | Safe zones / Android | Reference images show the Android status area and gesture bar; editor/search controls sit above the bottom system area. | The inspected native NoteFlow captures show gesture navigation. `p6-final7-native-table-input.png` places editor actions above the visible keyboard; the gesture bar remains visible. | Gesture-mode screenshots give limited positive evidence only. No 3-button navbar capture was inspected, so bottom clearance in that mode remains unknown. Verify toolbar, sheet actions and final scroll content above both gesture and 3-button navigation, with keyboard open/closed and portrait/landscape. |
| P1 | Safe zones / iOS | The current local reference set is Android/Web; the required top status/notch/Dynamic Island safe zone is a NoteFlow platform requirement. | No iOS app capture or device was inspected. | iOS remains unverified. Preserve top status/notch/Dynamic Island clearance and bottom Home Indicator handling; do not mark the platform complete based on Android evidence. |

## Source locations for the implementation team

These line references identify the current UI owners and relevant layout
boundaries. The graph generation is 2026-10-18. Parent coverage checks on 23
planned code paths reported `metadata_changed` with no recorded parse gaps. My
additional checks found the same status on eight tracked relevant paths; the new
share surface is untracked by the graph. I read current source directly for
material claims.

- Compact shell bars, Android bottom navigation and safe-area placement:
  `lib/presentation/workspace/workspace_shell.dart:324-350`,
  `:529-562`, `:736-742`, `:943-970`.
- Web dashboard header/search and compact bottom search dock:
  `lib/presentation/dashboard/dashboard_page.dart:444-480`, `:588-629`.
- Note list content column and responsive width:
  `lib/presentation/notes/notes_list_panel.dart:53-77`.
- Note document/editor content constraints and vertical spacing:
  `lib/presentation/notes/note_detail_surface.dart:146-174`, `:234-280`.
- Selection formatting controls and their menus:
  `lib/presentation/editor/selection_toolbar.dart:17-80`, `:156-200`.
- Selection overlay and route-dismissal owner:
  `lib/presentation/editor/rich_note_editor.dart:62-74,166-177,304-390`.
- Existing share dialog and responsive invite form:
  `lib/presentation/notes/share_management_dialog.dart:192-295`.
- Compact share sheet and recipient rows:
  `lib/presentation/notes/share_management_surface.dart:10-270`.
- Existing settings surface, bottom-sheet/dialog selection and safe area:
  `lib/presentation/common/note_flow_settings.dart:10-25`, `:31-84`.

## Prioritized correction/evidence order

1. Use the lead-captured Notion Android references and the lead's live Web
   observations already recorded above. Capture equivalent current NoteFlow
   states, including the Web owner/editor; the final7 Web Viewer screenshot
   is not sufficient for that comparison.
2. Remove environment-only `LOCAL DEV · owner` instrumentation from the visual
   comparison setup (or use an authorized production-like build where it is
   absent); keep development diagnostics intact in their intended context.
3. Compare and refine the shared shell, home/list density and open-note canvas
   first. Keep product-specific sections, access guards and all existing actions.
4. Re-capture current search, selection/IME, share and settings states. Compare
   equivalent states and adjust typography, spacing, icon sizing, surfaces and
   panel geometry only.
5. Check Android gesture and 3-button navigation, keyboard, rotation and final
   scroll. Record iOS safe zones as unverified until an iOS environment exists.
6. Only after paired evidence supports >=95% similarity independently on Web
   and Android may the lead move to functional acceptance. Do not estimate,
   average platforms or declare PASS from this report.

## Current peer-diff review — read-only

This review was performed against the current working-tree diff from HEAD. The
M09 source changes are uncommitted and were already present when I resumed this
review; I changed no source files. There are no commit boundaries here that
let me attribute each existing line to a specific agent. The lead's live Web
measurements below are second-hand input from the lead, not a live inspection
by this reviewer. I visually inspected the lead-captured native Notion
screenshots listed above; I did not drive the locked AVD. These captures
support reference descriptions but do not complete platform acceptance.

### Reference-to-code alignment observed

- **Desktop note width:** the peer diff adds a 720 logical-pixel Web editor
  maximum in `lib/presentation/notes/note_detail_surface.dart:153-162`, which
  matches the lead-reported 720-pixel live Notion reading column. This is a
  sound geometry match; verify the rendered editor column after the next Web
  capture.
- **Selection menu:** `SelectionToolbarLayout` is 224×110 and lays out three
  32-pixel rows plus dividers/padding at
  `lib/presentation/editor/selection_toolbar_layout.dart:20-24,57-96`.
  The horizontal control widths fit the 208-pixel inner row: five 32-pixel
  icon buttons plus a 44-pixel size button use 204 pixels. Mobile controls
  retain the 48-pixel target in `editor_icon_button.dart:32-48`.
- **Slash menu:** `BasicBlockMenu` uses a 324×289 desktop popup and a 34-pixel
  minimum row, with a 32-pixel header and 40-pixel footer at
  `lib/presentation/editor/basic_block_menu.dart:13-24,47-56,102-157,210-244`.
  These dimensions match the lead-reported live Web menu. The 13-block list
  will scroll inside the remaining space; native menu sizing remains the
  pre-existing 48-pixel row treatment.
- **Share panel:** at a 1280-pixel viewport, the 426-pixel content plus 32
  horizontal dialog padding yields a 458-pixel panel; right inset 100 and top
  inset 44 place it at approximately x=722/y=44. This matches the lead's
  reported x=723/y=44, 458-pixel Web reference in
  `lib/presentation/notes/share_management_dialog.dart:198-241`. It is an
  intentional match, pending a rendered capture.
- **Safe zones:** the shell's new top `SafeArea` and mutually exclusive bottom
  handling are at `lib/presentation/workspace/workspace_shell.dart:324-355`;
  `_buildCompactBottomBar` itself applies a bottom `SafeArea` at `:540-559`.
  The branches do not visibly apply bottom padding twice in source. The
  compact toolbar/menu still needs actual gesture and 3-button device evidence.

### Actionable issues and risks

| Priority | Finding | Evidence | Recommended follow-up |
| --- | --- | --- | --- |
| P1 | Settings modal was occluded by editor selection UI in the saved Web capture. | `output/playwright/p6-parallel1-web-state.png` shows the toolbar over the Theme row. The current diff adds route-current dismissal in `lib/presentation/editor/rich_note_editor.dart:62-74,166-177`. | The route hook is a plausible fix for this dialog route, but the capture predates it. Re-capture the same state and verify toolbar dismissal and modal control accessibility before closing the issue. |
| P2 | Web Preferences dropdown border is not a defect. | The lead reports a flat label/helper row with a right-aligned 150×28 dropdown and confirms the live control has a thin outline. `lib/presentation/common/note_flow_settings.dart:137-175` uses that size and a divider-colored outline. | Keep the current subtle border. Compare a fresh Settings capture for alignment, typography and spacing; do not remove the outline based on the old review. |
| Note | Search row dates are not a verified mismatch. | Current `dashboard_note_card.dart` dense mode omits per-row dates; the live Web Search screenshot with preview pane has no right-side dates visible. Older local NoteFlow `p6-visual5-web-search.png` showed them. The native Notion Search capture groups by date and shows no row dates. | Do not restore dates solely to match a stale local capture. Preserve them only if a current NoteFlow requirement needs them; compare current grouped results and preview states. |
| P2 | Compact single-line label filter may become cramped at narrow widths or large text scales. | `lib/presentation/labels/label_filter_bar.dart:110-127,129-147,162-183` keeps the Manage button outside the horizontal chip scroller and fixes the filter icon to 32×48. | Visually check Vietnamese labels and large text in a narrow Android viewport; ensure Manage remains reachable and does not force a horizontal overflow. This is a source-based risk, not a reproduced failure. |
| P2 | Web style comparison uses development captures with a visible environment banner. | The local Web captures `p6-visual5-web-note.png` and `p6-visual5-web-search.png` visibly include `LOCAL DEV · owner`; the current final7 Web capture is Viewer role. | Capture current owner/edit Web UI from a production-like presentation or exclude the development marker from the measured app region. Preserve diagnostics in their intended development context. |

### Integration and contract review

- The dense dashboard row still routes pin through the existing callback and
  keeps it disabled for shared, protected or unavailable notes at
  `lib/presentation/dashboard/dashboard_note_card.dart:217-242`. I found no
  new permission grant or data-write path in that diff.
- The query panel still feeds `queryNotes` with its `readable` predicate and
  only derives label choices via `visibleLabels` at
  `lib/presentation/labels/notes_query_panel.dart:21-24,65-74`. The new
  `queryControls`/`filteredEmpty` presentation slots in
  `lib/presentation/notes/notes_list_panel.dart:26-38,135-162` do not themselves
  alter note selection, persistence or authorization.
- The inspected share-dialog edits change width, padding, typography and
  status presentation. The caller still passes the existing note identity and
  secured session generation in `lib/presentation/notes/note_detail_sharing.dart:148-156`;
  no role/access contract change was found in these visual diffs.
- Parent/source files are already dirty from earlier work. The separate
  `_pendingSavedNote` condition in `note_detail_document.dart` and loading
  state edits in `notes_workspace_page.dart` are outside this visual review's
  acceptance scope; they need the lead's normal diff review/regression later.
- No tests, builds, browser or emulator were run for this review. The current
  pass is a static source review only, not runtime verification.

## Reviewer limitations

- I did not operate live Notion Web or Android in this agent task. I inspected
  the saved lead-captured native screenshots; Web dimensions and behavior are
  lead-reported. These are not a complete paired current-build assessment.
- Several NoteFlow views are visual4/visual5/UI6 predecessors. Any current
  implementation changes require fresh captures before they can be accepted.
- The inspected Android captures show gesture navigation only. Three-button
  navigation and iOS safe zones remain unverified.
- No code, test, build, browser, emulator or app state was changed by this
  reviewer.
