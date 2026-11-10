import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../application/labels/label_application.dart';
import '../../application/labels/local_label_state.dart';
import '../../application/sync/note_sync_status.dart';
import 'label_action_fence.dart';
import 'label_catalog_scope.dart';
import 'label_copy.dart';
import 'label_dialog_layout.dart';

Future<void> showLabelManager(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const _LabelManager());

final class _LabelManager extends StatefulWidget {
  const _LabelManager();
  @override
  State<_LabelManager> createState() => _LabelManagerState();
}

final class _LabelManagerState extends State<_LabelManager> {
  bool _busy = false;
  String? _error;
  LabelActionFence? _fence;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _fence ??= LabelActionFence.capture(context);
  }

  Future<void> _run(Future<void> Function(LabelApplication app) work) async {
    final app = LabelCatalogScope.maybeOf(context)?.application;
    if (app == null || _busy || _fence?.visible(context) != true) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await work(app);
    } on Object {
      if (mounted && _fence?.visible(context) == true) {
        setState(() => _error = LabelCopy(context).error);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit(LocalLabelState? label) async {
    final fence = _fence;
    if (fence == null ||
        !fence.visible(context) ||
        label != null && label.ownerId != fence.actor) {
      return;
    }
    final name = await _nameDialog(context, label?.name, fence);
    if (name == null || !mounted || !fence.visible(context)) return;
    await _run((app) async {
      label == null ? await app.create(name) : await app.rename(label.id, name);
    });
  }

  Future<void> _delete(LocalLabelState label) async {
    final fence = _fence;
    if (fence == null ||
        !fence.visible(context) ||
        label.ownerId != fence.actor) {
      return;
    }
    final copy = LabelCopy(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        backgroundColor: Theme.of(context).colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        title: Text(
          copy.confirmDelete,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
        contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
        actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        content: Builder(
          builder: (c) => Text(fence.visible(c) ? label.name : copy.error),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(copy.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(copy.delete),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted && fence.visible(context)) {
      await _run((app) async {
        await app.delete(label.id);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final copy = LabelCopy(context), scope = LabelCatalogScope.maybeOf(context);
    if (_fence?.visible(context) != true) {
      return AlertDialog(
        scrollable: true,
        backgroundColor: Theme.of(context).colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
        actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        content: Text(copy.error),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(copy.cancel),
          ),
        ],
      );
    }
    final rows =
        scope?.labels
            .where(
              (l) =>
                  l.ownerId == scope.actor &&
                  (!l.isDeleted || l.status == NoteSyncStatus.conflict),
            )
            .toList() ??
        [];
    final bodyHeight = labelDialogBodyHeight(context, .5, minimum: 192);
    return AlertDialog(
      scrollable: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      backgroundColor: Theme.of(context).colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      title: Text(copy.manage, style: Theme.of(context).textTheme.titleMedium),
      titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      contentPadding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      content: SizedBox(
        width: 420,
        height: bodyHeight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (scope?.status == LabelCatalogStatus.loading)
              const LinearProgressIndicator(),
            if (scope?.status == LabelCatalogStatus.error)
              Text(
                copy.error,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: Theme.of(context).colorScheme.error),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _busy ? null : () => _edit(null),
                icon: const Icon(Icons.add, size: 18),
                label: Text(copy.add),
                style: TextButton.styleFrom(
                  minimumSize: Size(
                    0,
                    kIsWeb && MediaQuery.sizeOf(context).width >= 720 ? 36 : 48,
                  ),
                  foregroundColor: Theme.of(context)
                      .colorScheme
                      .onSurfaceVariant,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
            ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (_busy) const LinearProgressIndicator(),
            Expanded(
              child: rows.isEmpty
                  ? Center(child: Text(copy.empty))
                  : ListView(
                      padding: EdgeInsets.zero,
                      children: [for (final label in rows) _row(label, copy)],
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(MaterialLocalizations.of(context).closeButtonLabel),
        ),
      ],
    );
  }

  Widget _row(LocalLabelState label, LabelCopy copy) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Tooltip(
                message: label.name,
                child: Text(
                  label.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            IconButton(
              tooltip: copy.rename,
              onPressed: _busy || label.status == NoteSyncStatus.conflict
                  ? null
                  : () => _edit(label),
              icon: const Icon(Icons.edit_outlined),
            ),
            IconButton(
              tooltip: copy.delete,
              onPressed: _busy || label.status == NoteSyncStatus.conflict
                  ? null
                  : () => _delete(label),
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
        Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant),
        if (label.status == NoteSyncStatus.conflict)
          Wrap(
            children: [
              TextButton(
                onPressed: _busy
                    ? null
                    : () =>
                          _run((app) => app.resolve(label.id, useCloud: false)),
                child: Text(copy.keepLocal),
              ),
              TextButton(
                onPressed: _busy
                    ? null
                    : () =>
                          _run((app) => app.resolve(label.id, useCloud: true)),
                child: Text(copy.useCloud),
              ),
            ],
          ),
        if (label.status == NoteSyncStatus.failed)
          Text(
            copy.error,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
      ],
    ),
  );
}

Future<String?> _nameDialog(
  BuildContext context,
  String? initial,
  LabelActionFence fence,
) async {
  final controller = TextEditingController(text: initial ?? '');
  final copy = LabelCopy(context);
  String? error;
  final result = await showDialog<String>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => !fence.visible(context)
          ? AlertDialog(
              scrollable: true,
              backgroundColor: Theme.of(context).colorScheme.surface,
              surfaceTintColor: Colors.transparent,
              contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              content: Text(copy.error),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(copy.cancel),
                ),
              ],
            )
          : AlertDialog(
              scrollable: true,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              backgroundColor: Theme.of(context).colorScheme.surface,
              surfaceTintColor: Colors.transparent,
              title: Text(
                initial == null ? copy.add : copy.rename,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              content: TextField(
                controller: controller,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: copy.name,
                  errorText: error,
                ),
                onSubmitted: (_) {
                  if (_validName(controller.text)) {
                    Navigator.pop(context, controller.text.trim());
                  }
                },
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(copy.cancel),
                ),
                FilledButton(
                  onPressed: () {
                    if (!_validName(controller.text)) {
                      setState(() => error = copy.invalid);
                      return;
                    }
                    Navigator.pop(context, controller.text.trim());
                  },
                  child: Text(copy.save),
                ),
              ],
            ),
    ),
  );
  // The route transition can still reference this controller for one frame.
  WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
  return result;
}

bool _validName(String raw) =>
    raw.trim().isNotEmpty &&
    raw.trim().runes.length <= 64 &&
    !RegExp(r'[\x00-\x1f\x7f]').hasMatch(raw.trim());
