# Android source23 visual review — 21 October 2026

## Scope and evidence

I inspected the four supplied source23 screenshots at 1080×2400:

- `output/m09/app23theme-light-threebutton.png`
- `output/m09/app23search-query-gesture.png`
- `output/m09/app23note-gesture.png`
- `output/m09/app23selection-ime-gesture.png`

The expected original Notion files were absent when this review began. Root
subsequently saved valid light references at
`output/m09/notion25-theme-light-reference.png` and
`output/m09/notion25-note-light-reference.png`. They visibly show Light
selected in the reopened Theme sheet and the equivalent Note title/body. Use
the PNGs for geometry; the Theme XML bounds are stale/transformed. The direct
Root subsequently captured a direct Search reference at
`output/m09/notion25-search-query-reference.png`; it shows the same result
title as `output/m09/app25-search-query.png`, although the entered query text
differs between captures. The first Selection screenshot,
`output/m09/notion25-selection-light-reference.png`, showed only a caret and
`Select all` popup. Root subsequently captured the valid same-word selection
reference at `output/m09/notion25-word-selected-light.png`; it shows the word
`comparison` highlighted, the OS selection action bubble, and Notion’s
formatting rail above the IME. No `board-matrix` local file was found under
`docs/m09`.

## Visible source23 observations

| Screen/state | What the app capture shows | Visible gap / comparison limit |
| --- | --- | --- |
| Theme, light | White rounded sheet over a dimmed screen; centered `Theme` heading, blue `Done`, three `System` / `Light` / `Dark` rows and a trailing checkmark. The valid direct Notion PNG also has Light selected, a centered heading, blue `Done`, a rounded three-row card, and nearly matching horizontal card margins. After accounting for the disclosed 52.5px development-strip offset, sheet heading and card top align closely. | NoteFlow labels the first row `System`; Notion says `Use system setting`. The NoteFlow option card remains visibly taller after vertical-offset alignment, with slightly taller rows and a larger/heavier checkmark. Notion’s parent `Settings` title is visible behind the sheet, while the app screenshot shows a different underlying context. App uses three-button navigation and Notion uses gesture navigation, so bottom insets are not directly comparable. |
| Search, query, gesture + IME | Large bold `Search` heading; filter icon, `test` and `QA-M04-Web` chips, `Manage labels`, a `Results` label, one note row, then a bottom query field above the keyboard. | The direct Notion capture has an `Ask AI` query row instead of the app's label filters, and its typed query is incomplete; both show the same exact result title. Result-row horizontal text geometry is close, but the surrounding screen states differ. Both have gesture navigation and the keyboard visible. |
| Note, gesture, light | Same two-line title `M09 UI comparison Android` and body `Local first comparison` as the valid light Notion reference. Both wrap the title identically and use similar title/body left alignment. NoteFlow adds a cloud-off status icon, a collapsed `Labels, files & note details` row and bottom Search / Ask notes / Edit actions. | The Notion reference continues with Heading 2 and `/`; the app capture instead shows collapsed metadata. Compare only the shared title/body and shell. App has an extra cloud-off action between Back and Share; bottom action geometry is similar, with product-specific `Ask notes` vs `Ask AI` labels. Both captures use gesture navigation. |
| Text selection, gesture + IME | The word `comparison` is actively highlighted; a full-width formatting rail shows Text, color, bold, italic, underline, strike, `17 pt` and code controls above the keyboard. | The valid Notion PNG shows the same word selected, with two selection handles, a floating Cut / Copy / Select all / Read aloud / Ask Gemini bubble, and a flat formatting rail directly above the IME. The app capture has no visible selection handles or floating action bubble. Its rail orders Text / color / B / I / U / strike / `17 pt` / code; Notion shows left chevron / AI / color / comment / reaction / B / I / U / strike / keyboard. Notion-only AI/comment/reaction actions are excluded; the approved `17 pt` control remains an intentional NoteFlow adaptation. |

All four app captures include a visible `LOCAL DEV · owner` band between the
system status area and app content. Root confirmed it is a disclosed,
development-only strip and is excluded from comparison anchors. Do not count
it as a product UI mismatch; account for its 52.5px image-space offset when
comparing vertical coordinates. It does not establish which product UI
adjustment is needed.

### Theme component comparison — direct Notion PNG

Compared `app23theme-light-threebutton.png` with the valid
`notion25-theme-light-reference.png` at the same 1080×2400 portrait image size.
Both visibly select Light. The modal title is centered, the Done action sits at
the upper right in blue, the handle is centered, and the option card has a
similar wide inset and rounded corners. The panel and card colors are both
light neutral and visually close. After excluding the development-only strip,
the modal header and option-card top align closely.

Remaining visible differences are localized to the card: app text says
`System` while Notion says `Use system setting`; app rows are slightly taller,
leaving the card bottom lower even after the top alignment; and the selected
checkmark is heavier/larger. The parent Settings heading is visible through
Notion’s dimmed background but not in the equivalent position in the app
capture. The app image uses three-button navigation and the Notion image uses
gesture navigation, so the bottom system region is not a matched component.
The app sheet controls remain above its three-button navbar in this capture.
This single component pair does not establish a platform percentage or cover
other screen states.

### Note component comparison — direct Notion PNG

Compared `app23note-gesture.png` with `notion25-note-light-reference.png`.
Both are light-theme portrait captures of the same note title and body and use
gesture navigation. The title wraps at the same word, its left edge and the
body’s left edge are closely aligned, and the visible title/body scale and
weight are similar. The app’s top content is shifted down by the disclosed
52.5px development strip; discount that strip when comparing the upper
anchors. The bottom action rows sit above the gesture bar in both images.

The reference then shows Heading 2 and `/`, while the app instead shows the
collapsed `Labels, files & note details` row. This content-state mismatch
prevents judging body-block spacing or the lower editor canvas as a paired
comparison. NoteFlow’s cloud-off indicator is an existing sync-status action;
its position is an adaptation, not a missing Notion control. The bottom pill
uses the existing `Ask notes` label where Notion shows `Ask AI`; compare its
shape/alignment without treating the labels as a capability request. This
shared title/body check is not a whole-screen percentage.

### Selection state comparison — direct Notion PNG

Compared `app23selection-ime-gesture.png` with
`notion25-word-selected-light.png`. Both are light portrait captures with the
same word `comparison` selected and the IME visible. Both place a full-width,
flat formatting rail immediately above the keyboard; neither rail overlaps the
gesture navigation area. The NoteFlow rail visibly exposes its approved
`17 pt` size control, which has no direct counterpart visible on the Notion
rail in this state.

The Notion image adds a floating contextual-action bubble above the selection
and two colored range handles. These are absent from the app image. Notion’s
rail orders controls differently and includes AI/comment/reaction buttons,
which are Notion-specific and not a request to add to NoteFlow. The NoteFlow
rail instead places Text/color and `17 pt`/code controls among its formatting
actions. The selected text, light theme, keyboard and safe-zone match make this
a valid comparison for the shared selection state, but the differing action
sets prevent treating the screenshots as pixel-identical or assigning a whole
screen percentage.

### Search result comparison — direct Notion PNG

Compared `app25-search-query.png` with
`notion25-search-query-reference.png`, both 1080×2400 portrait captures with
Light theme, gesture navigation and the IME visible. The result title text is
exactly `M09 UI comparison Android` in both. A dark-ink pixel-bound estimate
(grayscale threshold below 110) for the title glyphs is 462×33px at app bounds
x=151..612, y=643..675, versus
450×34px at Notion bounds x=145..594, y=689..722. This indicates a close
title size, with the app glyph run about 2.7% wider and its left edge 6px
farther right. It is an ink-bounds measurement, not a full layout score.

The query text itself is not a controlled match: the app field shows the
trailing visible text `JI comparison Android` (the leading portion is not
visible in this capture), while Notion's Ask AI row shows the partial input
`M09 UI comprisn Androi`; both result rows nevertheless contain the same full
title. The app shows label filters and `Manage labels` above
`Results`, while Notion shows its Ask AI row. Because that content hierarchy
differs, result-row vertical position is not used as a similarity metric.
Both search fields remain above the IME and the gesture indicator is visible
below it. This pair supports a direct comparison of the shared result title
and basic keyboard safe zone, but does not establish whole-screen similarity.

The valid Theme pair’s most concrete measured icon-size gap is the selected
checkmark: root measured the app glyph at 45×34 physical pixels and the Notion
glyph at 29×29. The proposed visual correction is to reduce the icon from 24px
to 16px while retaining the 48dp row touch target. This is one component-level
correction, not evidence that the Android platform has met its ≥95% target.

## Safe-zone evidence

- The Theme capture is in three-button mode; the sheet controls end well above
  the visible Android navigation bar, with no overlap in this screenshot.
- Search and selection show the IME and gesture navigation. The search field
  and formatting rail remain above the keyboard; the gesture indicator remains
  visible below it.
- The note’s bottom action bar is above the gesture indicator in the captured
  state.
- These captures do not cover landscape, enlarged text, every sheet/dialog,
  keyboard dismissal, Android three-button selection, or iOS. They are not a
  complete safe-zone check.

## Similarity status

No screen-level percentage is assigned from these component comparisons. Theme,
shared Note title/body, active-range Selection and the shared Search result
title now have direct paired visual reviews; Search query content and surrounding
hierarchy do not fully match. Android remains **unverified** against the ≥95%
target. The previous
96.2% rating is withdrawn per `docs/m09/VISUAL_REVIEW.md`; it is not carried
forward. A current direct Notion capture for each specified state and an
equivalent app state are required before a reasoned per-screen estimate can be
made. No full-platform PASS is claimed.

## Supplemental source24 Home safe-zone observation

The additional `output/m09/app24-home.png` and `output/m09/notion24-home.png`
were inspected after the source23 captures. Both are 1080×2400 portrait home
screens, but the app is light and Notion is dark, and the visible note sets and
home navigation differ. The comparison is therefore descriptive only; no
similarity estimate is assigned.

The source24 app home shows the bottom Search / Ask notes / Edit actions above
the gesture indicator. The final visible note row is also above that action bar,
so this capture shows no bottom gesture-nav overlap. The screenshot is a list
view, not the requested grid view; no grid safe-zone conclusion can be drawn.
This single portrait capture does not cover three-button navigation, landscape,
text scaling, keyboard, or scroll-to-end states.

Visible component differences in this light/dark unmatched pair include a
shorter top navigation row in NoteFlow, NoteFlow's horizontal recent cards and
its filter/list-grid controls, and Notion's private-page rows with expand,
more, and add affordances. The development-only strip remains excluded from
anchors. This is descriptive evidence only, not a checklist to add Notion-only
capabilities to NoteFlow.

## Selection handles and contextual-action bubble — source diagnosis

This is a read-only source diagnosis for the paired active-range captures
`output/m09/app23selection-ime-gesture.png` and
`output/m09/notion25-word-selected-light.png`. The code graph was unavailable
for this scope (`Transport closed`) and its last indexed generation was
18 October 2026, so the findings below use direct reads of the current named
source files; they do not claim graph coverage or a runtime reproduction.

### Drag handles: a confirmed mobile-style misconfiguration

`RichNoteEditor._buildEditor` passes `documentEditorStyle(context)` to
`AppFlowyEditor` (`lib/presentation/editor/rich_note_editor.dart:257-273`).
The style factory always calls `engine.EditorStyle.desktop(...)`, including
on native phones (`lib/presentation/editor/editor_renderers.dart:110-142`).
That desktop constructor sets `mobileDragHandleBallSize` to `Size.zero`,
`mobileDragHandleWidth` to `0.0`, and `dragHandleColor` to transparent
(`packages/noteflow_editor_engine/lib/src/editor/editor_component/style/editor_style.dart:136-140`).

The selection service itself is enabled: `AppFlowyEditor` defaults
`disableSelectionService` to false and wraps its body in
`SelectionServiceWidget` (`.../service/editor.dart:43,337-346`). On Android,
that wrapper chooses `MobileSelectionServiceWidget`
(`.../service/selection_service_widget.dart:45-65`). For a non-collapsed
selection, its left/right handle builders request selection rects and construct
`MobileSelectionHandle`, passing the editor style's handle width, ball width
and color (`.../service/selection/mobile_selection_service.dart:259-322`).
Thus the relevant service is not disabled; its mobile handles are configured
with zero dimensions and a transparent color. This is a confirmed source-level
cause consistent with the missing visible handles in the app screenshot. The
static trace does not prove whether selectable rects were available for that
particular screenshot.

### Contextual-action bubble: no wired mobile renderer found

The visible NoteFlow formatting rail is built by the host's
`engine.FloatingToolbar` (`lib/presentation/editor/rich_note_editor.dart:346-380`)
and its docked selection overlay. The Android long-press selection handler
sets `selectionExtraInfoDisableFloatingToolbar: true` at selection start and
while extending the range (`.../selection/mobile_selection_service.dart:770,
818`). The engine's `MobileFloatingToolbar` listens to that key and would
suppress its own contextual toolbar, but a scoped source search found only its
class/constructor declaration and no construction call site in
`packages/noteflow_editor_engine/lib`. Separately, the host formatting rail
checks `selectionExtraInfoDisableToolbar`, a different key, so its appearance
is not contradicted by the mobile-specific flag
(`.../find_replace_menu/search_service_v3.dart:6`,
`.../toolbar/desktop/floating_toolbar.dart:139-154`).

The supplied `contextMenuBuilder: EditorClipboard(adapter).contextMenu` is
forwarded by `SelectionServiceWidget` only in its Desktop/Web branch; the
Mobile branch constructs `MobileSelectionServiceWidget` without that builder
(`.../service/selection_service_widget.dart:45-65`). Therefore the current
source has a clear custom formatting-rail path but no wired Android contextual
action-bubble path. The absence of the Notion-style Cut/Copy/Select all/Read
aloud/Gemini bubble is not explained by a proven Android UI setting; this
editor path does not currently attach its custom context-menu builder to the
mobile selection service, and the engine mobile toolbar class is not mounted
in the scoped source. Runtime/OS-level behavior remains unverified. Notion's
Read aloud and Gemini actions are platform/Notion-specific and are not
recommendations to add NoteFlow capabilities.

No runtime source, device state, tests, browser or emulator were changed or
used for this diagnosis. The evidence supports correcting the native handle
style configuration first, then checking the existing mobile selection path.
It does not authorize adding Notion-specific actions or establish an Android
similarity percentage.
