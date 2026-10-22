part of 'attachment_editor_panel.dart';

extension _AttachmentEditorRows on _AttachmentEditorPanelState {
  static const _attachmentLimits =
      'Images 10 MiB · MP4 50 MiB · PDF/TXT/CSV 20 MiB. '
      'Up to 10 files / 100 MiB per note.';

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

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
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
          if (items.isEmpty) _emptyAttachmentPrompt(context),
          for (final item in items) _row(item),
          if (items.isNotEmpty && _canWrite)
            _emptyAttachmentPrompt(context, subdued: true),
          if (_previewItem != null) ...[
            const SizedBox(height: 4),
            const Divider(height: 1),
            _previewWidget(),
          ],
        ],
      ),
    );
  }

  PopupMenuButton<AttachmentSource> _addAttachmentMenu({
    Widget? child,
  }) => PopupMenuButton<AttachmentSource>(
    enabled: !_busy,
    tooltip: 'Add attachment',
    icon: child == null ? const Icon(Icons.add) : null,
    padding: EdgeInsets.zero,
    child: child,
    onSelected: (source) => unawaited(_pick(source)),
    itemBuilder: (_) => const [
      PopupMenuItem(value: AttachmentSource.files, child: Text('Choose files')),
      PopupMenuItem(value: AttachmentSource.gallery, child: Text('Gallery')),
      PopupMenuItem(
        value: AttachmentSource.cameraPhoto,
        child: Text('Take photo'),
      ),
      PopupMenuItem(
        value: AttachmentSource.cameraVideo,
        child: Text('Record video'),
      ),
    ],
  );

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

  Widget _emptyAttachmentPrompt(BuildContext context, {bool subdued = false}) {
    if (!_canWrite) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          'No attachments',
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      );
    }

    return Tooltip(
      message: _attachmentLimits,
      child: _addAttachmentMenu(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: kIsWeb && MediaQuery.sizeOf(context).width >= 720
                ? 40
                : 48,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: subdued
                  ? Colors.transparent
                  : Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                children: [
                  Icon(
                    Icons.attach_file,
                    size: 18,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      subdued
                          ? 'Add attachment'
                          : 'Add a file, photo, or video',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.add,
                    size: 18,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

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
