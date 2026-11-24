import 'local_note_state.dart';
import 'sync_snapshot.dart';

/// Read-only scoped refresh during sync; never a second cursor or writer.
abstract interface class ISharedLabelProjectionSource {
  Future<List<SyncNoteSnapshot>> refreshLabels(Iterable<LocalNoteState> notes);
}
