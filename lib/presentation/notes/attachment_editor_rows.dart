part of 'attachment_editor_panel.dart';

extension _AttachmentEditorRows on _AttachmentEditorPanelState {
  Widget _buildPanel(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(child: Text('Attachments')),
              if (_canWrite)
                PopupMenuButton<AttachmentSource>(
                  enabled: !_busy,
                  tooltip: 'Add attachment',
                  icon: const Icon(Icons.attach_file),
                  onSelected: (source) => unawaited(_pick(source)),
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: AttachmentSource.files,
                      child: Text('Choose files'),
                    ),
                    PopupMenuItem(
                      value: AttachmentSource.gallery,
                      child: Text('Gallery'),
                    ),
                    PopupMenuItem(
                      value: AttachmentSource.cameraPhoto,
                      child: Text('Take photo'),
                    ),
                    PopupMenuItem(
                      value: AttachmentSource.cameraVideo,
                      child: Text('Record video'),
                    ),
                  ],
                ),
            ],
          ),
          if (_canWrite)
            const Text(
              'Images 10 MiB · MP4 50 MiB · PDF/TXT/CSV 20 MiB. Up to 10 files / 100 MiB per note.',
            ),
          if (_busy) const LinearProgressIndicator(),
          if (_pending.isNotEmpty && widget.note.contentRevision == 0)
            const Text(
              'Saved on this device. Attachments will upload after this note syncs.',
            ),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          for (final draft in _pending.where(
            (d) => !widget.note.attachments.any((a) => a.id == d.cacheId),
          ))
            _row(_AttachmentItem.local(draft)),
          for (final attachment in widget.note.attachments)
            _row(_AttachmentItem.associated(attachment)),
          if (_previewItem != null) _previewWidget(),
        ],
      ),
    ),
  );
  Widget _row(_AttachmentItem item) {
    final progress = _progress[item.id], ready = _ready.contains(item.id);
    final uploading = _working.contains('upload/${item.id}');
    final label = (uploading || _previewItem?.id == item.id) && progress != null
        ? '${progress.phase} · ${progress.completedBytes}/${progress.totalBytes} bytes'
        : item.draft != null
        ? 'Pending on this device · ${item.size} bytes'
        : ready
        ? 'Ready · ${item.size} bytes'
        : 'Awaiting note sync · ${item.size} bytes';
    return ListTile(
      title: Text(item.name),
      subtitle: Text(label),
      onTap: () => unawaited(_open(item)),
      trailing: _canWrite
          ? Wrap(
              children: [
                if (!ready)
                  IconButton(
                    tooltip: 'Retry upload',
                    onPressed: uploading
                        ? null
                        : () => unawaited(_retry(item.id)),
                    icon: const Icon(Icons.refresh),
                  ),
                if (ready && _capabilities.canExport)
                  IconButton(
                    tooltip: 'Download attachment',
                    onPressed: () => unawaited(_open(item, exportFile: true)),
                    icon: const Icon(Icons.download),
                  ),
                IconButton(
                  tooltip: item.draft != null
                      ? 'Remove local attachment'
                      : 'Remove attachment',
                  onPressed: _working.contains('remove/${item.id}')
                      ? null
                      : () => unawaited(_remove(item)),
                  icon: const Icon(Icons.close),
                ),
              ],
            )
          : null,
    );
  }
}
