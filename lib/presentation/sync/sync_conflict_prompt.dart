import 'package:flutter/material.dart';

import '../../application/sync/sync_conflict.dart';
import '../../application/sync/sync_conflict_resolver.dart';
import '../../application/sync/sync_snapshot.dart';
import 'sync_localizations.dart';

enum SyncDirtyDraftChoice { saveAsNew, discard, cancel }

Future<SyncConflictChoice?> showSyncConflictChoices({
  required BuildContext context,
  required SyncConflict conflict,
}) {
  final SyncCopy copy = SyncCopy.of(context);
  final bool compact = MediaQuery.sizeOf(context).width < 600;
  if (compact) {
    return showModalBottomSheet<SyncConflictChoice>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: _SyncConflictChoices(
            conflict: conflict,
            copy: copy,
            compact: true,
          ),
        ),
      ),
    );
  }
  return showDialog<SyncConflictChoice>(
    context: context,
    builder: (BuildContext context) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 680),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: _SyncConflictChoices(
            conflict: conflict,
            copy: copy,
            compact: false,
          ),
        ),
      ),
    ),
  );
}

Future<SyncDirtyDraftChoice?> showSyncDirtyDraftChoices({
  required BuildContext context,
}) {
  final SyncCopy copy = SyncCopy.of(context);
  return showDialog<SyncDirtyDraftChoice>(
    context: context,
    builder: (BuildContext context) => AlertDialog(
      title: Text(copy.draftConflictTitle),
      content: Text(copy.draftConflictMessage),
      actions: <Widget>[
        TextButton(
          key: const ValueKey<String>('sync-draft-cancel'),
          onPressed: () =>
              Navigator.of(context).pop(SyncDirtyDraftChoice.cancel),
          child: Text(copy.cancel),
        ),
        TextButton(
          key: const ValueKey<String>('sync-draft-discard'),
          onPressed: () =>
              Navigator.of(context).pop(SyncDirtyDraftChoice.discard),
          child: Text(copy.discardDraftAndContinue),
        ),
        FilledButton(
          key: const ValueKey<String>('sync-draft-save-as-new'),
          onPressed: () =>
              Navigator.of(context).pop(SyncDirtyDraftChoice.saveAsNew),
          child: Text(copy.saveAsNew),
        ),
      ],
    ),
  );
}

final class _SyncConflictChoices extends StatelessWidget {
  const _SyncConflictChoices({
    required this.conflict,
    required this.copy,
    required this.compact,
  });

  final SyncConflict conflict;
  final SyncCopy copy;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final SyncNoteSnapshot? remote = conflict.remote;
    final Widget local = _VersionCard(
      label: copy.localVersion,
      title: conflict.local.title,
      content: conflict.local.content,
      detail: copy.noteStatus(conflict.local.status),
    );
    final Widget server = _VersionCard(
      label: copy.remoteVersion,
      title: remote?.title ?? '',
      content: remote == null
          ? copy.remoteMissing
          : remote.isDeleted
          ? copy.remoteDeleted
          : remote.content,
      detail: remote == null
          ? copy.remoteMissing
          : 'Revision ${remote.revision}',
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(copy.conflictTitle, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        if (compact) ...<Widget>[local, const SizedBox(height: 12), server] else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(child: local),
              const SizedBox(width: 12),
              Expanded(child: server),
            ],
          ),
        const SizedBox(height: 20),
        if (compact)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: _choiceButtons(context),
          )
        else
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: _choiceButtons(context).reversed.toList(),
          ),
      ],
    );
  }

  List<Widget> _choiceButtons(BuildContext context) => <Widget>[
    TextButton(
      key: const ValueKey<String>('sync-conflict-later'),
      onPressed: () => Navigator.of(context).pop(SyncConflictChoice.later),
      child: Text(copy.later),
    ),
    OutlinedButton(
      key: const ValueKey<String>('sync-conflict-use-local'),
      onPressed: () => Navigator.of(context).pop(SyncConflictChoice.useLocal),
      child: Text(copy.useLocal),
    ),
    FilledButton(
      key: const ValueKey<String>('sync-conflict-use-remote'),
      onPressed: () => Navigator.of(context).pop(SyncConflictChoice.useRemote),
      child: Text(copy.useRemote),
    ),
  ];
}

final class _VersionCard extends StatelessWidget {
  const _VersionCard({
    required this.label,
    required this.title,
    required this.content,
    required this.detail,
  });

  final String label;
  final String title;
  final String content;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      label: '$label. $title. $content. $detail',
      child: Container(
        constraints: const BoxConstraints(minHeight: 150, maxHeight: 240),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.surfaceContainerLow,
          border: Border.all(color: colors.outlineVariant),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(label, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Text(
              title.isEmpty ? '—' : title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: SingleChildScrollView(
                child: SelectableText(
                  content.isEmpty ? '—' : content,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(detail, style: Theme.of(context).textTheme.labelSmall),
          ],
        ),
      ),
    );
  }
}
