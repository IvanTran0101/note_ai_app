# Native settings choice review — 21 October 2026

## Scope and evidence

Read-only review of `lib/presentation/common/note_flow_settings.dart`,
`lib/presentation/common/note_flow_settings_choices.dart`,
`test/presentation/common/note_flow_settings_choices_test.dart`, and the
Theme/Language call sites in `lib/main.dart`. No runtime, test, build, device,
or browser actions were performed for this review.

The code graph is indexed only through 18 October. The new choices file and
test are untracked by that generation, while the settings surface and `main`
have changed since it. Graph lookup returned no node for the new symbol, so
this review relies on the current source and does not make completeness claims
from the graph.

## Result

**No source-level correctness blocker found in the reviewed path.** The change
reuses the existing caller-owned `DropdownMenuItem` values and callbacks. The
native compact control opens a scrollable modal sheet; a selected non-null
value closes the route and calls the existing callback once after the route
returns. Done, barrier dismissal, and dragging return `null`; the callback is
not called. The `context.mounted` guard avoids invoking a callback after the
settings widget has been disposed. Disabled controls cannot open the sheet,
and disabled menu items have no action. Web continues to use the existing
`DropdownButtonFormField` path.

The UI test source covers portrait and landscape (`412×914`, `914×412`), text
scale `1.0` and `2.0`, simulated top/bottom insets (`32`/`48`), disabled item
state, Done without a change, and a selected value producing one callback.
The bottom action is asserted above the simulated bottom inset. These are
source-level test assertions only; this review did not run them.

## Follow-up coverage gaps

- The test name says “dismiss”, but it dismisses via Done only. Add a focused
  barrier or drag-cancel case to lock in the documented null-result behavior.
- There is no test that disposes the settings owner while the choice route is
  open. The current mounted check handles this statically, but a regression
  test would protect the lifecycle edge.
- The test does not inspect the semantics tree. The trigger is a button and
  the options expose selected state through `Semantics(selected: ...)`, but
  keyboard/screen-reader traversal and the announced label/value combination
  remain unverified.

These are verification gaps, not demonstrated runtime defects. The root-owned
22 build and direct Notion-versus-app captures are still required before
claiming visual acceptance; this static review assigns no similarity
percentage and does not change either M09 gate.
