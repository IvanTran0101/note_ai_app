part of 'rich_note_editor.dart';

extension _RichNoteBlockChrome on _RichNoteEditorState {
  Future<void> _openAfterBlock(engine.Node node) async {
    final adapter = widget.adapter;
    if (!adapter.editable ||
        adapter.composing ||
        node.path.isEmpty ||
        BasicBlockCommands(adapter).inCell(node) ||
        !identical(adapter.editor.document.nodeAtPath(node.path), node)) {
      return;
    }
    // The gutter button can be used while another block owns the caret (or
    // when there is no active caret). Anchor the transaction to the clicked
    // block so the blank paragraph is always inserted in the expected place.
    adapter.editor.selection = engine.Selection.collapsed(
      engine.Position(path: node.path, offset: 0),
    );
    final snapshot = adapter.capture(range: false);
    if (snapshot == null || !adapter.accepts(snapshot)) return;

    slash.close();
    final path = [...node.path];
    path[path.length - 1]++;
    final transaction = adapter.editor.transaction;
    transaction.insertNode(path, engine.paragraphNode());
    transaction.afterSelection = engine.Selection.collapsed(
      engine.Position(path: path, offset: 0),
    );
    if (await adapter.apply(transaction, snapshot) && mounted) {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || !adapter.editable) return;
      final rects = adapter.editor.selectionRects();
      final box = adapter.editor.getNodeAtPath(path)?.renderBox;
      if (rects.isNotEmpty) {
        _blockFilterAnchor = Rect.fromLTWH(
          rects.last.left,
          rects.last.top,
          box?.size.width ?? 720,
          math.max(27, rects.last.height),
        );
      }
      _lastInputFocus = null;
      slash.openTouch();
    }
  }

  Widget _header() => EditorHeaderBoundary(
    adapter: widget.adapter,
    child: Column(
      children: [
        ValueListenableBuilder<Widget>(
          valueListenable: header,
          builder: (_, value, _) => value,
        ),
      ],
    ),
  );

  Widget _controls({VoidCallback? onBlocks}) => ListenableBuilder(
    listenable: widget.adapter,
    builder: (_, _) => widget.adapter.editable
        ? EditorControls(
            adapter: widget.adapter,
            slash: slash,
            onBlocks: onBlocks,
            blocksOpen: onBlocks != null,
          )
        : const SizedBox.shrink(),
  );

  Widget _nativeControls(BuildContext context) => EditorHeaderBoundary(
    adapter: widget.adapter,
    interceptSelection: false,
    child: NativeEditorRail(
      key: const ValueKey('document-controls-rail'),
      adapter: widget.adapter,
      focusNode: widget.focusNode,
      controls: _controls(),
    ),
  );
  Widget _footer(ColorScheme colors) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ValueListenableBuilder<Widget>(
        valueListenable: footer,
        builder: (_, value, _) =>
            EditorHeaderBoundary(adapter: widget.adapter, child: value),
      ),
      ListenableBuilder(
        listenable: widget.adapter,
        builder: (context, _) => widget.adapter.error == null
            ? const SizedBox(height: 120)
            : Semantics(
                liveRegion: true,
                child: Text(
                  widget.adapter.error!,
                  style: TextStyle(color: colors.error),
                ),
              ),
      ),
    ],
  );
}
