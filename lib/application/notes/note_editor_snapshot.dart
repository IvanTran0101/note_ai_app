import 'note_dto.dart';

/// The editor can explicitly review this fresh projection. Never logs content.
final class NoteEditorChanged implements Exception {
  const NoteEditorChanged(this.current);
  final NoteDto current;
  @override
  String toString() => 'NoteEditorChanged';
}
