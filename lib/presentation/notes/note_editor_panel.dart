import 'package:flutter/material.dart';

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
  final VoidCallback onSave;
  final VoidCallback? onDelete;
  final VoidCallback? onSummarize;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Text(
              'Note editor',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey<String>('title-field'),
              controller: titleController,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Title',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey<String>('content-field'),
              controller: contentController,
              minLines: 8,
              maxLines: 16,
              keyboardType: TextInputType.multiline,
              decoration: const InputDecoration(
                labelText: 'Content',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
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
                  child: const Text('Save note'),
                ),
                OutlinedButton(
                  key: const ValueKey<String>('delete-note'),
                  onPressed: onDelete,
                  child: const Text('Delete note'),
                ),
                OutlinedButton(
                  key: const ValueKey<String>('summarize-note'),
                  onPressed: onSummarize,
                  child: const Text('Summarize note'),
                ),
              ],
            ),
            if (hasSelectedNote) ...<Widget>[
              const SizedBox(height: 8),
              const Text(
                'Save changes before summarizing.',
                style: TextStyle(fontSize: 12),
              ),
            ],
            if (actionBusy) ...<Widget>[
              const SizedBox(height: 12),
              const LinearProgressIndicator(
                key: ValueKey<String>('notes-action-progress'),
              ),
            ],
            if (error != null) ...<Widget>[
              const SizedBox(height: 12),
              Text(
                error!,
                key: const ValueKey<String>('notes-error'),
                style: TextStyle(color: Colors.red),
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
                      const Text(
                        'Summary',
                        style: TextStyle(fontWeight: FontWeight.w600),
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
