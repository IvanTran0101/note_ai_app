import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../application/note_intelligence/model_provisioning/model_provisioning_boundary.dart';
import 'model_provisioning_status_panel.dart';
import 'note_detail_localizations.dart';
import 'note_detail_summary.dart';
import 'note_detail_utilities.dart';
import 'note_summary_availability.dart';
import 'note_summary_feedback.dart';
import 'notes_theme_tokens.dart';
import 'note_summary_content_motion.dart';

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
    this.informationalError = false,
    required this.statusMessage,
    this.showSaveState = true,
    required this.actionBusy,
    this.readOnly = false,
    this.labels,
    this.attachments,
    this.includeContent = true,
    this.includeTitle = true,
    this.includeMetadata = true,
    this.quietMetadata = false,
    this.includeFeedback = true,
    this.isSummarizing = false,
    this.showBusyIndicator = true,
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
    this.errorRetryEnabled = true,
    this.summaryAvailability,
    this.summaryCloud = false,
    this.onCancelSummary,
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
  final bool informationalError;
  final String? statusMessage;
  final bool showSaveState;
  final bool actionBusy;
  final bool readOnly;
  final Widget? labels;
  final Widget? attachments;
  final bool includeContent;
  final bool includeTitle, includeMetadata, includeFeedback;
  final bool quietMetadata;
  final bool isSummarizing;
  final bool showBusyIndicator;
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

  /// Whether the error retry action may run; false renders it disabled while a
  /// rate-limit hint still has to elapse.
  final bool errorRetryEnabled;

  /// Availability of the Summary action, or null when the host shows none.
  final NoteSummaryAvailability? summaryAvailability;

  /// Whether the active runtime is the cloud one, for unavailable copy.
  final bool summaryCloud;

  /// Cancels the in-flight generation; visible for the whole run.
  final VoidCallback? onCancelSummary;

  @override
  Widget build(BuildContext context) {
    final NoteFlowUiTokens tokens = NoteFlowUiTokens.of(context);
    final TextStyle? titleStyle = Theme.of(context).textTheme.headlineLarge;
    final TextStyle? bodyStyle = Theme.of(context).textTheme.bodyLarge;
    final bool animateSummary =
        isSummarizing && !MediaQuery.disableAnimationsOf(context);
    final TextStyle contentStyle =
        bodyStyle?.copyWith(color: tokens.textPrimary, height: 1.5) ??
        TextStyle(color: tokens.textPrimary, height: 1.5);
    final bool compactWeb =
        kIsWeb &&
        MediaQuery.sizeOf(context).width < NoteFlowLayout.compactBreakpoint;
    final double titleLeadingInset = compactWeb
        ? NoteFlowLayout.compactWebEditorTitleLeadingInset
        : 0;
    final nativePhone = NoteFlowLayout.isNativePhone(context);
    final double titleFontSize = nativePhone
        ? 34
        : NoteFlowLayout.isCompact(context)
        ? 32
        : 40;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (includeTitle)
          TextField(
            key: const ValueKey<String>('note-detail-title-field'),
            controller: titleController,
            readOnly: readOnly,
            focusNode: titleFocusNode,
            minLines: 1,
            maxLines: null,
            textInputAction: TextInputAction.next,
            style: titleStyle?.copyWith(
              fontSize: titleFontSize,
              fontWeight: FontWeight.w700,
              color: tokens.textPrimary,
              height: nativePhone ? 1.18 : 1.2,
            ),
            decoration: InputDecoration(
              hintText: copy.titleLabel,
              hintStyle: titleStyle?.copyWith(
                fontSize: titleFontSize,
                fontWeight: FontWeight.w700,
                color: tokens.textMuted,
                height: nativePhone ? 1.18 : 1.2,
              ),
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              errorBorder: InputBorder.none,
              focusedErrorBorder: InputBorder.none,
              contentPadding: EdgeInsets.fromLTRB(
                titleLeadingInset,
                nativePhone ? 4 : NoteFlowSpacing.sm,
                0,
                nativePhone ? 12 : NoteFlowSpacing.sm,
              ),
            ),
          ),
        if (includeTitle) const SizedBox(height: NoteFlowSpacing.sm),
        if (includeTitle && labels != null) ...[
          KeyedSubtree(
            key: const ValueKey('note-detail-labels-below-title'),
            child: labels!,
          ),
          const SizedBox(height: NoteFlowSpacing.sm),
        ],
        if (includeMetadata) ..._metadata(),
        if (includeContent)
          Container(
            key: contentFieldContextKey,
            child: Align(
              alignment: Alignment.topLeft,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth:
                      kIsWeb &&
                          MediaQuery.sizeOf(context).width >=
                              NoteFlowLayout.compactBreakpoint
                      ? NoteFlowLayout.webDocumentMaxWidth
                      : NoteFlowLayout.editorTextMaxWidth,
                ),
                child: NoteSummaryContentMotion(
                  active: animateSummary,
                  controller: contentController,
                  textStyle: contentStyle,
                  child: TextField(
                    key: const ValueKey<String>('note-detail-content-field'),
                    controller: contentController,
                    readOnly: readOnly,
                    focusNode: contentFocusNode,
                    minLines: 1,
                    maxLines: null,
                    keyboardType: TextInputType.multiline,
                    textCapitalization: TextCapitalization.sentences,
                    style: animateSummary
                        ? contentStyle.copyWith(color: Colors.transparent)
                        : contentStyle,
                    cursorColor: animateSummary
                        ? Colors.transparent
                        : tokens.textPrimary,
                    decoration: InputDecoration(
                      hintText: copy.contentLabel,
                      hintStyle: bodyStyle?.copyWith(color: tokens.textMuted),
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
              ),
            ),
          ),
        if (includeFeedback && isDirty && showSaveState) ...<Widget>[
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
        if (includeFeedback && error != null) ...<Widget>[
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
                border: Border.all(
                  color: informationalError ? tokens.divider : tokens.error,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(
                    informationalError
                        ? Icons.cloud_off_outlined
                        : Icons.error_outline,
                    size: 18,
                    color: informationalError ? tokens.textMuted : tokens.error,
                  ),
                  const SizedBox(width: NoteFlowSpacing.sm),
                  Expanded(
                    child: Text(
                      error!,
                      style: TextStyle(
                        color: informationalError
                            ? tokens.textSecondary
                            : tokens.error,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (onErrorRetry != null && errorRetryLabel != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: const ValueKey<String>('note-detail-error-retry'),
                onPressed: errorRetryEnabled ? onErrorRetry : null,
                child: Text(errorRetryLabel!),
              ),
            ),
        ],
        if (includeFeedback &&
            statusMessage != null &&
            showSaveState) ...<Widget>[
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
        if (includeFeedback &&
            actionBusy &&
            !isSummarizing &&
            showBusyIndicator) ...<Widget>[
          const SizedBox(height: NoteFlowSpacing.md),
          Semantics(
            liveRegion: true,
            label: copy.actionInProgress,
            child: const LinearProgressIndicator(
              key: ValueKey<String>('note-detail-progress'),
            ),
          ),
        ],
        if (includeFeedback && provisioningReader != null)
          ModelProvisioningStatusPanel(
            reader: provisioningReader!,
            onRetry: hasSavedNote ? onProvisioningRetry : null,
            onCancel: onProvisioningCancel,
          ),
      ],
    );
  }

  List<Widget> _metadata() {
    final feedback = summaryAvailability == null
        ? const SizedBox.shrink()
        : NoteSummaryFeedback(
            copy: copy,
            availability: summaryAvailability!,
            cloud: summaryCloud,
            isRunning: isSummarizing,
            onCancel: onCancelSummary,
          );
    final result = NoteDetailSummary(
      copy: copy,
      hasSavedNote: hasSavedNote,
      summary: summary,
      isStale: summaryStale,
      isSummarizing: isSummarizing,
      onCopy: onCopySummary,
      onRegenerate: onRegenerateSummary,
      copyLabel: copySummaryLabel,
      regenerateLabel: regenerateSummaryLabel,
    );
    if (!quietMetadata || !hasSavedNote) {
      return [feedback, result, ?attachments];
    }
    return [
      if (isSummarizing) feedback,
      if (summary != null) result,
      ?attachments,
      NoteDetailUtilities(
        label: copy.noteDetails,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [if (!isSummarizing) feedback],
        ),
      ),
    ];
  }
}
