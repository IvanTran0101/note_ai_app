# UI43 label chooser and manager

## Status

The scoped layout refinement and widget tests are in place. The lead's current
reference says labels have no standalone Notion equivalent, so this is a quiet
adaptation of existing label controls rather than a parity claim. The reference
now includes Android note, Home, and Search observations; additional screens and
combined runtime checks remain pending. Root owns running this widget test and
the combined platform checks.

## Reference and scope

- Read `MUST_REMEMBER.md`, `docs/m09/ui43/OWNERSHIP.md`,
  `docs/m09/REF_MAPPING.md`, `docs/m09/CURRENT_WORK.md`, and the lead's
  `docs/m09/ui43/LIVE_REFERENCE.md`.
- The local mapping has no label chooser or manager screen. The live reference
  explicitly keeps existing label capabilities, below-title placement, neutral
  compact controls, readable selected state, and native safe targets.
- The two original owned source files were read in full. The shared dialog
  layout helper was then added within this task's expanded ownership. Code
  graph generation is `2026-10-26T09:59:10Z`; coverage marks the original
  sources `metadata_changed`, the helper and test `not_tracked`, and this docs
  subtree excluded. I checked the changed paths directly; the graph is not used
  as a completeness claim.
- No product constructor, permission rule, write path, callback, or label
  identity behavior was changed.

## Changes

- Chooser and manager dialogs now use theme surfaces without Material tint,
  quieter padding, and scrollable dialog content.
- Both dialogs use the same small presentation helper to size their lists
  from the available viewport, safe padding, IME insets, and text scale.
- Their list areas are bounded by the current available height after view
  padding and keyboard insets, with text scale included in the reserved space.
  A small minimum list area keeps controls available; the dialog body can
  scroll on more constrained screens.
- Manager label names still wrap to two lines; a tooltip exposes the full name
  when it is truncated. Duplicate names remain separate rows with their
  existing IDs and per-row controls; no identifier or uniqueness rule was
  added.
- Rename and delete confirmations use the same safe, scrollable surface while
  preserving their existing actions and ordering. Native controls retain their
  existing 48dp minimum targets.

## Focused coverage added

- Manager with duplicate and 64-character names at narrow width, 200% text
  scale, and simulated keyboard insets; non-owner rows stay hidden, rename and
  delete dialogs remain operable, and cancellation does not write.
- Chooser with duplicate and long names at narrow width, increased text scale,
  and simulated keyboard insets; each label remains a separate selectable row
  and cancel leaves the note unchanged.
- The chooser action stays hidden when management permission is absent or the
  note belongs to another owner.

## Verification boundary

- `dart format` ran on the two owned sources and the assigned widget test.
- The widget test, analyzer, builds, browser, Android, and Notion checks were
  not run by this worker. Root runs shared checks.
- No Web/Android similarity percentage or visual acceptance is claimed.
