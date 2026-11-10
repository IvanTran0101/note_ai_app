# Source 18 `blockPadding` review

## Scope and evidence

Reviewed the current source in `editor_style.dart`, `page_block_component.dart`,
`editor_renderers.dart`, and `editor_block_padding_test.dart`, using direct source
reads. The repository graph could not be refreshed in this session (the lead
reported `Transport closed` from index/coverage calls), so this is a bounded
source review, not an exhaustive call-site audit. I did not run tests, builds,
or UI checks; the five focused widget tests are reported by the lead and were
not independently rerun here.

## Findings

### Non-blocking API limitation: `copyWith` cannot clear the callback

`EditorStyle.copyWith` preserves the old callback with
`blockPadding: blockPadding ?? this.blockPadding`
(`packages/noteflow_editor_engine/lib/src/editor/editor_component/style/editor_style.dart:181-206`).
Therefore `style.copyWith(blockPadding: null)` keeps the existing callback and
cannot restore the static `padding` fallback. This matches the null-as-keep
pattern used by several other optional fields in the same method and does not
affect the current NoteFlow call, which constructs a new style with either the
Web callback or `null` (`lib/presentation/editor/editor_renderers.dart:110-124`).
If callers need to clear a callback through `copyWith`, the API needs an explicit
clear mechanism; otherwise document this null-as-preserve behavior.

### No correctness or compatibility blocker found in the reviewed paths

- `blockPadding` is optional in the base, desktop, and mobile constructors, so
  existing constructor calls retain their previous behavior
  (`editor_style.dart:10-18`, `114-126`, `147-169`).
- Both page-rendering branches select the per-node value and fall back to the
  original editor padding when it is absent
  (`page_block_component.dart:58-86`, `95-137`).
- The NoteFlow callback is Web-only and selects only bullet, numbered, and todo
  list blocks; other Web blocks keep vertical 8px outer padding and native
  keeps the prior static 4px phone padding (`editor_renderers.dart:110-124`).
- The callback is a small membership check over three block types. It does not
  alter document data, commands, selection, or persistence. The todo builder
  separately retains its Web 3px internal vertical padding
  (`editor_renderers.dart:55-58`), so the page-level zero padding does not mean
  the todo's complete rendered spacing is zero.
- The added tests cover default/null behavior, callback preservation/replacement,
  both shrink-wrap modes, and fallback padding
  (`editor_block_padding_test.dart:10-75`).

## Limits

This review does not establish visual spacing in source18 on Web or Android,
performance under a large document, coverage of every external package
consumer, or either M09 similarity threshold. The lead should use installed
source18 captures for the visual decision.

## Source19 native Share header adjustment

Following the lead's direct Notion Android21 comparison (1080x2400, 420dpi),
the native Share sheet title is now18px instead of20px, the drag handle is44dp
instead of40dp, and the large-text layout threshold scales18px text while
retaining the existing adaptive header height. No other Share styling, layout,
safe-area, guard, action, or data behavior was changed. These edits are included in the lead's packaged19 build; the reviewer did not
run that build or runtime verification.

## Source20 native Search adjustment

The matched native Search captures (`output/m09/p6-parallel18-native-search-match.png`
and `output/m09/notion-native21-search-match.png`) are both1080x2400 at420dpi,
font scale1. The lead measured the query result title's dark ink as546x41px in
the app and450x34px in Notion. Source20 reduces only compact native Search
query result titles from16px to13.3px and uses medium weight to match the
reference ink. The blank-query landing remains16px regular; Web, Home and other
card callers retain their previous typography. Only the non-empty native query
Search `Results` heading now uses14px regular muted text; Web and blank-query
landing styling remain unchanged. Compact native Search also uses the existing
`compactHomeSurface` background; the Web Search background condition is
preserved. Search filtering, ordering, pinning, note access and actions are
unchanged. This is source20 only: no build or runtime verification was
performed by this review.

### Follow-up scope correction

The first source20 draft keyed the smaller title to all mobile Search and would
also have shrunk the blank-query landing. This was corrected before freeze by
adding the optional `DashboardNoteCard.searchQueryResult` flag, passed only
when the compact native Search query is non-empty. The blank-query landing
keeps its existing16px regular title; Web, home and other callers are unchanged.

## Source20 paired native Search visual check

Compared `output/m09/p6-parallel20-native-search-match.png` with the actual
Notion Android reference `output/m09/notion-native21-search-match.png`. Both
are1080x2400 at420dpi and font scale1. The NoteFlow capture is 3-button
navigation; Notion is gesture navigation. The app capture has a52.5px local
DEV strip, and the keyboard render differs, so those pixels are not app-to-app
layout evidence.

Using grayscale <120 within the result-title row, the exact same title
“M09 UI comparison Android” measures app x150..612/y643..675 (463x33px) and
Notion x145..594/y688..722 (450x35px). Source20's13.3px medium query-only title
is much closer to the earlier app18 measurement546x41px: its remaining width
is13px (2.9%) larger, its ink height is2px shorter, and its left edge is5px
farther right. The document-icon bounds are app x65..96 and Notion x56..92;
the title-to-icon ink gap is about54px versus52px, so most of the title's
horizontal offset comes from the row's overall inset, not a materially
different icon-to-title gap. This is a one-title measurement, not a platform
score.

At grayscale <220, the `Results` label measures119x28px in the app and115x29px
in Notion. Its app left edge is11px farther right. Sampled body background is
(249,248,247) in both captures, matching the intended light surface.

The app's result row shows its existing pin action and “Local first comparison”
content preview; Notion shows “in Private”. Notion's “Ask AI” suggestion row is
also absent from NoteFlow. These are capability/content differences, not a
reason to add Notion AI or remove existing NoteFlow actions/data. The query text
visible in the app field starts “JI comparison Android”, while the reference
field starts “M09 UI comparisonAndroi”; the screenshot notes ADB dropped some
input characters. Despite that input mismatch, the displayed result title is
the same. Absolute row y positions differ substantially because of the app DEV
strip and Notion-only Ask AI row; do not treat them as aligned vertical anchors.

This check confirms the query title size correction materially reduced the
measured gap, but the native Search screen is not pixel-identical. It does not
establish a whole-platform similarity percentage or certify other screens,
navigation modes, or safe-zone states.

## Source21 Android green perimeter diagnostic

The source21 `app21grid-threebutton.png` and `app21grid-pure.png` captures both
show a thin lime-green outline at the physical image perimeter, including the
status and navigation-bar areas. The pure screenshot still has the outline, so
it is present in the captured display image rather than being drawn by the
uiautomator XML overlay.

The first read-only ADB attempt could not reach the target emulator: the device
list was empty and property/settings queries failed. No emulator process was
running then, so the Android `settings`, `dumpsys`, and `logcat` state was
unavailable at that time.

The bounded source search found no app-level lime perimeter implementation or
`debug.layout` / `showLayoutBounds` literal in `lib`, the editor-engine `lib`,
or `test`. `lib/main.dart:1554` has
`debugShowCheckedModeBanner: false`. The engine's
`EditorStateDebugInfo.debugPaintSizeEnabled` defaults to false
(`packages/noteflow_editor_engine/lib/src/editor_state.dart:19`); its visible
debug branch is limited to selection handles and paints red
(`packages/noteflow_editor_engine/lib/src/render/selection/mobile_basic_handle.dart:122-124`).
This does not explain a full-device green outline.

At the first attempt, Android view-debug rendering was only a hypothesis. The
follow-up below checks its relevant flags directly; no cause is inferred from
the screenshots alone. The outline must be identified before these captures
are used as clean UI references. No removal or M09 acceptance claim is made.

### Read-only emulator follow-up

The target emulator now reports boot complete. No explicit enabled value was
reported for `debug.layout`, the StrictMode visual-flash property, or the
queried HWUI/SurfaceFlinger debug paint flags (profiling, dirty regions,
overdraw, layer updates, non-rect clips, show-updates, CPU overlay). Thus
“Show layout bounds,” a StrictMode visual flash, and those GPU debug overlays
are not supported as the source of the green perimeter by the current property
state. Filtered logcat did contain StrictMode `NonSdkApiUsedViolation` entries
from Google Play services and system-server StrictMode dropbox events; these do
not establish a visual overlay or explain the perimeter.

Accessibility is disabled (`accessibility_enabled=0`); no enabled service is
listed, touch exploration is off, and display magnification is inactive. The
window dump shows the standard top and bottom `ScreenDecorOverlay` windows
visible, while `ShellDropTarget` has no surface and is invisible. The decor
windows are present, but this read-only evidence does not show that they draw
the lime frame. **Cause remains unknown**; no runtime setting or device state
was changed.
