# AppFlowy editor compatibility source

Upstream: appflowy_editor6.2.0, https://pub.dev/packages/appflowy_editor/versions/6.2.0
Archive SHA256:c2367acdd93c7eeefaf6c58e5fed1a1c62cf02b8368102b786b5c6a0d1c583cf.
Original LICENSE is included unmodified; upstream offers MPL2.0 or AGPL3.0.
This compatibility adaptation is distributed under the MPL2.0 option. Its
modified source is included here. Input/selection/caret/undo algorithms unchanged.

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
