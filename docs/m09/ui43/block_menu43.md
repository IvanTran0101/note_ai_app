# UI43 block menu

## Implemented

- Native sheet height now follows its bounded parent constraint, which already
  accounts for the bottom sheet's safe area and keyboard insets. If the parent
  is unbounded, the menu caps itself to the remaining media height after insets
  and the 48dp host toolbar.
- Keyboard selection is surfaced in the native grid using the same restrained
  neutral highlight as the existing desktop rows. Hover and splash use that
  highlight too.
- Selection scrolling now computes the actual target row from the current
  choices, grid columns, scaled row height, grid padding and spacing, and the
  optional Media header. It scrolls the selected File row into view rather than
  jumping blindly to the bottom.
- Native list rows allow two scaled text lines. Grid rows continue to scale with
  text and switch to one column when the scaled label width requires it.
- The menu still exposes the existing 13 Basic blocks and existing File choice;
  no Page or Link to page action was added. Query text and insert callbacks stay
  with the existing controller/host.

## Reference boundary

The lead's direct Notion Web slash observation on 26 October showed a popup of
about 324×290px above the active block, 33px rows with a small left glyph and
14px title, a muted 12px “Basic blocks” caption, a thin rule before the next
section, a rounded neutral selected-row wash, and a “Close menu / Esc” footer.
The Web popup now uses the observed 324×290 size, a rounded selected row, and a
section rule. The “Type to search” prompt remains in the existing slash input;
that host/input is outside this ownership slice and its callback/query contract
is unchanged. Notion-suggested and other unapproved actions were not added.

The lead's current Android block-palette inspection is still pending. Native
spacing and behavior are adapted to safe available height, scaled text, and the
existing approved choices. This report does not claim Android palette parity or
a similarity score.

## Focused test coverage added

`test/presentation/ui43/block_menu43_test.dart` covers the observed Web popup
dimensions, allowed choice set, section separator, rounded selection highlight
and visibility at 200% text with a short landscape viewport and IME inset, and
scrolling the existing File choice into view on a short screen. The existing
UI41 test remains the evidence for query text staying out of the note.

## Checks and limits

- Formatted only the three owned Dart files and this scoped UI43 test file.
- Parent owns test execution, analysis, builds, browser, Android, and Notion.
  None of those shared checks ran here.
- `session_start.py`, `_agent_ops/`, and its closure protocol records are absent
  in this checkout. Existing root-owned continuity records were left unchanged.
- The Web slash observation is scoped to the popup. The Android palette and
  combined NoteFlow runtime still need lead review; no broad functional gate is
  claimed.

## Closure receipt

| Record | Resolution |
| --- | --- |
| `_agent_ops/CURRENT_TASK.md` | Not available; `_agent_ops` is absent in this checkout. |
| `docs/m09/ui43/block_menu43.md` | Updated with implemented behavior and remaining reference limits. |
