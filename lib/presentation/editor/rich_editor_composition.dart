part of 'rich_editor_adapter.dart';

/// Observe public IME deltas without replacing their upstream processing.
final class _RichEditorComposition
    extends engine.AppFlowyKeyboardServiceInterceptor {
  _RichEditorComposition(this.onChanged);
  final VoidCallback onChanged;
  bool composing = false;
  bool _observe(TextEditingDelta value) {
    final next = value.composing.isValid && !value.composing.isCollapsed;
    if (composing != next) {
      composing = next;
      onChanged();
    }
    return false;
  }

  void clear() {
    if (composing) {
      composing = false;
      onChanged();
    }
  }

  @override
  Future<bool> interceptInsert(
    TextEditingDeltaInsertion value,
    engine.EditorState state,
    List<engine.CharacterShortcutEvent> shortcuts,
  ) async => _observe(value);
  @override
  Future<bool> interceptDelete(
    TextEditingDeltaDeletion value,
    engine.EditorState state,
  ) async => _observe(value);
  @override
  Future<bool> interceptReplace(
    TextEditingDeltaReplacement value,
    engine.EditorState state,
    List<engine.CharacterShortcutEvent> shortcuts,
  ) async => _observe(value);
  @override
  Future<bool> interceptNonTextUpdate(
    TextEditingDeltaNonTextUpdate value,
    engine.EditorState state,
    List<engine.CharacterShortcutEvent> shortcuts,
  ) async => _observe(value);
}
