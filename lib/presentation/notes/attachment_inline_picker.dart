part of 'attachment_editor_panel.dart';

extension _AttachmentInlinePicker on _AttachmentEditorPanelState {
  Future<void> _showInlinePicker(
    BuildContext anchorContext,
    String blockId,
  ) async {
    if (!_canWrite || _busy || !anchorContext.mounted) return;
    final pickerAuthority = _pickerAuthority;
    final AttachmentSource? source;
    if (kIsWeb) {
      final anchor = anchorContext.findRenderObject();
      final overlay = Navigator.of(anchorContext).overlay?.context
          .findRenderObject();
      if (anchor is! RenderBox || overlay is! RenderBox) return;
      final topLeft = anchor.localToGlobal(Offset.zero, ancestor: overlay);
      final bottomRight = anchor.localToGlobal(
        anchor.size.bottomRight(Offset.zero),
        ancestor: overlay,
      );
      final menuWidth = (overlay.size.width - 16).clamp(1.0, 304.0).toDouble();
      const menuHeight = 88.0;
      final left = (topLeft.dx + (anchor.size.width - menuWidth) / 2)
          .clamp(
            8.0,
            (overlay.size.width - menuWidth - 8).clamp(8.0, double.infinity),
          )
          .toDouble();
      final above = topLeft.dy - menuHeight - 8;
      final top = (above >= 8 ? above : bottomRight.dy + 8)
          .clamp(
            8.0,
            (overlay.size.height - menuHeight - 8).clamp(8.0, double.infinity),
          )
          .toDouble();
      final colors = Theme.of(anchorContext).colorScheme;
      source = await showMenu<AttachmentSource>(
        context: anchorContext,
        position: RelativeRect.fromRect(
          Rect.fromLTWH(left, top, menuWidth, menuHeight),
          Offset.zero & overlay.size,
        ),
        constraints: BoxConstraints(minWidth: menuWidth, maxWidth: menuWidth),
        menuPadding: EdgeInsets.zero,
        elevation: 4,
        color: colors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: colors.outlineVariant),
        ),
        items: [
          PopupMenuItem<AttachmentSource>(
            enabled: false,
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SizedBox(
              width: menuWidth > 24 ? menuWidth - 24 : menuWidth,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Upload',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(anchorContext).textTheme.bodyMedium
                          ?.copyWith(color: colors.onSurface),
                    ),
                    const SizedBox(height: 3),
                    Container(width: 38, height: 1, color: colors.onSurface),
                  ],
                ),
              ),
            ),
          ),
          PopupMenuItem(
            value: AttachmentSource.files,
            height: 50,
            padding: EdgeInsets.zero,
            child: SizedBox(
              width: menuWidth,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xff2383e2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: SizedBox(
                    height: 36,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          'Choose a file',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(anchorContext).textTheme.labelLarge
                              ?.copyWith(color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    } else {
      source = await showModalBottomSheet<AttachmentSource>(
        context: anchorContext,
        useSafeArea: true,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (sheetContext) => AnimatedPadding(
          duration: const Duration(milliseconds: 120),
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                  child: Text(
                    'Upload',
                    style: Theme.of(sheetContext).textTheme.titleMedium,
                  ),
                ),
                for (final option in _attachmentPickerOptions)
                  ListTile(
                    minTileHeight: 48,
                    leading: Icon(option.icon),
                    title: Text(
                      option.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => Navigator.pop(sheetContext, option.source),
                  ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      );
    }
    if (source != null &&
        mounted &&
        _canWrite &&
        _samePickerResource(pickerAuthority)) {
      await _pickForBlock(blockId, source);
    }
  }
}

final class _AttachmentPickerOption {
  const _AttachmentPickerOption(this.source, this.icon, this.label);
  final AttachmentSource source;
  final IconData icon;
  final String label;
}

const _attachmentPickerOptions = <_AttachmentPickerOption>[
  _AttachmentPickerOption(
    AttachmentSource.files,
    Icons.upload_file_outlined,
    'Choose a file',
  ),
  _AttachmentPickerOption(
    AttachmentSource.gallery,
    Icons.photo_outlined,
    'Choose from gallery',
  ),
  _AttachmentPickerOption(
    AttachmentSource.cameraPhoto,
    Icons.camera_alt_outlined,
    'Take a photo',
  ),
  _AttachmentPickerOption(
    AttachmentSource.cameraVideo,
    Icons.videocam_outlined,
    'Record a video',
  ),
];
