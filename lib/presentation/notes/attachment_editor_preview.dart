part of 'attachment_editor_panel.dart';

extension _AttachmentEditorPreview on _AttachmentEditorPanelState {
  void _clearPreview() {
    final item = _previewItem;
    if (item != null && _previewReference != null) {
      _previewService?.cancelMedia(_previewReference!, item.id);
    }
    final media = _media;
    if (media != null) unawaited(media.close().catchError((Object _) {}));
    final bytes = _preview;
    if (bytes != null) {
      unawaited(
        ResizeImage(MemoryImage(bytes), width: 1024, height: 1024).evict(),
      );
      bytes.fillRange(0, bytes.length, 0);
    }
    _preview = null;
    _previewItem = null;
    _media = null;
    _exporting = false;
    _previewService = null;
    _previewReference = null;
  }

  Stream<List<int>> _readItem(
    AttachmentApplicationService service,
    _AttachmentItem item,
    int start,
    int end,
  ) => item.attachment != null
      ? service.read(_reference, item.attachment!, start: start, end: end)
      : service.readLocal(_reference, item.id, start: start, end: end);
  Future<void> _open(_AttachmentItem item, {bool exportFile = false}) async {
    if (!_allowed ||
        exportFile && !_capabilities.canExport ||
        _working.contains('open/${item.id}')) {
      return;
    }
    final generation = _generation;
    _update(() {
      _clearPreview();
      // A previous upload's terminal progress belongs to that transfer. Cached
      // reads may emit no new progress; keep their Ready status truthful.
      _progress.remove(item.id);
      _previewItem = item;
      _exporting = exportFile;
      _previewService = _service;
      _previewReference = _reference;
    });
    await _perform('open/${item.id}', (service) async {
      if (exportFile || {'video/mp4', 'application/pdf'}.contains(item.mime)) {
        final handle = exportFile
            ? await service.openExport(_reference, item.attachment!)
            : item.attachment != null
            ? await service.openMedia(_reference, item.attachment!)
            : await service.openPendingMedia(_reference, item.draft!);
        if (!_current(generation) || _previewItem != item) {
          await handle.close();
          return;
        }
        if (handle.exported) {
          _update(() {
            _clearPreview();
            _error = 'Attachment saved to Downloads/NoteFlow.';
          });
        } else {
          _update(() => _media = handle);
        }
        return;
      }
      final limit = item.mime.startsWith('image/')
          ? 10 * 1024 * 1024
          : 64 * 1024;
      final end = item.size < limit ? item.size : limit;
      final bytes = Uint8List(end);
      var offset = 0;
      try {
        await for (final chunk in _readItem(service, item, 0, end)) {
          try {
            if (!_current(generation) || _previewItem != item) return;
            if (offset + chunk.length > end) {
              throw StateError('Invalid preview range');
            }
            bytes.setRange(offset, offset + chunk.length, chunk);
            offset += chunk.length;
          } finally {
            chunk.fillRange(0, chunk.length, 0);
          }
        }
        if (offset != end) throw StateError('Incomplete preview');
        if (_current(generation) && _previewItem == item) {
          _update(() => _preview = Uint8List.fromList(bytes));
        }
      } finally {
        bytes.fillRange(0, bytes.length, 0);
      }
    });
  }

  Widget _previewWidget() {
    final item = _previewItem!, bytes = _preview, media = _media;
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w500),
                ),
              ),
              TextButton.icon(
                onPressed: () => _update(_clearPreview),
                icon: const Icon(Icons.close, size: 18),
                label: const Text('Close preview'),
              ),
            ],
          ),
        ),
        if (media?.uri != null)
          SizedBox(
            height: _exporting
                ? 100
                : item.mime == 'application/pdf'
                ? 420
                : 260,
            child: AttachmentMediaSurface(
              key: ValueKey(media),
              handle: media!,
              mime: item.mime,
              size: item.size,
              read: (start, end) => _readItem(_service!, item, start, end),
            ),
          ),
        if (bytes != null && item.mime.startsWith('image/'))
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: ColoredBox(
              color: colors.surfaceContainerLow,
              child: Image.memory(
                bytes,
                height: 220,
                fit: BoxFit.contain,
                cacheWidth: 1024,
                cacheHeight: 1024,
                errorBuilder: (_, _, _) => const Text(
                  'Image preview unavailable.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        if (bytes != null && !item.mime.startsWith('image/'))
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: SelectableText(
                utf8.decode(bytes, allowMalformed: true),
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(height: 1.5),
              ),
            ),
          ),
        if (bytes != null && bytes.length < item.size)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Showing the first 64 KiB.',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: colors.onSurfaceVariant),
            ),
          ),
        if (media == null &&
            bytes == null &&
            _working.contains('open/${item.id}'))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              _exporting ? 'Saving attachment…' : 'Opening attachment…',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: colors.onSurfaceVariant),
            ),
          ),
      ],
    );
  }
}
