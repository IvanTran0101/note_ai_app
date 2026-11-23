# UI43 cards43 — compact Home note rows

Date: 26 October 2026

## Reference basis

- Today's authenticated Notion Web observation is recorded in
  [LIVE_REFERENCE.md](LIVE_REFERENCE.md). It establishes a paper-white canvas,
  quiet neutral hierarchy and restrained supporting visuals. The appended
  current observations also cover the Web sidebar and a directly inspected
  Android Home in its warm near-black theme: Private-list icons are muted,
  titles are clear and about16ish, and Recents uses a separate horizontal
  thumbnail-card carousel.
- Home-specific supporting references mapped by
  [REF_MAPPING.md](../REF_MAPPING.md):
  `hinhanh/UI_web_ref/notion-web-001-home.jpg` shows compact document rows and
  a softly highlighted current row; `hinhanh/UI_android_ref/001_01_home_recents-favorites-private.png`
  shows title-only Favorites/Private rows with muted document icons. These are
  visual references, not fresh direct Home captures.
- The mobile row is an adaptation for independent NoteFlow notes. No nested
  page disclosure, child-page action, or new Home capability was added. The
  separate recent-card rail remains owned by `recents43`.

## Change

The compact Home row previously used an 18 px title on narrow Web layouts, an
18 px icon with a 16 px gap, a square selected surface, and no explicit focus
color. It now uses a 16 px compact Web title (the measured native phone title
remains 15.5 px), a 16 px muted note/lock icon with an 8 px gap, a 6 px row
corner, and a restrained focus tint. The existing 48 px row and compact pin
targets remain. Text scaling, one-line ellipsis, labels, semantics, selection,
note activation, pin callback, and title-only Home content are preserved.

## Focused coverage

Added `test/presentation/ui43/cards43_test.dart` for the compact Home row's
hierarchy, selected/hover/focus styling, muted icon, 48 px targets, semantics,
callbacks, hidden preview, and a narrow viewport at 1.8 text scale. The worker
did not run the test; shared Flutter commands are owned by the lead.

This is a scoped source refinement only. No current paired NoteFlow Home
runtime capture was available to this worker, and neither platform similarity
percentage is established by this change. The direct Home observations improve
the reference basis but do not replace the lead's combined Web/Android review.
