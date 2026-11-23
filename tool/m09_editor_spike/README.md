# M09 editor engine proof

Separate synthetic-only app (`app.noteflow.qa.m09_editor_spike`). It does not
read/write the production NoteFlow account store or contact the cloud.

From this directory:

```powershell
flutter pub get
flutter run -d chrome
flutter run -d emulator-5554
flutter test
```

Candidate: vendored AppFlowy6.2 with documented dependency/SDK compatibility
changes in `../../packages/noteflow_editor_engine/NOTEFLOW_PATCHES.md`. The
original license and modified source are included. Host builder decorators
provide semantics/nested-cell focus; table navigation uses engine selection.

Round trip verifies in-memory library JSON only. Durable encrypted persistence,
canonical document adaptation, guarded sync and final toolbar/style are later
M09 phases. Raw library JSON is not a production storage/wire contract.
Toggle-collapse mutation here is a renderer proof; production collapse state
will be ephemeral actor UI state. Default engine commands/clipboard are not the
production13-command menu or plain-paste policy.

See `../../docs/m09/REF_MAPPING.md` and `DOCUMENT_CONTRACT.md` for implementation
targets, and `CURRENT_WORK.md` for verified receipts and pending work.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
