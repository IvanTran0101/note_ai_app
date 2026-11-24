import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// The editor owns block selection/history; the attachment panel supplies only
/// the guarded file presentation and transfer actions.
final class FileBlockBuilder extends BlockComponentBuilder {
  FileBlockBuilder({required this.fileBuilder});
  final Widget Function(String blockId, String? attachmentId)? fileBuilder;
  @override
  BlockComponentValidate get validate =>
      (node) => node.children.isEmpty;
  @override
  Position end(Node node) => Position(path: node.path, offset: 1);
  @override
  BlockComponentWidget build(BlockComponentContext context) => _FileBlock(
    key: context.node.key,
    node: context.node,
    configuration: configuration,
    fileBuilder: fileBuilder,
  );
}

final class _FileBlock extends BlockComponentStatefulWidget {
  const _FileBlock({
    super.key,
    required super.node,
    required super.configuration,
    required this.fileBuilder,
  });
  final Widget Function(String, String?)? fileBuilder;
  @override
  State<_FileBlock> createState() => _FileBlockState();
}

final class _FileBlockState extends State<_FileBlock>
    with SelectableMixin, BlockComponentConfigurable {
  @override
  Node get node => widget.node;
  @override
  BlockComponentConfiguration get configuration => widget.configuration;
  RenderBox? get _box => context.findRenderObject() as RenderBox?;

  @override
  Widget build(BuildContext context) {
    final editor = context.read<EditorState>();
    final id = node.attributes['m09_id'] as String;
    final attachment = node.attributes['m09_attachment_id'] as String?;
    return BlockSelectionContainer(
      node: node,
      delegate: this,
      listenable: editor.selectionNotifier,
      remoteSelection: editor.remoteSelections,
      blockColor: editor.editorStyle.selectionColor,
      cursorColor: editor.editorStyle.cursorColor,
      selectionColor: editor.editorStyle.selectionColor,
      supportTypes: const [
        BlockSelectionType.block,
        BlockSelectionType.cursor,
        BlockSelectionType.selection,
      ],
      child: Padding(
        padding: padding,
        child:
            widget.fileBuilder?.call(id, attachment) ??
            const SizedBox(height: 48),
      ),
    );
  }

  @override
  Position start() => Position(path: node.path, offset: 0);
  @override
  Position end() => Position(path: node.path, offset: 1);
  @override
  Position getPositionInOffset(Offset start) => end();
  @override
  bool get shouldCursorBlink => false;
  @override
  CursorStyle get cursorStyle => CursorStyle.cover;
  @override
  Rect getBlockRect({bool shiftWithBaseOffset = false}) =>
      Offset.zero & (_box?.size ?? Size.zero);
  @override
  Rect? getCursorRectInPosition(
    Position position, {
    bool shiftWithBaseOffset = false,
  }) => _box == null ? null : getBlockRect();
  @override
  List<Rect> getRectsInSelection(
    Selection selection, {
    bool shiftWithBaseOffset = false,
  }) => _box == null ? [] : [getBlockRect()];
  @override
  Selection getSelectionInRange(Offset start, Offset end) =>
      Selection.single(path: node.path, startOffset: 0, endOffset: 1);
  @override
  Offset localToGlobal(Offset offset, {bool shiftWithBaseOffset = false}) =>
      _box?.localToGlobal(offset) ?? offset;
  @override
  TextDirection textDirection() => TextDirection.ltr;
}
