part of 'attachment_editor_panel.dart';

extension _AttachmentEditorRows on _AttachmentEditorPanelState {
  Widget _buildPanel(BuildContext context) {
    final items = <_AttachmentItem>[
      for (final draft in _pending.where(
        (draft) => !widget.note.attachments.any(
          (attachment) => attachment.id == draft.cacheId,
        ),
      ))
        _AttachmentItem.local(draft),
      for (final attachment in widget.note.attachments)
        _AttachmentItem.associated(attachment),
    ];
    final colors = Theme.of(context).colorScheme;

    if (items.isEmpty && _previewItem == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_busy) const LinearProgressIndicator(minHeight: 2),
          if (_pending.isNotEmpty && widget.note.contentRevision == 0)
            _localFirstHint(context),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 4),
              child: Text(_error!, style: TextStyle(color: colors.error)),
            ),
          for (final item in items) _row(item),
          if (_previewItem != null) ...[
            const SizedBox(height: 4),
            const Divider(height: 1),
            _previewWidget(),
          ],
        ],
      ),
    );
  }

  Widget _localFirstHint(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: Text(
          'Saved on this device. Attachments will upload after this note syncs.',
          style: TextStyle(fontSize: 12, height: 1.35),
        ),
      ),
    ),
  );

  Widget _row(_AttachmentItem item) {
    final progress = _progress[item.id], ready = _ready.contains(item.id);
    final uploading = _working.contains('upload/${item.id}');
    final status =
        (uploading || _working.contains('open/${item.id}')) && progress != null
        ? '${progress.phase} · ${progress.completedBytes}/${progress.totalBytes} B'
        : item.draft != null
        ? 'Pending on this device'
        : ready
        ? 'Ready'
        : 'Waiting for sync confirmation';
    final canRetry = _canWrite && !ready;
    final removeTooltip = item.draft != null
        ? 'Remove local attachment'
        : 'Remove attachment';

    return AttachmentFileRow(
      name: item.name,
      mimeType: item.mime,
      sizeLabel: _formatAttachmentSize(item.size),
      statusLabel: status,
      onOpen: () => unawaited(_open(item)),
      onRetry: canRetry ? () => unawaited(_retry(item.id)) : null,
      retryEnabled: !uploading,
      onDownload: _canWrite && ready && _capabilities.canExport
          ? () => unawaited(_open(item, exportFile: true))
          : null,
      onRemove: _canWrite ? () => unawaited(_remove(item)) : null,
      removeEnabled: !_working.contains('remove/${item.id}'),
      removeLabel: removeTooltip,
    );
  }

  String _formatAttachmentSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KiB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MiB';
  }
}
