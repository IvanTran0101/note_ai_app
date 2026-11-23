import 'dart:async';
import 'dart:convert';

import 'package:appflowy_editor/appflowy_editor.dart' as engine;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/notes/note_document.dart';
import 'rich_editor_adapter.dart';
import 'editor_projection_map.dart';

/// External clipboard imports plaintext only, through public upstream paste.
/// Clipboard latency is fenced before touching the selection or history.
final class EditorClipboard {
  const EditorClipboard(this.adapter);
  final RichEditorAdapter adapter;
  Future<bool> copy({bool cut = false}) async {
    final snapshot = cut ? adapter.capture() : adapter.captureForCopy();
    if (snapshot == null) return false;
    final text = EditorProjectionMap(adapter.editor.document)
        .selectedText(snapshot.selection);
    if (text == null) return false;
    if (!adapter.acceptsForCopy(snapshot)) return false;
    await Clipboard.setData(ClipboardData(text: text));
    if (cut && adapter.accepts(snapshot)) {
      await adapter.editor.deleteSelection(snapshot.selection);
    }
    return true;
  }

  Future<void> read() async {
    final snapshot = adapter.capture(range: false);
    if (snapshot == null) return;
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    if (text != null) await paste(snapshot, text);
  }

  Future<bool> paste(RichSelectionSnapshot snapshot, String text) async {
    if (text.isEmpty || !adapter.accepts(snapshot)) return false;
    final parts = text
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n');
    // Reserve the full imported structure before the engine deletes selection.
    // This bound is deliberately conservative when replacing a large selection.
    try {
      NoteDocument([
        ...adapter.visibleDocument.blocks,
        for (final part in parts)
          DocumentBlock(
            id: adapter.newIdentity(),
            kind: DocumentBlockKind.paragraph,
            runs: [DocumentText(part)],
          ),
      ]);
      if (utf8.encode(adapter.plainText).length + utf8.encode(text).length >
          100000) {
        adapter.reportInputLimit();
        return false;
      }
    } on ArgumentError {
      adapter.reportInputLimit();
      return false;
    }
    final nodes = parts
        .map((text) => engine.paragraphNode(text: text))
        .toList();
    if (nodes.length == 1) {
      await adapter.editor.pasteSingleLineNode(nodes.single);
    } else {
      await adapter.editor.pasteMultiLineNodes(nodes);
    }
    return adapter.error == null && adapter.editable;
  }

  List<engine.CommandShortcutEvent> get shortcuts => [
    for (final binding in ['ctrl+c', 'ctrl+x'])
      engine.CommandShortcutEvent(
        key: 'm09 $binding',
        command: binding,
        macOSCommand: binding.replaceFirst('ctrl', 'cmd'),
        getDescription: () => binding == 'ctrl+x' ? 'Cut' : 'Copy',
        handler: (_) {
          unawaited(copy(cut: binding == 'ctrl+x'));
          return KeyEventResult.handled;
        },
      ),
    for (final binding in ['ctrl+v', 'ctrl+shift+v'])
      engine.CommandShortcutEvent(
        key: 'm09 $binding',
        command: binding,
        macOSCommand: binding.replaceFirst('ctrl', 'cmd'),
        getDescription: () => 'Paste plain text',
        handler: (_) {
          unawaited(read());
          return KeyEventResult.handled;
        },
      ),
  ];
  Widget contextMenu(
    BuildContext context,
    Offset position,
    engine.EditorState editor,
    VoidCallback close,
  ) => engine.ContextMenu(
    position: position,
    editorState: editor,
    onPressed: close,
    items: [
      [
        engine.ContextMenuItem(
          getName: () => 'Copy',
          isApplicable: (_) => adapter.captureForCopy() != null,
          onPressed: (_) => unawaited(copy()),
        ),
        engine.ContextMenuItem(
          getName: () => 'Cut',
          isApplicable: (_) => adapter.capture() != null,
          onPressed: (_) => unawaited(copy(cut: true)),
        ),
        engine.ContextMenuItem(
          getName: () => 'Paste',
          isApplicable: (_) => adapter.editable,
          onPressed: (_) => unawaited(read()),
        ),
      ],
    ],
  );
}
