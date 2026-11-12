# UI43 Password-note form adaptation

Status: source and focused widget-test changes are ready for root review. The
password flow has no like-for-like Notion screen; this is an adaptation of the
current quiet document/form hierarchy described in `LIVE_REFERENCE.md`, not a
parity claim.

## Changes

- The dialog keeps its existing action title and uses the AlertDialog's single
  scroll surface. Removing the inner scroll view avoids nested scroll handling
  when the IME reduces available height.
- Narrow screens receive smaller horizontal insets. Form fields, labels,
  existing helper/error copy, and dialog actions remain readable at larger text
  scales; error copy is grouped in an announced error row. Password entries
  stay obscured, and all existing fields, actions, callbacks, and service calls
  are unchanged.
- The panel uses a quiet outlined surface with clearer title/status hierarchy.
  Existing action buttons wrap and keep a 48dp minimum height.
- Added `password43_test.dart` for one-scroll behavior, obscuring, helper and
  validation copy, IME-safe confirmation visibility at narrow width/large text,
  panel target sizing, and action callback preservation.

## Checks and limits

- Formatted only the two owned source files and this owned test file with
  `dart format`.
- Did not run Flutter tests, analysis, or builds; the root agent owns shared
  Flutter commands and runtime review.
- No permissions, password rules, storage, local-first behavior, constructors,
  public callbacks, or localization files were changed.
- The live reference releases this adaptation but does not provide a matching
  password screen. Web and Android visual review, integration, and both overall
  similarity gates remain for the lead; no PASS or percentage is claimed.
