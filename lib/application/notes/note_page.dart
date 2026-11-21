import '../labels/note_query.dart';
import 'note_dto.dart';

/// Query pagination, independent from cloud sync cursors and storage SDKs.
enum NotePageScope { owned, shared }

final class NotePageQuery {
  NotePageQuery({
    this.page = 0,
    this.size = 50,
    this.scope = NotePageScope.owned,
    this.keyword = '',
    this.byCreatedAt = false,
    this.pinFirst = true,
    Set<LabelSelection> labels = const {},
  }) : labels = Set.unmodifiable(labels) {
    if (page < 0 || size < 1 || size > 100) {
      throw ArgumentError('Page must be nonnegative; size must be 1–100.');
    }
  }
  final int page, size;
  final NotePageScope scope;
  final String keyword;
  final bool byCreatedAt;
  final bool pinFirst;
  final Set<LabelSelection> labels;
}

final class NotePage {
  NotePage({
    required Iterable<NoteDto> notes,
    required this.total,
    required this.page,
    required this.size,
    Map<LabelSelection, String> labelChoices = const {},
  }) : notes = List.unmodifiable(notes),
       labelChoices = Map.unmodifiable(labelChoices);
  final List<NoteDto> notes;
  final int total, page, size;
  final Map<LabelSelection, String> labelChoices;
  bool get hasPrevious => page > 0;
  bool get hasNext => (page + 1) * size < total;
  int get start => total == 0 ? 0 : page * size + 1;
  int get end => page * size + notes.length;
}

abstract interface class INotePageReader {
  Future<NotePage> queryNotePage(String actorId, NotePageQuery query);
}

/// Shared ordering: pin first, date descending, canonical identity tie-breaker.
int compareNotePageKeys(
  ({DateTime? pin, DateTime date, String owner, String id}) a,
  ({DateTime? pin, DateTime date, String owner, String id}) b,
) {
  if (a.pin == null && b.pin != null) return 1;
  if (a.pin != null && b.pin == null) return -1;
  final byDate = a.pin != null && b.pin != null
      ? b.pin!.compareTo(a.pin!)
      : b.date.compareTo(a.date);
  if (byDate != 0) return byDate;
  final owner = a.owner.compareTo(b.owner);
  return owner != 0 ? owner : a.id.compareTo(b.id);
}
