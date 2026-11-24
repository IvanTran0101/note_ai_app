part of 'selection_toolbar.dart';

extension _SelectionToolbarDialogs on SelectionToolbar {
  Future<void> _style(
    BuildContext context,
    RichSelectionSnapshot snapshot,
  ) async {
    onPopupOpen();
    final choice = await guardedEditorDialog<BasicBlockChoice>(
      context,
      adapter,
      snapshot,
      (context) => SimpleDialog(
        title: Text(editorText(context, 'Text style')),
        children: [
          for (final choice in basicBlockChoices.take(5))
            _selectionDialogOption(
              onPressed: () => Navigator.pop(context, choice),
              child: Text(editorText(context, choice.label)),
            ),
        ],
      ),
    );
    if (choice != null) {
      await BasicBlockCommands(adapter)
          .choose(choice, snapshot, popupOwnsFocus: true);
    }
  }

  Future<void> _size(
    BuildContext context,
    RichSelectionSnapshot snapshot,
  ) async {
    onPopupOpen();
    final formatter = SelectionFormattingController(adapter);
    final chosen = await guardedEditorDialog<String>(
      context,
      adapter,
      snapshot,
      (context) => SimpleDialog(
        title: Text(editorText(context, 'Font size')),
        children: [
          for (final size in [12, 14, 16, 18, 24, 32])
            _selectionDialogOption(
              onPressed: () => Navigator.pop(context, '$size'),
              child: Text('$size pt'),
            ),
          _selectionDialogOption(
            onPressed: () => Navigator.pop(context, 'custom'),
            child: Text(editorText(context, 'Custom size (12–48)')),
          ),
          _selectionDialogOption(
            onPressed: () => Navigator.pop(context, 'reset'),
            child: Text(editorText(context, 'Reset size')),
          ),
        ],
      ),
    );
    if (chosen == null || !context.mounted) return;
    if (chosen == 'custom') {
      final value = await editorValueDialog(
        context,
        title: 'Font size',
        label: 'Size (12–48)',
        initial: '${formatter.state(snapshot, 'font_size').value ?? 16}',
        validate: validateEditorSize,
        adapter: adapter,
        snapshot: snapshot,
      );
      if (value != null) {
        await formatter.size(
          snapshot,
          double.parse(value),
          popupOwnsFocus: true,
        );
      }
    } else {
      await formatter.size(
        snapshot,
        chosen == 'reset' ? null : double.parse(chosen),
        popupOwnsFocus: true,
      );
    }
  }

  Future<void> _link(
    BuildContext context,
    RichSelectionSnapshot snapshot,
  ) async {
    onPopupOpen();
    final formatter = SelectionFormattingController(adapter);
    final value = await editorValueDialog(
      context,
      title: 'Link',
      label: 'https://… (empty to remove)',
      initial: formatter.state(snapshot, 'href').value as String? ?? '',
      validate: validateEditorLink,
      adapter: adapter,
      snapshot: snapshot,
    );
    if (value != null) {
      await formatter.link(
        snapshot,
        value.isEmpty ? null : value,
        popupOwnsFocus: true,
      );
    }
  }

  Future<void> _color(
    BuildContext context,
    RichSelectionSnapshot snapshot,
    bool highlight,
  ) async {
    onPopupOpen();
    final selected = await guardedEditorDialog<String>(
      context,
      adapter,
      snapshot,
      (context) => SimpleDialog(
        title: Text(
          editorText(context, highlight ? 'Highlight' : 'Text color'),
        ),
        children: [
          _selectionDialogOption(
            onPressed: () => Navigator.pop(context, 'reset'),
            child: Text(editorText(context, 'Default')),
          ),
          for (final color in DocumentColor.values)
            _selectionDialogOption(
              onPressed: () => Navigator.pop(context, color.name),
              child: Row(
                children: [
                  Icon(
                    Icons.circle,
                    color: DocumentPalette.text(
                      color,
                      Theme.of(context).brightness,
                    ),
                    size: 16,
                  ),
                  const SizedBox(width: 12),
                  Flexible(child: Text(editorText(context, color.name))),
                ],
              ),
            ),
        ],
      ),
    );
    if (selected != null) {
      await SelectionFormattingController(adapter).color(
        snapshot,
        selected == 'reset' ? null : DocumentColor.values.byName(selected),
        highlight: highlight,
        popupOwnsFocus: true,
      );
    }
  }
}

Widget _selectionDialogOption({
  required VoidCallback onPressed,
  required Widget child,
}) => SimpleDialogOption(
  onPressed: onPressed,
  child: ConstrainedBox(
    // SimpleDialogOption contributes another 16px of vertical padding. Keep
    // native touch targets at least 48px while allowing large text to grow.
    constraints: BoxConstraints(minHeight: kIsWeb ? 0 : 32),
    child: Align(
      alignment: AlignmentDirectional.centerStart,
      heightFactor: 1,
      child: child,
    ),
  ),
);
