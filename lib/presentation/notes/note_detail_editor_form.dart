import 'package:flutter/material.dart';

import '../../application/note_intelligence/model_provisioning/model_provisioning_boundary.dart';
import 'model_provisioning_status_panel.dart';
import 'note_detail_localizations.dart';
import 'note_detail_summary.dart';

/// Scrollable editor content for [NoteDetailPage].
///
/// This widget is deliberately stateless: the page owns the editor lifecycle,
/// while this component owns only the mobile-friendly field and feedback
/// layout.
final class NoteDetailEditorForm extends StatelessWidget {
  const NoteDetailEditorForm({
    super.key,
    required this.titleController,
    required this.contentController,
    required this.contentFocusNode,
    required this.contentFieldContextKey,
    required this.copy,
    required this.hasSavedNote,
    required this.isDirty,
    required this.error,
    required this.statusMessage,
    required this.actionBusy,
    required this.provisioningReader,
    required this.onProvisioningRetry,
    required this.onProvisioningCancel,
    required this.summary,
    required this.summaryStale,
    this.onCopySummary,
    this.onRegenerateSummary,
    this.copySummaryLabel,
    this.regenerateSummaryLabel,
    this.onErrorRetry,
    this.errorRetryLabel,
  });

  final TextEditingController titleController;
  final TextEditingController contentController;
  final FocusNode contentFocusNode;
  final GlobalKey contentFieldContextKey;
  final NoteDetailCopy copy;
  final bool hasSavedNote;
  final bool isDirty;
  final String? error;
  final String? statusMessage;
  final bool actionBusy;
  final IModelProvisioningReader? provisioningReader;
  final VoidCallback? onProvisioningRetry;
  final VoidCallback? onProvisioningCancel;
  final String? summary;
  final bool summaryStale;
  final VoidCallback? onCopySummary;
  final VoidCallback? onRegenerateSummary;
  final String? copySummaryLabel;
  final String? regenerateSummaryLabel;
  final VoidCallback? onErrorRetry;
  final String? errorRetryLabel;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        TextField(
          key: const ValueKey<String>('note-detail-title-field'),
          controller: titleController,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(labelText: copy.titleLabel),
        ),
        const SizedBox(height: 16),
        Container(
          key: contentFieldContextKey,
          child: TextField(
            key: const ValueKey<String>('note-detail-content-field'),
            controller: contentController,
            focusNode: contentFocusNode,
            minLines: 10,
            maxLines: null,
            keyboardType: TextInputType.multiline,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: copy.contentLabel,
              alignLabelWithHint: true,
            ),
          ),
        ),
        if (isDirty) ...<Widget>[
          const SizedBox(height: 12),
          Semantics(
            liveRegion: true,
            label: copy.unsavedChanges,
            child: Text(
              copy.unsavedChanges,
              key: const ValueKey<String>('note-detail-dirty'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
        if (error != null) ...<Widget>[
          const SizedBox(height: 12),
          Semantics(
            liveRegion: true,
            label: error,
            child: Text(
              error!,
              key: const ValueKey<String>('note-detail-error'),
              style: TextStyle(color: colors.error),
            ),
          ),
          if (onErrorRetry != null && errorRetryLabel != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: const ValueKey<String>('note-detail-error-retry'),
                onPressed: onErrorRetry,
                child: Text(errorRetryLabel!),
              ),
            ),
        ],
        if (statusMessage != null) ...<Widget>[
          const SizedBox(height: 12),
          Semantics(
            liveRegion: true,
            label: statusMessage,
            child: Text(
              statusMessage!,
              key: const ValueKey<String>('note-detail-status'),
              style: TextStyle(color: colors.primary),
            ),
          ),
        ],
        if (actionBusy) ...<Widget>[
          const SizedBox(height: 12),
          Semantics(
            liveRegion: true,
            label: copy.actionInProgress,
            child: const LinearProgressIndicator(
              key: ValueKey<String>('note-detail-progress'),
            ),
          ),
        ],
        if (provisioningReader != null)
          ModelProvisioningStatusPanel(
            reader: provisioningReader!,
            onRetry: hasSavedNote ? onProvisioningRetry : null,
            onCancel: onProvisioningCancel,
          ),
        NoteDetailSummary(
          copy: copy,
          hasSavedNote: hasSavedNote,
          summary: summary,
          isStale: summaryStale,
          onCopy: onCopySummary,
          onRegenerate: onRegenerateSummary,
          copyLabel: copySummaryLabel,
          regenerateLabel: regenerateSummaryLabel,
        ),
      ],
    );
  }
}
