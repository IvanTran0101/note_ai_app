import 'package:flutter/material.dart';

import '../../application/note_intelligence/model_provisioning/model_provisioning_boundary.dart';
import 'model_provisioning_status_panel.dart';
import 'note_detail_localizations.dart';
import 'note_detail_summary.dart';
import 'notes_theme_tokens.dart';

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
    this.titleFocusNode,
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
  final FocusNode? titleFocusNode;
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
    final NoteFlowUiTokens tokens = NoteFlowUiTokens.of(context);
    final TextStyle? titleStyle = Theme.of(context).textTheme.headlineMedium;
    final TextStyle? bodyStyle = Theme.of(context).textTheme.bodyLarge;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        TextField(
          key: const ValueKey<String>('note-detail-title-field'),
          controller: titleController,
          focusNode: titleFocusNode,
          textInputAction: TextInputAction.next,
          style: titleStyle?.copyWith(
            fontWeight: FontWeight.w700,
            color: tokens.textPrimary,
            height: 1.2,
          ),
          decoration: InputDecoration(
            labelText: copy.titleLabel,
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            errorBorder: InputBorder.none,
            focusedErrorBorder: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(
              vertical: NoteFlowSpacing.sm,
            ),
          ),
        ),
        const SizedBox(height: NoteFlowSpacing.sm),
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
            style: bodyStyle?.copyWith(color: tokens.textPrimary, height: 1.5),
            decoration: InputDecoration(
              labelText: copy.contentLabel,
              alignLabelWithHint: true,
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              errorBorder: InputBorder.none,
              focusedErrorBorder: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                vertical: NoteFlowSpacing.sm,
              ),
            ),
          ),
        ),
        if (isDirty) ...<Widget>[
          const SizedBox(height: NoteFlowSpacing.md),
          Semantics(
            liveRegion: true,
            label: copy.unsavedChanges,
            child: Row(
              key: const ValueKey<String>('note-detail-dirty'),
              children: <Widget>[
                Icon(Icons.edit_outlined, size: 16, color: tokens.textMuted),
                const SizedBox(width: NoteFlowSpacing.sm),
                Expanded(
                  child: Text(
                    copy.unsavedChanges,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: tokens.textMuted),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (error != null) ...<Widget>[
          const SizedBox(height: NoteFlowSpacing.md),
          Semantics(
            liveRegion: true,
            label: error,
            child: Container(
              key: const ValueKey<String>('note-detail-error'),
              padding: const EdgeInsets.all(NoteFlowSpacing.md),
              decoration: BoxDecoration(
                color: tokens.subtleSurface,
                borderRadius: BorderRadius.circular(NoteFlowRadius.card),
                border: Border.all(color: tokens.error),
              ),
              child: Text(error!, style: TextStyle(color: tokens.error)),
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
          const SizedBox(height: NoteFlowSpacing.md),
          Semantics(
            liveRegion: true,
            label: statusMessage,
            child: Row(
              key: const ValueKey<String>('note-detail-status'),
              children: <Widget>[
                Icon(Icons.check_circle_outline, size: 16, color: tokens.link),
                const SizedBox(width: NoteFlowSpacing.sm),
                Expanded(
                  child: Text(
                    statusMessage!,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: tokens.textSecondary),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (actionBusy) ...<Widget>[
          const SizedBox(height: NoteFlowSpacing.md),
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
