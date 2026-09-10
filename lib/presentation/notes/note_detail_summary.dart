import 'package:flutter/material.dart';

import 'note_detail_localizations.dart';

/// Renders the ephemeral AI summary and its lifecycle hint.
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
    final String? value = summary;
    if (value == null) {
      return Padding(
        padding: const EdgeInsets.only(top: 20),
        child: Text(
          hasSavedNote ? copy.noSummary : copy.saveBeforeSummary,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      );
    }

    final Widget heading = Text(
      copy.summary,
      style: Theme.of(context).textTheme.titleMedium,
    );
    return Card(
      key: const ValueKey<String>('note-detail-summary'),
      margin: const EdgeInsets.only(top: 20),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (isStale) ...<Widget>[
              heading,
              const SizedBox(height: 6),
              Text(
                copy.summaryStale,
                style: Theme.of(context).textTheme.labelMedium
                    ?.copyWith(color: Theme.of(context).colorScheme.error),
              ),
            ] else
              heading,
            const SizedBox(height: 10),
            SelectableText(value),
            if (onCopy != null || onRegenerate != null) ...<Widget>[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  if (onCopy != null && copyLabel != null)
                    TextButton.icon(
                      key: const ValueKey<String>('note-detail-copy-summary'),
                      onPressed: onCopy,
                      icon: const Icon(Icons.copy_outlined),
                      label: Text(copyLabel!),
                    ),
                  if (onRegenerate != null && regenerateLabel != null)
                    FilledButton.tonalIcon(
                      key: const ValueKey<String>(
                        'note-detail-regenerate-summary',
                      ),
                      onPressed: onRegenerate,
                      icon: const Icon(Icons.refresh),
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
