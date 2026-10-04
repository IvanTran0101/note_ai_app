import 'package:flutter/material.dart';

import '../../application/notes/note_dto.dart';
import 'label_action_fence.dart';
import 'label_catalog_scope.dart';
import 'label_manager_dialog.dart';
import 'label_copy.dart';
import 'note_label_chips.dart';

final class NoteLabelEditor extends StatefulWidget {
  const NoteLabelEditor({
    super.key,
    required this.note,
    required this.readable,
    required this.canManage,
    required this.onChanged,
  });
  final NoteDto note;
  final bool readable, canManage;
  final ValueChanged<NoteDto> onChanged;
  @override
  State<NoteLabelEditor> createState() => _NoteLabelEditorState();
}

final class _NoteLabelEditorState extends State<NoteLabelEditor> {
  bool _busy = false;
  String? _error;
  bool _valid(LabelActionFence fence, NoteDto note) =>
      mounted &&
      fence.live &&
      widget.canManage &&
      widget.readable &&
      widget.note.identity == note.identity;

  Future<void> _choose() async {
    final fence = LabelActionFence.capture(context), captured = widget.note;
    if (fence == null || !_valid(fence, captured) || _busy) return;
    final copy = LabelCopy(context);
    final id = await showDialog<String>(
      context: context,
      builder: (context) => _choices(context, fence, captured, copy),
    );
    if (id == null || !_valid(fence, captured)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final updated = await fence.app.setAttached(
        captured,
        id,
        !captured.labelIds.contains(id),
      );
      if (_valid(fence, captured)) widget.onChanged(updated);
    } on Object {
      if (_valid(fence, captured)) setState(() => _error = copy.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _choices(
    BuildContext context,
    LabelActionFence fence,
    NoteDto captured,
    LabelCopy copy,
  ) {
    if (!fence.visible(context) || !_valid(fence, captured)) {
      return AlertDialog(
        content: Text(copy.error),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(copy.cancel),
          ),
        ],
      );
    }
    final scope = LabelCatalogScope.maybeOf(context)!;
    final rows = scope.labels.where((l) => !l.isDeleted).toList();
    final activeIds = rows.map((l) => l.id).toSet();
    final deletedIds = scope.labels
        .where((l) => l.isDeleted)
        .map((l) => l.id)
        .toSet();
    final obsolete = captured.labelIds.where((id) => !activeIds.contains(id));
    return AlertDialog(
      title: Text(copy.organize),
      content: SizedBox(
        width: 400,
        height: MediaQuery.sizeOf(context).height * .4,
        child: ListView(
          children: [
            if (rows.isEmpty && obsolete.isEmpty)
              Center(child: Text(copy.empty)),
            for (final label in rows)
              CheckboxListTile(
                title: Text(label.name),
                value: captured.labelIds.contains(label.id),
                onChanged: (_) => Navigator.pop(context, label.id),
              ),
            for (final id in obsolete)
              CheckboxListTile(
                title: Text(
                  deletedIds.contains(id) ? copy.removed : copy.unavailable,
                ),
                value: true,
                onChanged: (_) => Navigator.pop(context, id),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(copy.cancel),
        ),
        TextButton(
          onPressed: () => showLabelManager(context),
          child: Text(copy.manage),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final scope = LabelCatalogScope.maybeOf(context);
    if (scope?.application == null ||
        !widget.readable ||
        scope!.actor.isEmpty) {
      return const SizedBox.shrink();
    }
    final copy = LabelCopy(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        NoteLabelChips(note: widget.note, readable: widget.readable),
        if (widget.canManage && widget.note.ownerId == scope.actor)
          TextButton.icon(
            onPressed: _busy ? null : _choose,
            icon: const Icon(Icons.label_outline),
            label: Text(copy.organize),
          ),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null)
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
      ],
    );
  }
}
