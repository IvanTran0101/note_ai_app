import 'package:flutter/material.dart';

import 'note_detail_localizations.dart';
import 'notes_theme_tokens.dart';

/// Renders the ephemeral AI summary and its lifecycle hint as a light callout.
final class NoteDetailSummary extends StatelessWidget {
  const NoteDetailSummary({
    super.key,
    required this.copy,
    required this.hasSavedNote,
    required this.summary,
    required this.isStale,
    this.onCopy,
    this.onRegenerate,
    this.copyLabel,
    this.regenerateLabel,
  });

  final NoteDetailCopy copy;
  final bool hasSavedNote;
  final String? summary;
  final bool isStale;
  final VoidCallback? onCopy;
  final VoidCallback? onRegenerate;
  final String? copyLabel;
  final String? regenerateLabel;

  @override
  Widget build(BuildContext context) {
    final NoteFlowUiTokens tokens = NoteFlowUiTokens.of(context);
    final String? value = summary;
    if (value == null) {
      if (!hasSavedNote) {
        return const SizedBox.shrink();
      }
      return Padding(
        padding: const EdgeInsets.only(top: NoteFlowSpacing.xl),
        child: Text(
          copy.noSummary,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: tokens.textMuted),
        ),
      );
    }

    final Widget heading = Row(
      children: <Widget>[
        Icon(Icons.auto_awesome_outlined, size: 16, color: tokens.textMuted),
        const SizedBox(width: NoteFlowSpacing.sm),
        Text(
          copy.summary,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: tokens.textSecondary,
          ),
        ),
      ],
    );
    return Card(
      key: const ValueKey<String>('note-detail-summary'),
      margin: const EdgeInsets.only(top: NoteFlowSpacing.xl),
      color: tokens.subtleSurface,
      child: Padding(
        padding: const EdgeInsets.all(NoteFlowSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (isStale) ...<Widget>[
              heading,
              const SizedBox(height: NoteFlowSpacing.sm),
              Text(
                copy.summaryStale,
                style: Theme.of(context).textTheme.labelMedium
                    ?.copyWith(color: tokens.error),
              ),
            ] else
              heading,
            const SizedBox(height: NoteFlowSpacing.md),
            SelectableText(
              value,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: tokens.textPrimary, height: 1.5),
            ),
            if (onCopy != null || onRegenerate != null) ...<Widget>[
              const SizedBox(height: NoteFlowSpacing.md),
              Wrap(
                spacing: NoteFlowSpacing.sm,
                runSpacing: NoteFlowSpacing.sm,
                children: <Widget>[
                  if (onCopy != null && copyLabel != null)
                    TextButton.icon(
                      key: const ValueKey<String>('note-detail-copy-summary'),
                      onPressed: onCopy,
                      icon: const Icon(Icons.copy_outlined, size: 18),
                      label: Text(copyLabel!),
                    ),
                  if (onRegenerate != null && regenerateLabel != null)
                    FilledButton.tonalIcon(
                      key: const ValueKey<String>(
                        'note-detail-regenerate-summary',
                      ),
                      onPressed: onRegenerate,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: Text(regenerateLabel!),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
