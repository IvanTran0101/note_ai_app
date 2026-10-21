# M09 Web editor visual audit — 21 October 2026

## Scope and decision

This audit covers the Web rich-note editor and its selection toolbar only. It
does not assign a similarity percentage. The editor still has a concrete
vertical-geometry gap, while the latest heading-spacing fix and current toolbar
state have not yet been captured from a built, current source revision. Web
similarity therefore remains unverified.

## Evidence used

- Direct Notion Web inspection on 21 October at 1480×668, dark theme: measured
  H1/H2/H3 as 30/24/20 px, Segoe UI weight 600, line-height 1.3, with text
  advances 132.85/110/91.66 px. The measured heading block top spacing was
  30/26/22 px. Keep these coordinate types distinct: editable rectangle origins
  were y=290/365/428.2; text-range origins were y=291.2/366.2/429.4; visible
  glyph-ink tops were approximately y=301/375/437. The following paragraph's
  glyph-ink top was approximately y=479.
- NoteFlow `p6-parallel15-web-rich21.png` is the latest supplied rich-content
  capture. It is from source 15 and includes a 20 px LOCAL DEV strip at the top.
  After removing that strip, the comparable text glyphs are approximately at
  y=304/383/452/493. The first bullet is corrected in this capture; the older
  `p6-parallel13-web-rich21.png` reads “irst bullet” and is unsuitable for a
  content-density comparison.
- `p6-parallel9-web-selection.png` shows the Web selection popover, but it is a
  source-9 capture, not a current source-15/16 capture. Current direct Notion
  Web inspection measured a 224 px overall selection panel and a compact
  Normal Text row (14 px text, 16.8 px line height; 176×28 px inner row).
- Current workspace source was read from `document_span.dart`,
  `editor_renderers.dart`, `rich_note_editor.dart`, and
  `selection_toolbar.dart`. The graph generation is 18 October and these paths
  report `metadata_changed`; source was checked directly. The source-16
  heading-builder change is not proven by either supplied runtime screenshot.

## Confirmed visual gap: rich-content vertical rhythm

| Shared item | Notion editable rect origin | Notion text-range origin | Notion glyph-ink top | NoteFlow source 15 glyph-ink top, minus 20 px dev strip | Ink delta |
| --- | ---: | ---: | ---: | ---: | ---: |
| H1 | 290 | 291.2 | ~301 | 304 | +3 px |
| H2 | 365 | 366.2 | ~375 | 383 | +8 px |
| H3 | 428.2 | 429.4 | ~437 | 452 | +15 px |
| Following paragraph | — | — | ~479 | 493 | +14 px |

Compare glyph ink to glyph ink: the editable-box and text-range origins are not
glyph tops. In the source-15 pair, ink begins about 3/8/15/14 px lower in
NoteFlow after removing the dev strip. The drift grows through the heading
sequence, so this rich-content state is not yet demonstrated as visually
matched. The configured Web heading sizes are 30/24/20/18 and top paddings are
30/26/22/18; those box settings do not by themselves establish the rendered
ink positions. The body style is 16 px with 1.5 line height, consistent with
the measured 16/24 reference and not a known gap here.

`document_span.dart` supplies the inline heading style and source 16 now also
sets `TextStyle(height: 1.3)` on the public heading builder. This is a
reasonable fix candidate because the engine reapplies block defaults after
inline decoration, but it has not been visually verified. The supplied source
15 image predates it. Rebuild the exact current source and recapture the same
note at the same viewport; measure the four glyph origins again. If the
  increasing drift remains, tune the block/paragraph spacing responsible for the
  rendered deltas. The configured top-padding numbers match the measured
  30/26/22 px CSS spacing, but that does not prove where the rendered ink lands;
  changing them without a fresh rendered comparison could move the headings in
  the wrong direction.

The font comparison also needs rendered evidence. Notion's measured style is
Segoe UI 600; NoteFlow requests Roboto Medium (`NoteFlowHeading`, `w500`). Since
the families differ, the nominal weight numbers alone do not prove the visible
severity. Compare NoteFlow's actual heading advances and ink thickness against
the Notion advances above before choosing a font/weight adjustment.

## Selection toolbar: current evidence is stale

The current implementation builds three desktop rows and includes the approved
font-size control. Its compact style row uses 14 px text, an 18 px chevron and
the Text-fields glyph; compact action icons are 18 px. The supplied source-9
capture looks consistent with the measured 224 px, three-row Notion structure,
but cannot certify the current source. Capture a current-source selection
state and compare its outer bounds, row heights, spacing and selected-text
alignment to the direct Notion state. Do not count Notion-only AI/comment
controls as missing NoteFlow functionality.

## Next editor-only checks

1. Build the exact working revision that contains the heading-builder
   `height: 1.3` change and capture the same synthetic content at 1480×668,
   dark theme, with the 20 px dev strip accounted for.
2. Compare H1/H2/H3/paragraph glyph-ink tops (not editable-box or range
   origins), plus actual heading advances and ink thickness, against the direct
   Notion measurements above. Keep content and block order identical.
3. Capture the selection toolbar from that same revision and record its
   viewport, selection range and popup bounds. Reuse the same selection in
   Notion before comparing.
4. Keep Web and Android similarity scores blank until the full required
   screen/state matrix has current paired evidence; this editor-only audit is
   not a whole-platform score.
