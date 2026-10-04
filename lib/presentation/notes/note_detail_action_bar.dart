import 'package:flutter/material.dart';

import 'notes_theme_tokens.dart';

/// Mobile-first actions for the Note Detail editor.
///
/// Rendered as a flat Notion-style toolbar: page surface with a hairline top
/// divider instead of a raised bar. The widget is intentionally independent
/// from Note/Application contracts so it can be placed in a Scaffold
/// bottomNavigationBar and tested in isolation. Scaffold's
/// resizeToAvoidBottomInset moves that slot above the IME; SafeArea protects
/// it from the home indicator without creating a second scroll owner.
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
    this.onMoreWithContext,
    required this.saveLabel,
    required this.summarizeLabel,
    required this.moreLabel,
    required this.savingLabel,
    required this.summarizingLabel,
    this.summarizeTooltip,
    this.iconOnly = false,
  });

  final bool isSaving;
  final bool isSummarizing;
  final bool canSave;
  final bool canSummarize;
  final VoidCallback? onSave;
  final VoidCallback? onSummarize;
  final VoidCallback? onMore;
  final ValueChanged<BuildContext>? onMoreWithContext;
  final String saveLabel;
  final String summarizeLabel;
  final String moreLabel;
  final String savingLabel;
  final String summarizingLabel;
  final String? summarizeTooltip;
  final bool iconOnly;

  @override
  Widget build(BuildContext context) {
    final NoteFlowUiTokens tokens = NoteFlowUiTokens.of(context);
    final bool saveEnabled =
        canSave && !isSaving && !isSummarizing && onSave != null;
    final bool summarizeEnabled =
        canSummarize && !isSaving && !isSummarizing && onSummarize != null;
    final bool hasMoreAction = onMore != null || onMoreWithContext != null;
    final bool moreEnabled = !isSaving && !isSummarizing && hasMoreAction;

    void invokeMore(BuildContext buttonContext) {
      final ValueChanged<BuildContext>? withContext = onMoreWithContext;
      if (withContext != null) {
        withContext(buttonContext);
      } else {
        onMore?.call();
      }
    }

    final Widget summarizeButton = Semantics(
      container: true,
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
        label: Text(isSummarizing ? summarizingLabel : summarizeLabel),
      ),
    );
    final Widget summarizeAction = summarizeTooltip == null
        ? summarizeButton
        : Tooltip(message: summarizeTooltip!, child: summarizeButton);

    if (iconOnly) {
      Widget iconAction({
        required String label,
        required Key key,
        required bool enabled,
        required VoidCallback? onPressed,
        required Widget icon,
        String? tooltip,
        ValueChanged<BuildContext>? onPressedWithContext,
      }) {
        return Builder(
          builder: (BuildContext buttonContext) => Semantics(
            container: true,
            button: true,
            enabled: enabled,
            label: label,
            child: IconButton(
              key: key,
              tooltip: tooltip ?? label,
              onPressed: enabled
                  ? () {
                      if (onPressedWithContext != null) {
                        onPressedWithContext(buttonContext);
                      } else {
                        onPressed?.call();
                      }
                    }
                  : null,
              icon: icon,
            ),
          ),
        );
      }

      return Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (onSave != null)
            iconAction(
              label: isSaving ? savingLabel : saveLabel,
              key: const ValueKey<String>('note-detail-save'),
              enabled: saveEnabled,
              onPressed: onSave,
              icon: isSaving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
            ),
          iconAction(
            label: isSummarizing ? summarizingLabel : summarizeLabel,
            key: const ValueKey<String>('note-detail-summarize'),
            enabled: summarizeEnabled,
            onPressed: onSummarize,
            icon: isSummarizing
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_awesome_outlined),
            tooltip: summarizeTooltip,
          ),
          if (onMore != null)
            iconAction(
              label: moreLabel,
              key: const ValueKey<String>('note-detail-more'),
              enabled: moreEnabled,
              onPressed: onMore,
              icon: const Icon(Icons.more_horiz),
              onPressedWithContext: onMoreWithContext,
            ),
        ],
      );
    }

    return Material(
      color: tokens.pageSurface,
      elevation: 0,
      child: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: tokens.divider)),
        ),
        child: SafeArea(
          top: false,
          minimum: const EdgeInsets.fromLTRB(
            NoteFlowSpacing.md,
            NoteFlowSpacing.sm,
            NoteFlowSpacing.md,
            NoteFlowSpacing.sm,
          ),
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              return Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: NoteFlowSpacing.sm,
                  runSpacing: NoteFlowSpacing.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    if (onSave != null)
                      Semantics(
                        container: true,
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
                    summarizeAction,
                    if (hasMoreAction)
                      Builder(
                        builder: (BuildContext buttonContext) => Semantics(
                          container: true,
                          button: true,
                          enabled: moreEnabled,
                          label: moreLabel,
                          child: OutlinedButton.icon(
                            key: const ValueKey<String>('note-detail-more'),
                            onPressed: moreEnabled
                                ? () => invokeMore(buttonContext)
                                : null,
                            icon: const Icon(Icons.more_horiz),
                            label: Text(moreLabel),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
