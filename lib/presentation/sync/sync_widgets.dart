import 'package:flutter/material.dart';

import '../../application/sync/note_sync_status.dart';
import '../../application/sync/sync_status.dart';
import '../common/note_flow_primitives.dart';
import 'sync_localizations.dart';
import 'sync_presentation_controller.dart';

/// Compact, readable account sync state and a foreground retry action.
final class SyncStatusPanel extends StatelessWidget {
  const SyncStatusPanel({
    super.key,
    required this.controller,
    this.compact = false,
    this.iconOnly = false,
    this.additionalStatus,
    this.localPending = false,
    this.localFailed = false,
  });

  final SyncPresentationController controller;
  final bool compact;
  final bool iconOnly, localPending, localFailed;
  final String? additionalStatus;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (BuildContext context, Widget? child) {
        final SyncCopy copy = SyncCopy.of(context);
        final ColorScheme colors = Theme.of(context).colorScheme;
        final String title = _title(copy);
        final List<String> details = <String>[
          if (controller.loadError == null && controller.status.failure != null)
            copy.failure(controller.status.failure),
          if (controller.pendingCount > 0)
            '${controller.pendingCount} ${copy.pendingChanges}',
          if (controller.conflictCount > 0)
            copy.conflictCount(controller.conflictCount),
          if (controller.blockedInvalidMutationCount > 0)
            copy.invalidMutationHint,
        ];
        final String semanticLabel = <String>[title, ...details].join('. ');
        final VoidCallback? foregroundAction =
            controller.isLoading || controller.status.isSyncing
            ? null
            : controller.loadError == null
            ? controller.syncNow
            : controller.refresh;
        if (iconOnly) {
          final label = <String>[
            if (additionalStatus != null)
              additionalStatus!.trim().replaceFirst(RegExp(r'[.!?…]+$'), ''),
            semanticLabel,
            controller.loadError != null ||
                    controller.status.status == SyncStatus.failed ||
                    controller.status.status == SyncStatus.offline
                ? copy.retry
                : copy.syncNow,
          ].join('. ');
          return Semantics(
            key: const ValueKey<String>('sync-now'),
            liveRegion: true,
            button: true,
            enabled: foregroundAction != null,
            label: label,
            onTap: foregroundAction,
            excludeSemantics: true,
            child: IconButton(
              tooltip: label,
              onPressed: foregroundAction,
              icon: controller.status.isSyncing
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      localFailed
                          ? Icons.error_outline
                          : localPending &&
                                !controller.isLoading &&
                                controller.loadError == null &&
                                controller.status.status == SyncStatus.idle
                          ? Icons.cloud_upload_outlined
                          : _icon,
                      size: 20,
                    ),
            ),
          );
        }
        if (compact) {
          return Semantics(
            container: true,
            explicitChildNodes: true,
            liveRegion: true,
            label: semanticLabel,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Icon(_icon, size: 18, color: colors.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ExcludeSemantics(
                      child: Tooltip(
                        message: semanticLabel,
                        child: Text(
                          <String>[title, ...details].join(' · '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey<String>('sync-now'),
                    tooltip:
                        controller.loadError != null ||
                            controller.status.status == SyncStatus.failed ||
                            controller.status.status == SyncStatus.offline
                        ? copy.retry
                        : copy.syncNow,
                    onPressed:
                        controller.isLoading || controller.status.isSyncing
                        ? null
                        : controller.loadError == null
                        ? controller.syncNow
                        : controller.refresh,
                    icon: controller.status.isSyncing
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.sync, size: 20),
                  ),
                ],
              ),
            ),
          );
        }
        return Semantics(
          container: true,
          liveRegion: true,
          label: semanticLabel,
          child: Card(
            margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: <Widget>[
                  NoteFlowStateTransition(
                    child: Icon(
                      _icon,
                      key: ValueKey<IconData>(_icon),
                      color: colors.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        NoteFlowStateTransition(
                          child: Text(
                            title,
                            key: ValueKey<String>(title),
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                        for (final String detail in details)
                          Text(
                            detail,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    key: const ValueKey<String>('sync-now'),
                    onPressed:
                        controller.isLoading || controller.status.isSyncing
                        ? null
                        : controller.loadError == null
                        ? controller.syncNow
                        : controller.refresh,
                    icon: controller.status.isSyncing
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.sync),
                    label: Text(
                      controller.loadError != null ||
                              controller.status.status == SyncStatus.failed ||
                              controller.status.status == SyncStatus.offline
                          ? copy.retry
                          : copy.syncNow,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _title(SyncCopy copy) {
    if (controller.isLoading) return copy.checking;
    if (controller.loadError != null) return copy.localStoreError;
    final SyncStatus value = controller.status.status;
    if (value == SyncStatus.idle && controller.conflictCount > 0) {
      return copy.conflictsNeedReview;
    }
    if (value == SyncStatus.idle && controller.pendingCount > 0) {
      return copy.pending;
    }
    return copy.status(value);
  }

  IconData get _icon => controller.isLoading
      ? Icons.cloud_sync_outlined
      : controller.status.status == SyncStatus.idle &&
            controller.conflictCount > 0
      ? Icons.compare_arrows
      : switch (controller.status.status) {
          SyncStatus.idle =>
            controller.pendingCount == 0 && controller.conflictCount == 0
                ? Icons.cloud_done_outlined
                : Icons.cloud_upload_outlined,
          SyncStatus.offline => Icons.cloud_off_outlined,
          SyncStatus.syncing => Icons.sync,
          SyncStatus.failed => Icons.error_outline,
        };
}

/// Text-and-icon note state badge; status is never communicated by color alone.
final class SyncNoteStatusBadge extends StatelessWidget {
  const SyncNoteStatusBadge({
    super.key,
    required this.controller,
    required this.noteId,
  });

  final SyncPresentationController controller;
  final String noteId;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (BuildContext context, Widget? child) {
        final NoteSyncStatus? status = controller.noteStatusFor(noteId);
        if (status == null) return const SizedBox.shrink();
        final SyncCopy copy = SyncCopy.of(context);
        final ColorScheme colors = Theme.of(context).colorScheme;
        final Color color = switch (status) {
          NoteSyncStatus.synced => colors.tertiary,
          NoteSyncStatus.pending => colors.primary,
          NoteSyncStatus.failed => colors.error,
          NoteSyncStatus.conflict => colors.error,
        };
        return Semantics(
          key: ValueKey<String>('sync-note-status-$noteId'),
          label: copy.noteStatus(status),
          child: NoteFlowStateTransition(
            child: Chip(
              key: ValueKey<NoteSyncStatus>(status),
              visualDensity: VisualDensity.compact,
              avatar: Icon(_icon(status), size: 16, color: color),
              label: Text(copy.noteStatus(status)),
              side: BorderSide(color: color),
              padding: EdgeInsets.zero,
            ),
          ),
        );
      },
    );
  }

  IconData _icon(NoteSyncStatus status) => switch (status) {
    NoteSyncStatus.synced => Icons.cloud_done_outlined,
    NoteSyncStatus.pending => Icons.schedule,
    NoteSyncStatus.failed => Icons.error_outline,
    NoteSyncStatus.conflict => Icons.compare_arrows,
  };
}
