# UI43 Summary and consent

## Reference basis

On 26 October 2026, the lead inspected the real Notion Web document at a
1280×720 viewport. This is an adaptation because the existing Summary and cloud
consent flow has no matching Notion workflow. The observed document uses a
quiet white surface, neutral text, muted supporting copy, light separators,
and restrained blue actions. Android inspection is still in progress, so this
report makes no Android comparison or parity claim.

## Changes

- Replaced the filled, rounded availability card with a plain inline status row
  and a light top separator. Supporting text now uses the readable body style
  and secondary text color.
- On compact layouts or when text is enlarged, the in-progress Summary label
  and Cancel action use separate rows. The existing progress, cancel key, and
  callback are preserved.
- Added a subtle divider between the consent disclosure and its session-scope
  summary. Supporting scope text uses the body style; dialog actions explicitly
  wrap downward and remain end-aligned on narrow widths. Existing title,
  disclosure, action order, scroll behavior, and consent result are unchanged.
- The content shimmer already follows `MediaQuery.disableAnimations`; the new
  widget test checks that it stops and resumes when the platform setting
  changes. No generation or consent service behavior changed.
- The summary failure copy still feeds the shared `NoteDetailSurface.error`
  row, which remains in the root-owned view boundary and was not modified.

## Added checks

`test/presentation/ui43/summary_ui43_test.dart` covers large text and a narrow
viewport with an IME inset, the availability row’s quiet surface and readable
text, the Cancel callback, consent action reachability above the keyboard,
explicit Allow versus Cancel/barrier results, and reduced-motion changes while
the shimmer is active.

Tests and runtime visual checks were not run by this worker; the lead owns
shared Flutter checks and combined Web/Android review. Web >=95% and Android
>=95% similarity remain unverified.
