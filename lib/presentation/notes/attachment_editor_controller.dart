import 'package:flutter/material.dart';

typedef AttachmentInlineBlockBuilder = Widget Function(
  BuildContext context,
  String blockId,
  String? attachmentId,
);

typedef AttachmentInlinePicker = Future<void> Function(
  BuildContext context,
  String blockId,
);

typedef AttachmentLegacyPanelBuilder = Widget Function(BuildContext context);

/// Bridges document file blocks to the one mounted attachment panel.
///
/// The panel remains the sole owner of attachment services, transfer state,
/// preview bytes, and access checks. This controller only exposes its inline
/// widgets and picker entry point to the rich editor.
final class AttachmentEditorController extends ChangeNotifier {
  AttachmentEditorController({this.readReferencedIds});

  Object? _owner;
  AttachmentInlineBlockBuilder? _buildBlock;
  AttachmentLegacyPanelBuilder? _buildLegacy;
  AttachmentInlinePicker? _openPicker;
  List<String> Function()? _readAttachmentIds;
  final List<String> Function()? readReferencedIds;
  final Map<String, BuildContext> _blockContexts = {};
  bool _refreshScheduled = false;
  bool _disposed = false;

  /// Associated and locally pending IDs known by the mounted attachment panel.
  /// The editor uses this list while migrating legacy attachments into blocks.
  List<String> get attachmentIds =>
      List.unmodifiable(_readAttachmentIds?.call() ?? const <String>[]);

  /// IDs currently stored in rich document file blocks.
  List<String> get referencedAttachmentIds =>
      List.unmodifiable(readReferencedIds?.call() ?? const <String>[]);

  void bind({
    required Object owner,
    required AttachmentInlineBlockBuilder buildBlock,
    required AttachmentLegacyPanelBuilder buildLegacy,
    required AttachmentInlinePicker openPicker,
    required List<String> Function() readAttachmentIds,
  }) {
    _owner = owner;
    _buildBlock = buildBlock;
    _buildLegacy = buildLegacy;
    _openPicker = openPicker;
    _readAttachmentIds = readAttachmentIds;
    _scheduleRefresh();
  }

  void unbind(Object owner) {
    if (!identical(_owner, owner)) return;
    _owner = null;
    _buildBlock = null;
    _buildLegacy = null;
    _openPicker = null;
    _readAttachmentIds = null;
    _blockContexts.clear();
    _scheduleRefresh();
  }

  Widget buildBlock(
    BuildContext context,
    String blockId,
    String? attachmentId,
  ) => _AttachmentInlineAnchor(
    controller: this,
    blockId: blockId,
    builder: (anchorContext) =>
        _buildBlock?.call(anchorContext, blockId, attachmentId) ??
        const SizedBox.shrink(),
  );

  /// Builds the single legacy attachment panel when the document is not using
  /// inline File blocks. The mounted panel remains the service/state owner.
  Widget buildLegacy(BuildContext context) =>
      _buildLegacy?.call(context) ?? const SizedBox.shrink();

  Future<void> openPicker(String blockId) async {
    final context = _blockContexts[blockId];
    final picker = _openPicker;
    if (context == null || !context.mounted || picker == null) return;
    await picker(context, blockId);
  }

  void refresh() {
    if (_owner != null) _scheduleRefresh();
  }

  void _scheduleRefresh() {
    if (_disposed || _refreshScheduled) return;
    _refreshScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshScheduled = false;
      if (!_disposed && hasListeners) notifyListeners();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void dispose() {
    _disposed = true;
    _owner = null;
    _buildBlock = null;
    _buildLegacy = null;
    _openPicker = null;
    _readAttachmentIds = null;
    _blockContexts.clear();
    super.dispose();
  }

  void _register(String blockId, BuildContext context) {
    _blockContexts[blockId] = context;
  }

  void _unregister(String blockId, BuildContext context) {
    if (identical(_blockContexts[blockId], context)) {
      _blockContexts.remove(blockId);
    }
  }
}

final class _AttachmentInlineAnchor extends StatefulWidget {
  const _AttachmentInlineAnchor({
    required this.controller,
    required this.blockId,
    required this.builder,
  });

  final AttachmentEditorController controller;
  final String blockId;
  final WidgetBuilder builder;

  @override
  State<_AttachmentInlineAnchor> createState() =>
      _AttachmentInlineAnchorState();
}

final class _AttachmentInlineAnchorState
    extends State<_AttachmentInlineAnchor> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    widget.controller._register(widget.blockId, context);
  }

  @override
  void didUpdateWidget(covariant _AttachmentInlineAnchor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller ||
        oldWidget.blockId != widget.blockId) {
      oldWidget.controller._unregister(oldWidget.blockId, context);
      widget.controller._register(widget.blockId, context);
    }
  }

  @override
  void dispose() {
    widget.controller._unregister(widget.blockId, context);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    widget.controller._register(widget.blockId, context);
    return widget.builder(context);
  }
}
