import 'package:flutter/material.dart';

import '../../application/labels/note_query.dart';
import '../../application/notes/note_dto.dart';
import 'label_catalog_scope.dart';
import 'label_manager_dialog.dart';
import 'label_copy.dart';

final class LabelFilterBar extends StatelessWidget {
  const LabelFilterBar({
    super.key,
    required this.notes,
    required this.selected,
    required this.onChanged,
    required this.readable,
    this.allowManage = true,
  });
  final List<NoteDto> notes;
  final Set<LabelSelection> selected;
  final ValueChanged<Set<LabelSelection>> onChanged;
  final bool Function(NoteDto) readable;
  final bool allowManage;
  @override
  Widget build(BuildContext context) {
    final scope = LabelCatalogScope.maybeOf(context);
    if (scope?.application == null || scope!.actor.isEmpty) {
      return const SizedBox.shrink();
    }
    final choices = <LabelSelection, String>{};
    for (final note in notes) {
      for (final label in visibleLabels(
        note,
        scope.labels,
        actor: scope.actor,
        readable: readable(note),
      )) {
        choices[(ownerId: note.ownerId, id: label.id)] = label.name;
      }
    }
    // Own catalog is an independent authorized organization surface.
    if (allowManage) {
      for (final label in scope.labels.where(
        (l) => l.ownerId == scope.actor && !l.isDeleted,
      )) {
        choices[(ownerId: label.ownerId, id: label.id)] = label.name;
      }
    }
    final copy = LabelCopy(context);
    final tombstones = scope.labels
        .where((l) => l.ownerId == scope.actor && l.isDeleted)
        .map((l) => (ownerId: l.ownerId, id: l.id))
        .toSet();
    final retained = selected.difference(tombstones);
    if (retained.length != selected.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted &&
            LabelCatalogScope.maybeOf(context)?.actor == scope.actor) {
          onChanged(retained);
        }
      });
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(copy.filter),
          for (final choice in choices.entries)
            FilterChip(
              key: ValueKey(('label-filter', choice.key)),
              label: Text(choice.value),
              selected: selected.contains(choice.key),
              onSelected: (value) {
                final next = Set<LabelSelection>.of(selected);
                value ? next.add(choice.key) : next.remove(choice.key);
                onChanged(next);
              },
            ),
          if (selected.isNotEmpty)
            TextButton(onPressed: () => onChanged({}), child: Text(copy.clear)),
          if (allowManage)
            TextButton.icon(
              onPressed: () => showLabelManager(context),
              icon: const Icon(Icons.label_outline),
              label: Text(copy.manage),
            ),
        ],
      ),
    );
  }
}
