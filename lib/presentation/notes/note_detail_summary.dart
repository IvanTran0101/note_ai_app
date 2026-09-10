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
  });

  final NoteDetailCopy copy;
  final bool hasSavedNote;
  final String? summary;
  final bool isStale;

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
          ],
        ),
      ),
    );
  }
}
