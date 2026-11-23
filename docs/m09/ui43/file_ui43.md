# UI43 — file rows, Upload chooser, and PDF navigation

## Evidence and boundary

The 26 October direct Web reference in `LIVE_REFERENCE.md` shows a plain inline
file glyph, 16px filename, and smaller muted size on one line, without a card.
It records Web only; Android inspection remains in progress. Existing file
actions, upload sources, PDF callbacks, access checks, transfer behavior, and
canonical removal remain unchanged.

## Changes

- Reduced the attachment glyph from22px to18px to keep the inline row quiet.
  The filename and smaller muted size stay together on the first line; the
  existing non-Ready status stays below it. No card or new file action was
  added. Light/dark colors continue to come from the active color scheme.
- Made the native Upload sheet respect its available height after safe-area and
  keyboard insets. Its content scrolls when needed, and option labels can wrap
  at large text sizes instead of being ellipsized to one line. The four sources
  and their callbacks are unchanged.
- PDF page controls wrap at narrow widths, keep each navigation target at least
 48dp, and scroll inside a bounded short-height host. Page and busy-state
  callback behavior is unchanged.

## Added coverage (not run by this worker)

- File row hierarchy, no-card presentation, small glyph, muted size, and light/
  dark theme colors with a long filename.
- PDF controls at narrow width, 220% text scale, and constrained height;
  verifies scroll access, 48dp navigation targets, and page callback dispatch.
- Native Upload sheet at narrow width with an IME inset and 220% text scale;
  verifies the chooser can scroll to the last option and its label is not
  truncated.

Root owns test execution and combined Web/Android review. This is an
implementation report, not a direct Android comparison, visual acceptance, or
similarity score. The Web/Android >=95% gates remain unverified.
