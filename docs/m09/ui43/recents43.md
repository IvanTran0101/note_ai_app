# UI43 Home recent rail

## Change

`dashboard_recent_rail.dart` now gives card titles a clear primary hierarchy:
compact titles use 14 px semibold text, while wider layouts use 16 px semibold
text in the primary text color. The quiet white card surface, muted thumbnail
band, horizontal ordering, gaps, widths, note masking, and open callback remain
unchanged.

Card height now follows the scaled title line height and its one- or two-line
limit. The title remains bounded inside the card with an 8 px lower inset. This
removes the former compact-height cap of 164 px, which could clip two enlarged
title lines after their fixed divider-relative offset. At 200% compact scale,
the card grows to fit those lines while keeping the existing horizontal-card
layout and touch target.

## Reference basis and limits

`LIVE_REFERENCE.md` records the current Notion Web document's paper-white
surface and neutral typography, plus the direct Android Home inspection on
`Notion_API35_PlayStore` (1080x2400, dark theme, 26 October). Android Home has a
warm near-black surface, a horizontal carousel with neutral thumbnail tops, a
document glyph crossing the divider, and a two-line semibold title. The
existing NoteFlow tokens adapt those surfaces in dark mode; this patch aligns
title hierarchy and scaling while preserving the mapped carousel layout.

The Home reference is now directly observed, but a paired comparison against
the combined NoteFlow Web/Android runtime remains pending. This is not a Home
parity or similarity sign-off. No card width or gap values were changed without
a direct measurement of those values.

## Verification

`recents43_test.dart` covers the existing tap semantics/callback, primary title
weight, and a compact long title at 200% text scale. The scale case checks that
the card grows beyond the old cap and that the title occupies two lines inside
its card. The lead's analysis identified an unsupported `SemanticsNode`
assertion; it now reads the tap action from `getSemanticsData()`. The test was
not run by this worker because shared Flutter test execution belongs to the
lead. Combined runtime review remains pending.

No `>=95%` or PASS claim is made by this worker.
