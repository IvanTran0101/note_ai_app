import '../../domain/labels/label_projection.dart';
import '../notes/note_dto.dart';
import '../../domain/notes/note_body.dart';
import 'local_label_state.dart';

typedef LabelSelection = ({String ownerId, String id});

/// Reads only already loaded, authorized projections. No I/O per keystroke.
List<LabelProjection> visibleLabels(
  NoteDto note,
  Iterable<LocalLabelState> catalog, {
  required String actor,
  required bool readable,
}) {
  if (!readable || !note.contentAvailable) return const [];
  if (note.ownerId == actor) {
    return [
      for (final row in catalog)
        if (row.ownerId == actor &&
            !row.isDeleted &&
            note.labelIds.contains(row.id))
          LabelProjection(id: row.id, name: row.name),
    ];
  }
  return note.labelProjections
      .where((p) => note.labelIds.contains(p.id))
      .toList();
}

List<NoteDto> queryNotes(
  Iterable<NoteDto> notes, {
  String keyword = '',
  Set<LabelSelection> selected = const {},
  required bool Function(NoteDto) readable,
  required List<LabelProjection> Function(NoteDto) labelsFor,
}) {
  final query = keyword.trim().toLowerCase();
  return notes.where((note) {
    if (!readable(note)) return query.isEmpty && selected.isEmpty;
    if (query.isNotEmpty &&
        !note.title.toLowerCase().contains(query) &&
        !NoteBody.plainText(note.content).toLowerCase().contains(query)) {
      return false;
    }
    final available = labelsFor(note)
        .map((p) => (ownerId: note.ownerId, id: p.id))
        .toSet();
    return selected.every(available.contains);
  }).toList();
}
