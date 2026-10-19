# AppFlowy editor compatibility source

Upstream: appflowy_editor6.2.0, https://pub.dev/packages/appflowy_editor/versions/6.2.0
Archive SHA256:c2367acdd93c7eeefaf6c58e5fed1a1c62cf02b8368102b786b5c6a0d1c583cf.
Original LICENSE is included unmodified; upstream offers MPL2.0 or AGPL3.0.
This compatibility adaptation is distributed under the MPL2.0 option. Its
modified source is included here. Input/selection/undo algorithms stay upstream;
scroll and platform compatibility corrections are documented below.

## Changes

- pubspec: retain NoteFlow device_info_plus13; use modern file_picker13.1.0
  (old file_picker10 requires Win32v5, incompatible with current hardware plugin).
  A forced Win32v6 override failed real VM compilation and was rejected.
- file_picker_impl: current static single/multiple pick APIs, platform options.
  Preserve path-only export selection through existing file_selector, so picker
  adaptation never creates/truncates a file while merely selecting a location.
- image_upload_widget: async byte read and mounted fence for the updated picker.
  Image blocks are outside NoteFlow's13 Basic-block editor commands; M03 remains
  the owner of actual note attachments, picker validation and encrypted storage.
- delta_input_service: implement the newer Flutter TextInputClient callback
  onFocusReceived with Flutter's default false return. This is an interface
  compatibility callback, not an input/selection algorithm replacement.
- both input clients: return null for absent autofill scope (the SDK contract)
  rather than throwing from a platform callback. No autofill group is registered.
- keyboard_height_plugin0.3.0: same callback/dispose API, compileSdk34 instead
  of31. The old dependency failed Android AAR metadata checks with current
  Flutter embedding. Actual native keyboard behavior still needs proof.

All other lib/assets files are upstream6.2.0. Keep editing algorithms upstream;
SDK interface shims must be minimal, documented and covered by runtime proof.
Dependency resolver/compiler/real Web+Android proof is required before adoption.

- keyboard_service_widget: platform TextInputConfiguration carries readonly;
  editableNotifier reconfigures an existing connection after the frame when host
  access changes; dispose closes the platform connection after removing listeners.
  Upstream EditorState.apply remains the owner of transaction refusal. This
  prevents stale editable platform input while preserving selection/copy.
  On Web, a different starting block uses a fresh input connection: switching
  semantic DOM fields under the same client otherwise loses the destination
  editing buffer. Actual table navigation found this gap; test retains B1 while
  inserting after Tab. The text/selection/undo algorithms stay upstream.
- desktop_selection_service: instance-specific metrics debounce, cancellation
  on dispose and mounted/current-selection fences. This prevents a delayed SDK
  metrics callback from using a disposed/null selection after rotation/unmount.

NoteFlow's separate host proof decorates builders for text semantics (including
nested/table paragraphs) and defers DOM focus until framework/view focus settles.
The host uses upstream selection/transactions/delta diff/history, never a second
editing engine. Production adaptation and permission-fenced persistence remain
separate M09 phases; this package alone does not provide those contracts.

## P4 Web focus corrections (2026-10-16; acceptance pending)

- keyboard_service_widget: retain an already focused descendant on selection,
  tap, enable and keep-focus callbacks. Web host text fields own primary focus;
  the ancestor keyboard handler omits a competing DOM semantics focus target.
  Web tap does not close the client a semantic focus action just attached;
  the existing selection listener owns reconnecting when the block changes.
- non_delta_input_service: an equal cached editing value skips attachment only
  while its platform client is still attached. A title/dialog can replace that
  client without changing the document value; reconnecting must still work.
- page_block_component: the public shrink-wrap path uses its supplied scroll
  controller. The production Web host uses this stable bounded viewport to
  prevent indexed viewport semantics reparenting from blurring a cell on its
  first scroll. Native keeps the indexed viewport. Document limits still apply;
  Web performance at the maximum document size needs acceptance evidence.

The production host gives each Web text block a primary FocusNode beneath the
engine keyboard focus, and renders the slash menu in a separately owned
OverlayEntry. OverlayPortal reparenting lost focus during menu filtering.
No selection/delta/transaction/undo algorithm is replaced by these corrections.

## P4 native caret auto-scroll correction (2026-10-16; acceptance pending)

The copied EdgeDraggingAutoScroller could alternate forever when keyboard
resizing made its viewport smaller than the caret's edge-padding target. A
zero-duration recursive move also sampled an indexed viewport before its next
layout and starved native frames/input. Bound target padding by the viewport,
stop when moveTo does not advance, and await endOfFrame between instant steps.
Cap each step by the remaining edge distance; a minimum/smoothed step must not
overshoot a fractional target and reverse forever.
The caret center and existing selection/transactions/history remain unchanged.
Regression covers both axes, reverse directions, inside/outside targets and a
stalled ScrollPosition and fractional coordinates (24 VM checks). Native user interaction must still be
retested; passing this helper alone does not accept the product editor.

The host stops its scroller on unmount; the scroller checks that its Scrollable
is mounted before reading geometry. The indexed positioned-list notification
also checks mounted before publishing post-frame item positions. Fresh-frame
menu updates exposed these stale callbacks in three existing editor regressions;
the focused editor/menu/scroll/controls group passes37 checks after the fences.
## Table layout and user history (17Oct)

Automatic post-frame row-height measurements in `table_col.dart` preserve both
Undo and Redo stacks and stop after disposal. Structural table commands still
use the original transaction/history owner. Real Native QA reproduced row Undo
being trapped by repeated height-only history items; `table_history_test.dart`
covers initial paint/text-scale with no edits, one-step row Undo/Redo and a
layout change retaining Redo. This patch changes no stored document contract.

## P5 viewport and delayed selection scrolling (17Oct; acceptance pending)

`scroll_service_widget.dart` observes viewport constraints and requests current
selection scrolling after layout. Selection/resize requests invalidate older
post-frame and Native keyboard-delay callbacks; delayed scrolling reads fresh
selection rectangles. An idle editor explicitly requests a frame. Unmount
invalidates pending callbacks and stops scrolling. The platform scroll service
continues to own scrolling, including the existing desktop drag-scroll guard,
mobile drag-handle direction and disabled-auto-scroll behavior. No input,
document, transaction or history algorithm changes.

The widget regression runs on the host OS with Android layout metrics. It does
not simulate UniversalPlatform's Native Android branch; emulator rotation with
Gboard must independently verify that branch before acceptance.
