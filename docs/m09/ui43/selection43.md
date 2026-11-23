# UI43 selection toolbar

## Status

Web popup refinement implemented from the lead's current direct Notion
observation. The live reference now includes current Android Home, note, and
Search observations, but no Android selected-text toolbar state; this patch
makes no Android-specific toolbar visual claim. The source target files,
assigned test, and this report are the only files in this worker's ownership.

## Source baseline

- `SelectionToolbar` builds formatting actions from one captured
  `RichSelectionSnapshot`. Existing handlers retain the same adapter,
  controller, `onPopupOpen`, and dialog guard paths.
- The current Web reference is a narrow white, elevated, rounded popup at the
  upper-right of selected text. It uses Normal Text and a chevron on top, then
  color/B/I/U/clear, then link/strike/code/equation/More. Notion-only Comment
  and AI controls are excluded. The approved size12–48 control stays alongside
  the existing format actions.
- Web remains a fixed 192 x 110 three-row surface. The existing size button is
  retained at the end of the second row; Highlight stays reachable through
  More, and equation-to-text remains available when an equation is selected.
- Compact Web icon buttons are 28 x 28. The second row's five icons and the
  36 px size button fit the 176 px inner width. Non-compact buttons retain
  48 x 48 targets.
- Native compact and short-editor layouts use one horizontally scrollable
  48 px rail. Other layouts wrap controls and increase their estimated height
  for narrow widths and larger text scales.
- The non-owned `rich_note_editor_overlays.dart` positions the Web popup to
  the right or left of the selected text and below or above it, clamps it to
  the popup bounds, and clips/scrolls content. Native compact placement docks
  above the keyboard/system area. No changes to that integration are in scope.
- Existing formatting actions include text style, text/highlight colors,
  bold, italic, underline, strikethrough, inline code, link, equation, clear,
  equation-to-text where applicable, and font-size presets 12/14/16/18/24/32,
  custom 12–48, and reset. Dialogs continue to use the captured selection and
  existing route/snapshot guards.

## Changes

- Removed the extra text-fields glyph from the Web style row so it presents the
  observed `Normal Text` label and chevron.
- Disabled Material's elevation surface tint on the popup; its light surface
  stays paper-white while the existing dark surface remains unchanged.
- Let color names flex within their dialog row so localized or enlarged labels
  can wrap instead of forcing horizontal overflow.
- Preserved action callbacks, selected/mixed semantics, the captured snapshot,
  dialog guards, size presets/custom/reset, and the 48 dp native button target.

## Focused test added (not run)

- Web only: assert the 192 x 110 surface, three-row grouping, Normal Text row,
  size control placement, existing actions and Highlight in More, plus all
  approved size presets/custom/reset entries.
- Constrained viewport: at 360 x 640, 2x text and a 280 px bottom inset, open
  and scroll the color chooser to red, apply it to the captured range, and
  check for layout exceptions. On VM, also check the 48 px rail/button target.
- The lead runs the shared Flutter suite. No Flutter test, analysis, build,
  browser, or Android run was performed by this worker.

## Reference evidence and limits

- `docs/m09/ui43/LIVE_REFERENCE.md` records the lead's current direct Notion
  Web observation at 1280 x 720 and current Android Home/note/Search states.
  The file has no current Android selected-text toolbar comparison. This is a
  grounded scoped Web refinement, not a paired similarity score.
- The mapped Android formatting-rail image and historical NoteFlow capture do
  not certify the current Android toolbar. Native toolbar appearance remains
  for the lead's selected-text comparison; this patch preserves its layout.

## Verification boundary

The code graph is generation `2026-10-24T15:27:12Z`. Tier 2 coverage returned
no recorded issue for the three owned source files and relevant overlay/test
paths, with `metadata_changed`; I reread each owned source in full before
editing and read the relevant current call sites directly. This best-effort
coverage is not a completeness guarantee. The assigned test file is added but
unrun. No analysis, builds, browser, Android, Notion, or Git mutations were
run. One read-only Git status check confirmed existing dirty/untracked paths;
I did not modify them.

## Next step

Lead review and shared test execution remain pending. Android toolbar/dialog
review should use the lead's upcoming direct observation; the current patch
preserves existing native layout and only adds constrained-dialog wrapping.
The combined UI and both platform similarity gates remain unverified.
