import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

enum AttachmentFileRowAction { retry, download, remove }

/// Compact file row used by the note attachment area.
///
/// The widget only presents actions supplied by its caller. The caller remains
/// responsible for the note's access, transfer, and export rules.
final class AttachmentFileRow extends StatefulWidget {
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

  @override
  State<AttachmentFileRow> createState() => _AttachmentFileRowState();
}

final class _AttachmentFileRowState extends State<AttachmentFileRow> {
  bool _hovered = false;
  bool _actionsFocused = false;

  IconData get _fileIcon => Icons.upload_file_outlined;

  bool get _hasActions =>
      widget.onRetry != null ||
      widget.onDownload != null ||
      widget.onRemove != null;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final compactWeb = kIsWeb && MediaQuery.sizeOf(context).width >= 720;
    final titleStyle = text.bodyMedium?.copyWith(
      fontSize: compactWeb ? 16 : 17,
      height: 1.5,
      color: colors.onSurface,
    );
    final detailStyle = text.bodySmall?.copyWith(
      fontSize: 12,
      height: 4 / 3,
      color: colors.onSurfaceVariant,
    );
    final showActions =
        !compactWeb ||
        _hovered ||
        _actionsFocused ||
        MediaQuery.accessibleNavigationOf(context);

    return Tooltip(
      message: widget.statusLabel,
      child: MouseRegion(
        onEnter: (_) {
          if (!_hovered) setState(() => _hovered = true);
        },
        onExit: (_) {
          if (_hovered) setState(() => _hovered = false);
        },
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            key: const ValueKey('attachment-file-row-open'),
            onTap: widget.onOpen,
            borderRadius: BorderRadius.circular(4),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: compactWeb ? 28 : 48),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Row(
                  children: [
                    Icon(_fileIcon, size: 22, color: colors.onSurfaceVariant),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Flexible(
                                flex: 3,
                                child: Text(
                                  widget.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: titleStyle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                flex: 2,
                                child: Tooltip(
                                  message: widget.sizeLabel,
                                  child: Text(
                                    widget.sizeLabel,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: detailStyle,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (widget.statusLabel != 'Ready') ...[
                            const SizedBox(height: 2),
                            Text(
                              widget.statusLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: detailStyle,
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (_hasActions)
                      Focus(
                        key: const ValueKey('attachment-actions-focus-scope'),
                        canRequestFocus: false,
                        skipTraversal: true,
                        onFocusChange: (focused) {
                          if (_actionsFocused != focused) {
                            setState(() => _actionsFocused = focused);
                          }
                        },
                        child: AnimatedOpacity(
                          key: const ValueKey('attachment-actions-reveal'),
                          duration: const Duration(milliseconds: 100),
                          opacity: showActions ? 1 : 0,
                          alwaysIncludeSemantics: true,
                          child: IgnorePointer(
                            ignoring: !showActions,
                            child: SizedBox.square(
                              dimension: compactWeb ? 28 : 48,
                              child: PopupMenuButton<AttachmentFileRowAction>(
                                tooltip: 'Attachment actions',
                                padding: EdgeInsets.zero,
                                iconSize: 18,
                                icon: Icon(
                                  Icons.more_horiz,
                                  color: colors.onSurfaceVariant,
                                ),
                                onSelected: _selectAction,
                                itemBuilder: (context) => [
                                  if (widget.onRetry != null)
                                    PopupMenuItem(
                                      value: AttachmentFileRowAction.retry,
                                      enabled: widget.retryEnabled,
                                      child: const _ActionLabel(
                                        icon: Icons.refresh,
                                        label: 'Retry upload',
                                      ),
                                    ),
                                  if (widget.onDownload != null)
                                    const PopupMenuItem(
                                      value: AttachmentFileRowAction.download,
                                      child: _ActionLabel(
                                        icon: Icons.download_outlined,
                                        label: 'Download attachment',
                                      ),
                                    ),
                                  if (widget.onRemove != null)
                                    PopupMenuItem(
                                      value: AttachmentFileRowAction.remove,
                                      enabled: widget.removeEnabled,
                                      child: _ActionLabel(
                                        icon: Icons.close,
                                        label: widget.removeLabel,
                                      ),
                                    ),
                                ],
                              ),
                            ),
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
    );
  }

  void _selectAction(AttachmentFileRowAction action) {
    switch (action) {
      case AttachmentFileRowAction.retry:
        widget.onRetry?.call();
        break;
      case AttachmentFileRowAction.download:
        widget.onDownload?.call();
        break;
      case AttachmentFileRowAction.remove:
        widget.onRemove?.call();
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
