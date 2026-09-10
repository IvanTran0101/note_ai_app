import '../../application/notes/note_application.dart';

/// Why a Note Detail route returned to its caller.
enum NoteDetailExitReason { saved, deleted, discarded, cancelled }

/// Small Presentation result used to decide whether a parent projection must
/// refresh after a Note Detail route closes.
final class NoteDetailRouteResult {
  const NoteDetailRouteResult({required this.reason, this.note})
    : assert(
        reason == NoteDetailExitReason.saved || note == null,
        'Only a saved result may carry a note payload.',
      );

  final NoteDetailExitReason reason;
  final NoteDto? note;

  bool get shouldRefresh =>
      reason == NoteDetailExitReason.saved ||
      reason == NoteDetailExitReason.deleted;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is NoteDetailRouteResult &&
            other.reason == reason &&
            other.note == note;
  }

  @override
  int get hashCode => Object.hash(reason, note);

  @override
  String toString() =>
      'NoteDetailRouteResult(reason: ${reason.name}, note: ${note?.id})';
}
