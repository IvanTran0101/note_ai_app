import 'package:flutter/material.dart';

import '../../application/labels/note_query.dart';
import '../../application/notes/note_dto.dart';
import 'label_catalog_scope.dart';

final class NoteLabelChips extends StatelessWidget {
  const NoteLabelChips({super.key, required this.note, required this.readable});
  final NoteDto note;
  final bool readable;
  @override
  Widget build(BuildContext context) {
    final scope = LabelCatalogScope.maybeOf(context);
    if (scope == null || !readable) return const SizedBox.shrink();
    final labels = visibleLabels(
      note,
      scope.labels,
      actor: scope.actor,
      readable: readable,
    );
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final label in labels)
          Chip(
            key: ValueKey(('note-label', note.identity, label.id)),
            label: Text(label.name),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
          ),
      ],
    );
  }
}
