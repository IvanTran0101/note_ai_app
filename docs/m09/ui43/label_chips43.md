# UI43 label chips audit

## Status

Implemented the existing-feature adaptation released by the lead's current
direct Notion observation. The live note has no standalone label equivalent;
the instruction is to keep the existing below-title placement and neutral
compact chips, improve selected-state legibility, and retain native safe
targets. This is an adaptation, not a paired label-screen match. The requested
`docs/m09/ui43/REF_MAPPING.md` is absent; the shared supporting map is
`docs/m09/REF_MAPPING.md`.

## Current source baseline

- `NoteLabelChips` hides labels when the catalog is unavailable or the note is
  unreadable. It preserves the note/label key, optional caption and trailing
  widget. Display chips use a muted surface, compact density, six-pixel gaps,
  and one-line ellipsis within a width capped at 120–240 logical pixels.
- `LabelFilterBar` derives choices from readable notes and, when management is
  allowed, the actor's own active catalog. It clears deleted-label selections
  only if the same actor is still active after the frame. Filter selection,
  clear and manage actions keep their existing callbacks and keys.
- Filter chips currently use a fixed 12px text style and a low-alpha neutral
  selected fill. In dense non-single-line mode, chips and Clear/Manage controls
  opt into compact density and shrink-wrapped targets; Clear/Manage set a 32px
  minimum height. Single-line filters scroll horizontally.
- The prior label review says the standalone Notion page had no matching label
  property and records the existing neutral metadata adaptation. The shared
  reference map's search/filter captures include database-specific controls;
  those are not evidence for adding filter behavior here.

## Changes made

- Note chips retain their keys, muted fill, caption and trailing content. Their
  text-width cap now follows the available parent width, so a narrow card does
  not inherit a wider viewport's chip constraint.
- Filter chips keep the existing selection callbacks and keys. Selected chips
  now use a stronger neutral fill and border, primary text and a matching
  checkmark; labels use the theme's scalable label style.
- Dense mode keeps its compact horizontal padding while all interactive chips,
  Clear and Manage controls use standard density and padded 48px minimum
  targets. Filter and Clear text also use scalable theme styles.

## Scoped widget tests added

`test/presentation/ui43/label_chips43_test.dart` covers a long note label at
narrow width and 1.6x text scale, dense filter touch geometry, selected and
clear callback/semantics behavior, and keyboard activation with a long filter
label at narrow width and 1.6x text scale. The test was formatted but not run;
shared Flutter verification belongs to the lead.

## Graph and verification boundary

The Tier 2 graph was indexed at `2026-10-24T15:27:12Z`; exact-path coverage
reported `metadata_changed` for both owned Dart sources. I read the full current
source directly. Caller traces were heuristic leads and are not a completeness
claim. No tests, analysis, builds, browser checks, or Android checks were run.
Direct Android label-specific observation and combined visual review are still
pending with the lead.

No similarity percentage or PASS claim is made. `_agent_ops` and its
session-start/closure records are absent from this checkout, so no root-owned
continuity file was changed.
