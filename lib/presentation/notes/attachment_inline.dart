part of 'attachment_editor_panel.dart';

extension _AttachmentEditorInline on _AttachmentEditorPanelState {
  bool _shouldRetryDraft(LocalAttachmentDraft draft) {
    if (!widget.inlineLayout) return true;
    final inlineController = widget.inlineController;
    return inlineController != null &&
        inlineController.referencedAttachmentIds.contains(draft.cacheId);
  }

  List<LocalAttachmentDraft> _unboundPendingDrafts() {
    final associated = widget.note.attachments.map((item) => item.id).toSet();
    final referenced =
        widget.inlineController?.referencedAttachmentIds.toSet() ??
        const <String>{};
    return _pending
        .where(
          (draft) =>
              !associated.contains(draft.cacheId) &&
              !referenced.contains(draft.cacheId),
        )
        .toList(growable: false);
  }

  Widget _buildInlineBlock(
    BuildContext context,
    String blockId,
    String? attachmentId,
  ) {
    if (!_allowed || _service == null) return const SizedBox.shrink();

    if (attachmentId == null) {
      return _emptyInlineBlock(context, blockId);
    }

    Attachment? attachment;
    for (final item in widget.note.attachments) {
      if (item.id == attachmentId) {
        attachment = item;
        break;
      }
    }
    LocalAttachmentDraft? draft;
    for (final item in _pending) {
      if (item.cacheId == attachmentId) {
        draft = item;
        break;
      }
    }
    if (attachment == null && draft == null) {
      return _unavailableInlineBlock(context, loading: _loading);
    }

    final item = attachment != null
        ? _AttachmentItem.associated(attachment)
        : _AttachmentItem.local(draft!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _row(item),
        if (draft != null && widget.note.contentRevision == 0)
          _localFirstHint(context),
        if (_previewItem?.id == item.id) ...[
          const SizedBox(height: 4),
          _previewWidget(),
        ],
      ],
    );
  }

  Widget _emptyInlineBlock(BuildContext context, String blockId) {
    final colors = Theme.of(context).colorScheme;
    final canUpload = _canWrite && !_busy;
    final unbound = _unboundPendingDrafts();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_working.contains('recover/inline'))
          const LinearProgressIndicator(minHeight: 2),
        Material(
          color: Colors.transparent,
          child: InkWell(
            key: ValueKey('attachment-inline-placeholder-$blockId'),
            onTap: canUpload
                ? () => unawaited(_showInlinePicker(context, blockId))
                : null,
            borderRadius: BorderRadius.circular(4),
            child: Ink(
              width: double.infinity,
              decoration: BoxDecoration(
                color: colors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(4),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.upload_file_outlined,
                        size: 20,
                        color: colors.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          canUpload ? 'Upload a file' : 'File',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                fontSize: 14,
                                color: colors.onSurfaceVariant,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (canUpload && unbound.isNotEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => unawaited(_recoverPendingForBlock(blockId)),
              icon: const Icon(Icons.refresh, size: 16),
              label: Text(
                'Retry local files (${unbound.length})',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              style: TextButton.styleFrom(
                minimumSize: const Size(48, 36),
                visualDensity: VisualDensity.compact,
                textStyle: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
        if (_inlineErrorBlock == blockId && _error != null)
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 2, bottom: 4),
            child: Text(
              _error!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: colors.error),
            ),
          ),
      ],
    );
  }

  Widget _unavailableInlineBlock(
    BuildContext context, {
    required bool loading,
  }) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(4),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Icon(
                  Icons.insert_drive_file_outlined,
                  size: 20,
                  color: colors.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    loading ? 'Loading file…' : 'File unavailable',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(color: colors.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
