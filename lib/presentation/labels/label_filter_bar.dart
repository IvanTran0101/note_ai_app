import 'package:flutter/material.dart';

import '../../application/labels/note_query.dart';
import '../../application/notes/note_dto.dart';
import 'label_catalog_scope.dart';
import 'label_manager_dialog.dart';
import 'label_copy.dart';
import '../notes/notes_theme_tokens.dart';

final class LabelFilterBar extends StatelessWidget {
  const LabelFilterBar({
    super.key,
    required this.notes,
    required this.selected,
    required this.onChanged,
    required this.readable,
    this.allowManage = true,
    this.dense = false,
    this.singleLine = false,
  });
  final List<NoteDto> notes;
  final Set<LabelSelection> selected;
  final ValueChanged<Set<LabelSelection>> onChanged;
  final bool Function(NoteDto) readable;
  final bool allowManage;
  final bool dense;
  final bool singleLine;
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
    final tokens = NoteFlowUiTokens.of(context);
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
    final List<Widget> chips = [
      for (final choice in choices.entries)
        FilterChip(
          key: ValueKey(('label-filter', choice.key)),
          label: Text(choice.value),
          labelStyle: TextStyle(fontSize: 12, color: tokens.textSecondary),
          labelPadding: EdgeInsets.symmetric(horizontal: dense ? 4 : 8),
          padding: EdgeInsets.symmetric(horizontal: dense ? 6 : 8),
          visualDensity: dense && !singleLine
              ? VisualDensity.compact
              : VisualDensity.standard,
          materialTapTargetSize: dense && !singleLine
              ? MaterialTapTargetSize.shrinkWrap
              : MaterialTapTargetSize.padded,
          backgroundColor: Colors.transparent,
          selectedColor: tokens.textPrimary.withValues(alpha: .07),
          side: BorderSide(color: tokens.divider),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          selected: selected.contains(choice.key),
          onSelected: (value) {
            final next = Set<LabelSelection>.of(selected);
            value ? next.add(choice.key) : next.remove(choice.key);
            onChanged(next);
          },
        ),
    ];
    final Widget clearButton = TextButton(
      onPressed: () => onChanged({}),
      style: TextButton.styleFrom(
        minimumSize: Size(48, dense && !singleLine ? 32 : 48),
        visualDensity: dense && !singleLine
            ? VisualDensity.compact
            : VisualDensity.standard,
        tapTargetSize: dense && !singleLine
            ? MaterialTapTargetSize.shrinkWrap
            : MaterialTapTargetSize.padded,
        foregroundColor: tokens.textSecondary,
        textStyle: Theme.of(context).textTheme.labelLarge
            ?.copyWith(fontSize: 12, fontWeight: FontWeight.w400),
      ),
      child: Text(copy.clear),
    );
    final Widget manageButton = TextButton.icon(
      onPressed: () => showLabelManager(context),
      icon: const Icon(Icons.label_outline),
      label: Text(copy.manage),
      style: TextButton.styleFrom(
        foregroundColor: tokens.textSecondary,
        iconSize: dense ? 16 : 18,
        minimumSize: Size(48, dense && !singleLine ? 32 : 48),
        padding: EdgeInsets.symmetric(horizontal: dense ? 6 : 12),
        visualDensity: dense && !singleLine
            ? VisualDensity.compact
            : VisualDensity.standard,
        tapTargetSize: dense && !singleLine
            ? MaterialTapTargetSize.shrinkWrap
            : MaterialTapTargetSize.padded,
        textStyle: Theme.of(context).textTheme.labelLarge
            ?.copyWith(fontSize: 12, fontWeight: FontWeight.w400),
      ),
    );
    final Widget filterLabel = singleLine || dense
        ? Tooltip(
            message: copy.filter,
            child: Semantics(
              label: copy.filter,
              child: SizedBox(
                width: 32,
                height: dense && !singleLine ? 32 : 48,
                child: Icon(
                  Icons.filter_list,
                  size: 18,
                  color: tokens.textMuted,
                ),
              ),
            ),
          )
        : Text(
            copy.filter,
            style: TextStyle(fontSize: 12, color: tokens.textMuted),
          );
    final Widget controls = Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        filterLabel,
        ...chips,
        if (selected.isNotEmpty) clearButton,
        if (allowManage) manageButton,
      ],
    );
    return Padding(
      padding: EdgeInsets.symmetric(vertical: dense ? 0 : 8),
      child: singleLine
          ? Row(
              children: [
                filterLabel,
                const SizedBox(width: 4),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (int index = 0; index < chips.length; index++) ...[
                          if (index > 0) const SizedBox(width: 6),
                          chips[index],
                        ],
                        if (selected.isNotEmpty) clearButton,
                      ],
                    ),
                  ),
                ),
                if (allowManage) manageButton,
              ],
            )
          : controls,
    );
  }
}
