import 'package:flutter/material.dart';

import '../../application/labels/note_query.dart';
import '../../application/notes/note_dto.dart';
import 'label_catalog_scope.dart';
import 'label_copy.dart';

final class NoteLabelChips extends StatelessWidget {
  const NoteLabelChips({
    super.key,
    required this.note,
    required this.readable,
    this.showCaption = false,
    this.trailing,
  });
  final NoteDto note;
  final bool readable;
  final bool showCaption;
  final Widget? trailing;

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
    final children = <Widget>[];
    if (showCaption) {
      final colors = Theme.of(context).colorScheme;
      children.add(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.label_outline, size: 15, color: colors.onSurfaceVariant),
            const SizedBox(width: 5),
            Text(
              LabelCopy(context).labels,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: colors.onSurfaceVariant),
            ),
          ],
        ),
      );
    }
    final colors = Theme.of(context).colorScheme;
    final maxChipWidth = (MediaQuery.sizeOf(context).width * .55)
        .clamp(120.0, 240.0)
        .toDouble();
    for (final label in labels) {
      children.add(
        Chip(
          key: ValueKey(('note-label', note.identity, label.id)),
          label: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxChipWidth),
            child: Text(
              label.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          labelStyle: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: colors.onSurfaceVariant),
          backgroundColor: colors.surfaceContainerHighest,
          side: BorderSide.none,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          labelPadding: const EdgeInsets.symmetric(horizontal: 5),
          padding: EdgeInsets.zero,
        ),
      );
    }
    if (trailing != null) children.add(trailing!);
    if (children.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: children,
    );
  }
}
