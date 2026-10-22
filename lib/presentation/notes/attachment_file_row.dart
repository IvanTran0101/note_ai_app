import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

enum AttachmentFileRowAction { retry, download, remove }

/// Compact file row used by the note attachment area.
///
/// The widget only presents actions supplied by its caller. The caller remains
/// responsible for the note's access, transfer, and export rules.
final class AttachmentFileRow extends StatelessWidget {
  const AttachmentFileRow({
    super.key,
    required this.name,
    required this.mimeType,
    required this.sizeLabel,
    required this.statusLabel,
    required this.onOpen,
    this.onRetry,
    this.retryEnabled = true,
    this.onDownload,
    this.onRemove,
    this.removeEnabled = true,
    this.removeLabel = 'Remove attachment',
  });

  final String name;
  final String mimeType;
  final String sizeLabel;
  final String statusLabel;
  final VoidCallback onOpen;
  final VoidCallback? onRetry;
  final bool retryEnabled;
  final VoidCallback? onDownload;
  final VoidCallback? onRemove;
  final bool removeEnabled;
  final String removeLabel;

  IconData get _fileIcon => switch (mimeType) {
    final type when type.startsWith('image/') => Icons.image_outlined,
    'application/pdf' => Icons.picture_as_pdf_outlined,
    'video/mp4' => Icons.movie_outlined,
    _ => Icons.description_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final desktop = kIsWeb && MediaQuery.sizeOf(context).width >= 720;
    final titleStyle = text.bodyMedium?.copyWith(
      fontSize: desktop ? 16 : 17,
      height: 1.35,
      color: colors.onSurface,
    );
    final detailStyle = text.bodySmall?.copyWith(
      fontSize: 12,
      height: 1.35,
      color: colors.onSurfaceVariant,
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const ValueKey('attachment-file-row-open'),
        onTap: onOpen,
        borderRadius: BorderRadius.circular(6),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: desktop ? 40 : 48),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: 2,
              vertical: desktop ? 4 : 0,
            ),
            child: Row(
              children: [
                Icon(_fileIcon, size: 18, color: colors.onSurfaceVariant),
                const SizedBox(width: 10),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      style: titleStyle,
                      children: [
                        TextSpan(text: name),
                        TextSpan(text: '  ·  $sizeLabel', style: detailStyle),
                        TextSpan(text: '  ·  $statusLabel', style: detailStyle),
                      ],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (_hasActions)
                  SizedBox.square(
                    dimension: desktop ? 28 : 48,
                    child: PopupMenuButton<AttachmentFileRowAction>(
                      tooltip: 'Attachment actions',
                      padding: EdgeInsets.zero,
                      iconSize: 18,
                      icon: const Icon(Icons.more_horiz),
                      onSelected: _selectAction,
                      itemBuilder: (context) => [
                        if (onRetry != null)
                          PopupMenuItem(
                            value: AttachmentFileRowAction.retry,
                            enabled: retryEnabled,
                            child: _ActionLabel(
                              icon: Icons.refresh,
                              label: 'Retry upload',
                            ),
                          ),
                        if (onDownload != null)
                          PopupMenuItem(
                            value: AttachmentFileRowAction.download,
                            child: _ActionLabel(
                              icon: Icons.download_outlined,
                              label: 'Download attachment',
                            ),
                          ),
                        if (onRemove != null)
                          PopupMenuItem(
                            value: AttachmentFileRowAction.remove,
                            enabled: removeEnabled,
                            child: _ActionLabel(
                              icon: Icons.close,
                              label: removeLabel,
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool get _hasActions =>
      onRetry != null || onDownload != null || onRemove != null;

  void _selectAction(AttachmentFileRowAction action) {
    switch (action) {
      case AttachmentFileRowAction.retry:
        onRetry?.call();
        break;
      case AttachmentFileRowAction.download:
        onDownload?.call();
        break;
      case AttachmentFileRowAction.remove:
        onRemove?.call();
        break;
    }
  }
}

final class _ActionLabel extends StatelessWidget {
  const _ActionLabel({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 18),
      const SizedBox(width: 12),
      Flexible(child: Text(label)),
    ],
  );
}
