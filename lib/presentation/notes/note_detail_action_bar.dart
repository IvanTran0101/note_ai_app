import 'package:flutter/material.dart';

/// Mobile-first actions for the Note Detail editor.
///
/// The widget is intentionally independent from Note/Application contracts so
/// it can be placed in a Scaffold bottomNavigationBar and tested in isolation.
/// Scaffold's resizeToAvoidBottomInset moves that slot above the IME; SafeArea
/// protects it from the home indicator without creating a second scroll owner.
final class NoteDetailActionBar extends StatelessWidget {
  const NoteDetailActionBar({
    super.key,
    required this.isSaving,
    required this.isSummarizing,
    required this.canSave,
    required this.canSummarize,
    required this.onSave,
    required this.onSummarize,
    required this.onMore,
    required this.saveLabel,
    required this.summarizeLabel,
    required this.moreLabel,
    required this.savingLabel,
    required this.summarizingLabel,
  });

  final bool isSaving;
  final bool isSummarizing;
  final bool canSave;
  final bool canSummarize;
  final VoidCallback? onSave;
  final VoidCallback? onSummarize;
  final VoidCallback? onMore;
  final String saveLabel;
  final String summarizeLabel;
  final String moreLabel;
  final String savingLabel;
  final String summarizingLabel;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final bool saveEnabled =
        canSave && !isSaving && !isSummarizing && onSave != null;
    final bool summarizeEnabled =
        canSummarize && !isSaving && !isSummarizing && onSummarize != null;
    final bool moreEnabled = !isSaving && !isSummarizing && onMore != null;

    return Material(
      color: colors.surfaceContainer,
      elevation: 2,
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            return Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  if (onSave != null)
                    Semantics(
                      button: true,
                      enabled: saveEnabled,
                      label: isSaving ? savingLabel : saveLabel,
                      child: FilledButton.icon(
                        key: const ValueKey<String>('note-detail-save'),
                        onPressed: saveEnabled ? onSave : null,
                        icon: isSaving
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.save_outlined),
                        label: Text(isSaving ? savingLabel : saveLabel),
                      ),
                    ),
                  Semantics(
                    button: true,
                    enabled: summarizeEnabled,
                    label: isSummarizing ? summarizingLabel : summarizeLabel,
                    child: FilledButton.tonalIcon(
                      key: const ValueKey<String>('note-detail-summarize'),
                      onPressed: summarizeEnabled ? onSummarize : null,
                      icon: isSummarizing
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.auto_awesome_outlined),
                      label: Text(
                        isSummarizing ? summarizingLabel : summarizeLabel,
                      ),
                    ),
                  ),
                  if (onMore != null)
                    Semantics(
                      button: true,
                      enabled: moreEnabled,
                      label: moreLabel,
                      child: OutlinedButton.icon(
                        key: const ValueKey<String>('note-detail-more'),
                        onPressed: moreEnabled ? onMore : null,
                        icon: const Icon(Icons.more_horiz),
                        label: Text(moreLabel),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
