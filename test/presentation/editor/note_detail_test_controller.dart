import 'dart:async';

import 'package:note_ai_app/application/notes/note_application.dart';
import 'package:note_ai_app/domain/notes/note_document.dart';
import 'package:note_ai_app/presentation/notes/notes_application_controller.dart';

final class RichTestNotesController
    implements
        NotesApplicationController,
        DocumentNotesController,
        SnapshotNotesController {
  int richSaves = 0, plainSaves = 0;
  Completer<void>? saveGate;
  NoteDto? last;
  @override
  Future<List<NoteDto>> listNotes() async => last == null ? [] : [last!];
  @override
  get summaryConsent => null;
  NoteDto saved(
    NoteDto? previous,
    String title,
    String content,
    NoteDocument? document,
  ) => last = NoteDto(
    id: previous?.id ?? 'new',
    ownerId: previous?.ownerId ?? 'owner',
    title: title,
    content: content,
    document: document,
    createdAt: previous?.createdAt ?? DateTime.utc(2026),
    updatedAt: DateTime.utc(2026, 10, 15),
  );
  @override
  Future<NoteDto> saveDocumentSnapshot(
    NoteDto selected,
    String title,
    NoteDocument document,
  ) async {
    richSaves++;
    final captured = saved(selected, title, document.plainText, document);
    await saveGate?.future;
    return captured;
  }

  @override
  Future<NoteDto> createDocumentNote({
    required String title,
    required NoteDocument document,
  }) async {
    richSaves++;
    return saved(null, title, document.plainText, document);
  }

  @override
  Future<NoteDto> saveEditorSnapshot(
    NoteDto selected,
    String title,
    String content,
  ) async {
    plainSaves++;
    return saved(selected, title, content, null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
