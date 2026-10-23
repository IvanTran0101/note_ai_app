import 'dart:async';

import 'package:appflowy_editor/appflowy_editor.dart' as engine;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../domain/notes/note_document.dart';
import 'editor_identity_normalizer.dart';
import 'rich_document_codec.dart';

part 'rich_editor_composition.dart';
part 'rich_editor_files.dart';

/// Owns transient editing state only. Immutable business snapshots are passed
/// to the existing Application controller; this class has no persistence port.
final class RichEditorAdapter extends ChangeNotifier {
  RichEditorAdapter({
    required NoteDocument? document,
    required String legacyText,
    required this.canEdit,
    this.canRead = _readableByDefault,
    required this.isLive,
    required this.accessGeneration,
    required this.onChanged,
    this.readLegacyAttachmentIds,
    this.onFileInserted,
  }) : _source = document {
    engine.AppFlowyLogConfiguration()
      ..level = engine.AppFlowyEditorLogLevel.off
      ..handler = null;
    editor = engine.EditorState(
      document: document == null
          ? RichDocumentCodec.legacy(legacyText)
          : RichDocumentCodec.encode(document),
    );
    _guardSubscription = editor.transactionStream.listen((event) {
      if (event.$1 == engine.TransactionTime.before &&
          (!isLive() || !canEdit() || _menuOwnsInput.value)) {
        // Text edits are composed lazily by Transaction.operations. Disable
        // that deferred composition before clearing, or it recreates the edit.
        event.$2.markNeedsComposing = false;
        event.$2.operations = [];
        event.$2.afterSelection = event.$2.beforeSelection;
      }
    });
    _normalizer = EditorIdentityNormalizer(editor, onRejected: _reject);
    _initial = _current = RichDocumentCodec.decode(editor.document);
    _composition = _RichEditorComposition(_notify);
    _subscription = editor.transactionStream.listen((event) {
      if (event.$1 == engine.TransactionTime.after) _changed();
    });
    editor.selectionNotifier.addListener(_notify);
  }
  final bool Function() canEdit, canRead, isLive;
  final int Function() accessGeneration;
  final VoidCallback onChanged;
  final List<String> Function()? readLegacyAttachmentIds;
  final ValueChanged<String>? onFileInserted;
  List<String> get legacyAttachmentIds =>
      List<String>.unmodifiable(readLegacyAttachmentIds?.call() ?? const []);
  late final engine.EditorState editor;
  late final EditorIdentityNormalizer _normalizer;
  late final _RichEditorComposition _composition;
  late final StreamSubscription<engine.EditorTransactionValue> _subscription,
      _guardSubscription;
  engine.AppFlowyKeyboardService? _keyboard;
  late NoteDocument _initial, _current;
  NoteDocument? _source;
  bool _disposed = false;
  final ValueNotifier<bool> active = ValueNotifier(true);

  /// The + palette owns its temporary query input until it closes.
  final ValueNotifier<bool> _menuOwnsInput = ValueNotifier(false);
  ValueListenable<bool> get menuOwnsInput => _menuOwnsInput;
  void setMenuInput(bool value) {
    if (!_disposed) _menuOwnsInput.value = value;
  }

  int revision = 0;
  String? error;
  final Map<String, bool> expandedToggles = {};

  /// Legacy content is not inflated by opening, selection, layout or no-op undo.
  NoteDocument? get document =>
      _source == null && _current == _initial ? null : _current;
  NoteDocument get visibleDocument => _current;
  String get plainText => _current.plainText;
  bool get composing => _composition.composing;
  bool get editable => !_disposed && isLive() && canEdit();

  String newIdentity() => _normalizer.allocateIdentity();

  void bindKeyboard() {
    if (_disposed) return;
    final next = editor.service.keyboardService;
    if (identical(next, _keyboard)) return;
    _keyboard?.unregisterInterceptor(_composition);
    _keyboard = next;
    next?.registerInterceptor(_composition);
  }

  void refreshAccess() {
    if (_disposed) return;
    editor.editable = editable;
    if (!editable) _composition.clear();
    _notify();
  }

  void acceptSavedDocument(NoteDocument? document) {
    _source = document;
    if (document != null) _initial = document;
  }

  void _changed() {
    if (_disposed || !isLive()) return;
    final next = RichDocumentCodec.decode(editor.document);
    if (next == _current) return;
    _current = next;
    revision++;
    error = null;
    _notify();
    onChanged();
  }

  void _reject() {
    error =
        'This change exceeds the document limits or uses an unsupported block.';
    _notify();
  }

  void reportInputLimit() {
    error =
        'Paste exceeds the document limits. The existing draft is unchanged.';
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  RichSelectionSnapshot? capture({bool range = true}) {
    final selection = editor.selection;
    if (!editable ||
        composing ||
        selection == null ||
        range && selection.isCollapsed) {
      return null;
    }
    return RichSelectionSnapshot(
      _copySelection(selection),
      revision,
      accessGeneration(),
    );
  }

  RichSelectionSnapshot? captureForCopy() {
    final selection = editor.selection;
    if (_disposed ||
        !isLive() ||
        !canRead() ||
        selection == null ||
        selection.isCollapsed) {
      return null;
    }
    return RichSelectionSnapshot(
      _copySelection(selection),
      revision,
      accessGeneration(),
    );
  }

  bool acceptsForCopy(RichSelectionSnapshot snapshot) =>
      !_disposed &&
      isLive() &&
      canRead() &&
      revision == snapshot.revision &&
      accessGeneration() == snapshot.accessGeneration &&
      _sameSelection(editor.selection, snapshot.selection);

  bool accepts(RichSelectionSnapshot snapshot, {bool popupOwnsFocus = false}) =>
      editable &&
      !composing &&
      revision == snapshot.revision &&
      accessGeneration() == snapshot.accessGeneration &&
      (_sameSelection(editor.selection, snapshot.selection) ||
          popupOwnsFocus && editor.selection == null);

  /// One upstream transaction and one undo unit; callers capture before a popup.
  Future<bool> apply(
    engine.Transaction transaction,
    RichSelectionSnapshot snapshot, {
    bool popupOwnsFocus = false,
  }) async {
    if (_menuOwnsInput.value ||
        !accepts(snapshot, popupOwnsFocus: popupOwnsFocus)) {
      return false;
    }
    if (editor.undoManager.undoStack.isNonEmpty) {
      editor.undoManager.undoStack.last.seal();
    }
    transaction.beforeSelection = snapshot.selection;
    await editor.apply(transaction, skipHistoryDebounce: true);
    return error == null && isLive() && canEdit();
  }

  void expand(String id) {
    if (_disposed || !isLive()) return;
    expandedToggles[id] = !(expandedToggles[id] ?? true);
    // Viewing expansion is ephemeral and does not emit a document/save event.
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    active.value = false;
    _keyboard?.unregisterInterceptor(_composition);
    editor.selectionNotifier.removeListener(_notify);
    _subscription.cancel();
    _guardSubscription.cancel();
    _normalizer.dispose();
    editor.dispose();
    active.dispose();
    _menuOwnsInput.dispose();
    super.dispose();
  }
}

final class RichSelectionSnapshot {
  const RichSelectionSnapshot(
    this.selection,
    this.revision,
    this.accessGeneration,
  );
  final engine.Selection selection;
  final int revision, accessGeneration;
}

engine.Selection _copySelection(engine.Selection value) => engine.Selection(
  start: value.start.copyWith(path: List<int>.of(value.start.path)),
  end: value.end.copyWith(path: List<int>.of(value.end.path)),
);
bool _readableByDefault() => true;
bool _sameSelection(engine.Selection? a, engine.Selection b) =>
    a != null &&
    listEquals(a.start.path, b.start.path) &&
    a.start.offset == b.start.offset &&
    listEquals(a.end.path, b.end.path) &&
    a.end.offset == b.end.offset;
