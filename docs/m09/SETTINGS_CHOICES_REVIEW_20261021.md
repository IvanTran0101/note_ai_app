# M09 native settings choice surface — 21 October 2026

## Scope

Changed only the existing native compact Theme and Language choice presentation.
The existing items, typed values, current selection and `onChanged` callbacks
remain supplied by the current settings screen. Web and desktop retain their
existing dropdown implementation; no setting or option was added.

## Implementation

- `lib/presentation/common/note_flow_settings.dart` selects the new control only
  when `!kIsWeb && NoteFlowLayout.isCompact(context)`. The native compact
  settings caption is 16sp/400; its Web style remains unchanged.
- `lib/presentation/common/note_flow_settings_choices.dart` presents the
  current choice in an outlined, keyboard-focusable button. It opens a
  scrollable native modal sheet with a 44dp handle, centered setting label,
  localized Done/Xong action and the original options in a rounded surface.
- Rows retain each `DropdownMenuItem`'s enabled state and value, expose the
  selected state semantically and keep a minimum 48dp touch target. Done,
  swipe dismissal and barrier dismissal return no value and do not call the
  settings callback. A selected value closes the chooser and invokes the
  existing callback once.
- The sheet uses current light/dark surface, divider and text tokens, adapts to
  available width/height, scrolls when its contents exceed the viewport, and
  applies the bottom safe area.

## Reference evidence and pending verification

The directly inspected Notion Android reference is
`output/m09/notion22theme-reopen.png`. It shows a nearly full-width neutral
sheet with a centered Theme title and Done action, a short handle, and three
choices in a white rounded group with a checkmark on the selected row. The
previous NoteFlow candidate `output/m09/app20native-theme-menu.png` showed the
Material popup overlaying the Settings content near the right edge. This change
addresses that visible presentation gap.

No build or tests were run in this slice; the lead requested that shared
verification wait until handoff. The lead must build/install this source, then
inspect the native sheet at baseline, text scale 2, landscape, light/dark and
both Android navigation modes. Web/Android similarity percentages remain
unverified until the paired visual review is complete.

The code graph snapshot was indexed 18 October 2026 and marked this source's
metadata as changed. I read the current source and its settings call sites
directly before editing; graph coverage is not being used as proof of current
source.
