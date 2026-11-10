# UI43 Settings adaptation

## Scope

This change refines the existing Settings surface and Theme/Language choices.
It does not add settings or change their values, callbacks, keys, or persistence.

## Evidence and changes

- The mapped Android 103 reference uses quiet section dividers, supporting text,
  and restrained controls. The lead's current direct native inspection adds a
  settled dark Settings screen with a centered semibold title, back control,
  divider below the header, bold section headings, muted multiline support
  copy, right-aligned controls, quiet row separators, and content above the
  three-button navigation bar. No new settings were observed or added.
- The compact Settings header now has a 48dp minimum instead of a fixed height.
  Its title shares a wrapping row with the existing 48dp back target, so scaled
  text can grow without overlapping the control.
- The native choice sheet header now grows with wrapped text and keeps Done in a
  separate 48dp target. Long labels are no longer truncated to two lines in a
  fixed-height stack.
- The choice sheet animates its bottom inset with the IME. Its existing choice
  list remains scrollable, and the Settings body remains a scroll view.
- Existing Settings dividers now use the surface's muted divider token in both
  compact and non-compact layouts. Their order and spacing are unchanged.

## Verification

Added cases in `test/presentation/ui43/settings43_test.dart` for a 320x640
viewport, 200% text, a simulated 220dp IME inset, long content, and a long
choice-sheet title. Tests were not run because shared test execution belongs to
the lead.

The adaptive values match the qualitative native Settings observations, but
the combined runtime review and both platform similarity gates remain pending.
This report does not claim parity or a pass.
