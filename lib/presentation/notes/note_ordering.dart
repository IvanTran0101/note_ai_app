import '../../application/notes/note_application.dart';

/// Applies the pin-first ordering used by note-list presentation surfaces.
List<NoteDto> sortNotes(Iterable<NoteDto> notes, {bool byCreatedAt = false}) {
  final List<NoteDto> sorted = List<NoteDto>.of(notes);
  sorted.sort((NoteDto a, NoteDto b) {
    final DateTime? aPinnedAt = a.pinnedAt;
    final DateTime? bPinnedAt = b.pinnedAt;
    if (aPinnedAt == null && bPinnedAt != null) return 1;
    if (aPinnedAt != null && bPinnedAt == null) return -1;

    if (aPinnedAt != null && bPinnedAt != null) {
      final int byPinTime = bPinnedAt.compareTo(aPinnedAt);
      if (byPinTime != 0) return byPinTime;
    } else {
      final DateTime aDate = byCreatedAt ? a.createdAt : a.updatedAt;
      final DateTime bDate = byCreatedAt ? b.createdAt : b.updatedAt;
      final int byDate = bDate.compareTo(aDate);
      if (byDate != 0) return byDate;
    }

    final int byOwner = a.ownerId.compareTo(b.ownerId);
    return byOwner != 0 ? byOwner : a.id.compareTo(b.id);
  });
  return sorted;
}
