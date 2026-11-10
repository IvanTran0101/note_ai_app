import 'package:flutter/material.dart';

import '../../domain/note_intelligence/rag_models.dart';
import '../common/note_flow_primitives.dart';
import '../notes/notes_theme_tokens.dart';
import 'rag_copy.dart';

/// The scope chips of the ask-notes screen.
///
/// The control is presentational only: it renders the options this route may
/// ask in and reports the chosen [RagScope]. It never queries, cancels, or
/// clears anything; the page forwards the choice to the single application
/// owner.
final class RagScopeSelector extends StatelessWidget {
  /// Creates the selector for [options] with [selected] already chosen.
  const RagScopeSelector({
    super.key,
    required this.options,
    required this.selected,
    required this.copy,
    required this.onSelected,
  });

  /// The scopes this route may ask in, in display order.
  final List<RagScope> options;

  /// The currently selected scope.
  final RagScope selected;

  /// The resolved localized copy.
  final RagCopy copy;

  /// Reports a newly selected scope to the page.
  final ValueChanged<RagScope> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        NoteFlowSectionLabel(label: copy.scopeLabel, padding: EdgeInsets.zero),
        const SizedBox(height: NoteFlowSpacing.sm),
        Wrap(
          spacing: NoteFlowSpacing.sm,
          runSpacing: NoteFlowSpacing.sm,
          children: <Widget>[
            for (final RagScope option in options)
              ChoiceChip(
                key: ValueKey<String>('rag-scope-${option.type.name}'),
                materialTapTargetSize: NoteFlowLayout.isCompact(context)
                    ? MaterialTapTargetSize.padded
                    : MaterialTapTargetSize.shrinkWrap,
                label: Text(
                  option.isAccount
                      ? copy.scopeAccountLabel
                      : copy.scopeNoteLabel,
                ),
                selected: selected == option,
                onSelected: (bool value) {
                  if (value) {
                    onSelected(option);
                  }
                },
              ),
          ],
        ),
      ],
    );
  }
}
