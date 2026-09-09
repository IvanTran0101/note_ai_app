import 'package:flutter/material.dart';

import '../../application/note_intelligence/model_provisioning/model_provisioning_boundary.dart';
import 'model_provisioning_status_panel.dart';
import 'notes_localizations.dart';
import 'notes_theme_tokens.dart';

/// Edits one Note projection and displays its ephemeral summary.
final class NoteEditorPanel extends StatelessWidget {
  const NoteEditorPanel({
    super.key,
    required this.titleController,
    required this.contentController,
    required this.hasSelectedNote,
    required this.actionBusy,
    required this.error,
    required this.summary,
    this.isDirty = false,
    this.summaryBusy = false,
    this.statusMessage,
    this.provisioningReader,
    this.onProvisioningRetry,
    required this.onSave,
    required this.onDelete,
    required this.onSummarize,
  });

  final TextEditingController titleController;
  final TextEditingController contentController;
  final bool hasSelectedNote;
  final bool actionBusy;
  final String? error;
  final String? summary;
  final bool isDirty;
  final bool summaryBusy;
  final String? statusMessage;
  final IModelProvisioningReader? provisioningReader;
  final VoidCallback? onProvisioningRetry;
  final VoidCallback onSave;
  final VoidCallback? onDelete;
  final VoidCallback? onSummarize;

  @override
  Widget build(BuildContext context) {
    final NotesCopy copy = NotesCopy.of(context);
    final ThemeData theme = Theme.of(context);
    final NoteFlowSemanticColors semanticColors =
        theme.extension<NoteFlowSemanticColors>() ??
        NoteFlowSemanticColors.fromColorScheme(theme.colorScheme);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(copy.editor, style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey<String>('title-field'),
              controller: titleController,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: copy.titleLabel,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey<String>('content-field'),
              controller: contentController,
              minLines: 8,
              maxLines: 16,
              keyboardType: TextInputType.multiline,
              decoration: InputDecoration(
                labelText: copy.contentLabel,
                alignLabelWithHint: true,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                FilledButton(
                  key: const ValueKey<String>('save-note'),
                  onPressed: actionBusy ? null : onSave,
                  child: Text(copy.save),
                ),
                OutlinedButton(
                  key: const ValueKey<String>('delete-note'),
                  onPressed: onDelete,
                  child: Text(copy.delete),
                ),
                OutlinedButton(
                  key: const ValueKey<String>('summarize-note'),
                  onPressed: isDirty || summaryBusy ? null : onSummarize,
                  child: Text(summaryBusy ? copy.summarizing : copy.summarize),
                ),
              ],
            ),
            if (isDirty) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                copy.unsavedChanges,
                key: ValueKey<String>('notes-dirty'),
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (actionBusy) ...<Widget>[
              const SizedBox(height: 12),
              Semantics(
                liveRegion: true,
                label: copy.actionInProgress,
                child: const LinearProgressIndicator(
                  key: ValueKey<String>('notes-action-progress'),
                ),
              ),
            ],
            if (provisioningReader != null)
              ModelProvisioningStatusPanel(
                reader: provisioningReader!,
                onRetry: onProvisioningRetry,
              ),
            if (error != null) ...<Widget>[
              const SizedBox(height: 12),
              Semantics(
                liveRegion: true,
                child: Text(
                  error!,
                  key: const ValueKey<String>('notes-error'),
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            ],
            if (statusMessage != null) ...<Widget>[
              const SizedBox(height: 12),
              Semantics(
                liveRegion: true,
                child: Text(
                  statusMessage!,
                  key: const ValueKey<String>('notes-status'),
                  style: TextStyle(color: semanticColors.success),
                ),
              ),
            ],
            if (summary != null) ...<Widget>[
              const SizedBox(height: 16),
              Card(
                key: const ValueKey<String>('summary-card'),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Text(
                        copy.summary,
                        key: ValueKey<String>('summary-heading'),
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      SelectableText(
                        summary!,
                        key: const ValueKey<String>('summary-text'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
