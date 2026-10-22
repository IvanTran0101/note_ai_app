# M09 Label UI review — source27

## Scope

Refined only the presentation of the existing note-label property, label
chooser, and label manager. The standalone Note page reference has no matching
label property, so the note detail uses a small neutral metadata row: a muted
label icon/caption, quiet chips, and the existing choose-label action styled as
a compact text control. This adapts the existing app feature without adding a
database or changing independent-note flow.

The shared `NoteLabelChips` defaults remain caption-free for dashboard cards.
Long label names are visually clipped within a bounded chip while retaining
their full semantic text. On note detail, the existing action remains visibly
named “Choose note labels”; its minimum height is 36 logical pixels on Web and
48 on native platforms. Manager surfaces use smaller headings, a neutral add
action, tighter row spacing and separators.

## Behavioral boundary

- The editor still changes one label per selection and invokes the same
  `setAttached` operation.
- `LabelActionFence`, owner/actor/readability/manage checks, stale-note checks,
  deleted/unavailable label detachment, busy state and error handling are
  unchanged.
- The label manager retains its existing create, rename, delete confirmation,
  retry/conflict resolution, and sync status actions.
- Dashboard label chips use the same compact neutral chip treatment, but do not
  gain the detail caption or editing action.

## Verification

- The four owned Dart files were formatted with the repository Dart SDK.
- Flutter tests, analyzer and builds were not run in this subtask because the
  lead requested that parallel Flutter work wait for an idle-runtime window.
- Existing widget coverage in `test/presentation/labels/label_widgets_test.dart`
  targets the still-visible “Choose note labels” action and attach/detach flow;
  the lead should run it with the combined slice.
- No claim is made here about direct paired visual acceptance or the M09 95%
  Web/Android gates.
