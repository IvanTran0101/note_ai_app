import '../labels/local_label_state.dart';
import 'local_note_state.dart';

/// A consistent local read generation. Headers contain no bodies/documents.
abstract interface class LocalNotePageView {
  String get accountId;
  List<LocalNoteState> get headers;
  List<LocalLabelState> get labels;
  Future<LocalNoteState> readNote(LocalNoteState header);
  Future<void> requireCurrent();
}

abstract interface class ILocalNotePageStore {
  Future<T> withNotePageView<T>(
    Future<T> Function(LocalNotePageView view) query,
  );
}
