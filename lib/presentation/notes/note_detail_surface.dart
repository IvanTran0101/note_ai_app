import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../../application/note_intelligence/model_provisioning/model_provisioning_boundary.dart';
import '../common/note_flow_primitives.dart';
import 'note_detail_action_bar.dart';
import 'note_detail_editor_form.dart';
import 'note_detail_localizations.dart';
import 'note_summary_availability.dart';
import 'notes_theme_tokens.dart';
import 'note_rich_text.dart';

/// Pure layout surface for the Note Detail editor.
///
/// This widget creates no [Scaffold]: the host page owns the app bar,
/// navigation, and route contract, while [NoteDetailSurface] only arranges the
/// scrollable [NoteDetailEditorForm] above the persistent
/// [NoteDetailActionBar]. Keeping the two pieces in one surface lets a host
/// embed the editor in either a full page or a responsive shell without
/// duplicating layout.
///
/// All editor state is owned by the caller and forwarded verbatim, so the
/// surface stays presentation-only and independently testable.
final class NoteDetailSurface extends StatelessWidget {
  const NoteDetailSurface({
    super.key,
    required this.titleController,
    required this.contentController,
    this.titleFocusNode,
    required this.contentFocusNode,
    required this.contentFieldContextKey,
    required this.copy,
    required this.pageTitle,
    required this.showPageHeader,
    this.statusUnavailable = false,
    this.onBack,
    this.backTooltip,
    this.backKey,
    required this.hasSavedNote,
    required this.isDirty,
    required this.error,
    required this.statusMessage,
    required this.actionBusy,
    this.readOnly = false,
    this.attachments,
    this.attachmentAction,
    this.attachmentTray,
    this.editorIdentity,
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
    required this.isSaving,
    required this.isSummarizing,
    this.showBusyIndicator = true,
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
  });

  final TextEditingController titleController;
  final TextEditingController contentController;
  final FocusNode? titleFocusNode;
  final FocusNode contentFocusNode;
  final GlobalKey contentFieldContextKey;
  final NoteDetailCopy copy;
  final String pageTitle;
  final bool showPageHeader;
  final bool statusUnavailable;
  final VoidCallback? onBack;
  final String? backTooltip;
  final Key? backKey;
  final bool hasSavedNote;
  final bool isDirty;
  final String? error;
  final String? statusMessage;
  final bool actionBusy;
  final bool readOnly;
  final Widget? attachments;
  final Widget? attachmentAction;
  final Widget? attachmentTray;
  final Object? editorIdentity;
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

  /// Whether the error retry action may run right now.
  final bool errorRetryEnabled;

  /// Availability of the Summary action, or null when the host shows none.
  final NoteSummaryAvailability? summaryAvailability;

  /// Whether the active runtime is the cloud one, for unavailable copy.
  final bool summaryCloud;

  /// Cancels the in-flight generation; visible for the whole run.
  final VoidCallback? onCancelSummary;

  final bool isSaving;
  final bool isSummarizing;
  final bool showBusyIndicator;
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

  static const Key scrollKey = ValueKey<String>('note-detail-scroll');

  @override
  Widget build(BuildContext context) {
    final bool compact =
        MediaQuery.sizeOf(context).width < NoteFlowLayout.compactBreakpoint;
    final double editorMaxWidth = compact
        ? NoteFlowLayout.editorMaxWidth
        : kIsWeb
        ? NoteFlowLayout.wideWebEditorMaxWidthFor(
            MediaQuery.sizeOf(context).width,
          )
        : NoteFlowLayout.editorMaxWidth;
    final double editorTopPadding = NoteFlowSpacing.xl;
    final String pageStatus = isSaving
        ? savingLabel
        : isSummarizing
        ? summarizingLabel
        : statusUnavailable
        ? copy.savingUnavailable
        : error ??
              (isDirty
                  ? copy.autoSavePending
                  : statusMessage ??
                        (hasSavedNote ? copy.saved : copy.autoSaveHint));
    final Widget actionBar = NoteDetailActionBar(
      isSaving: isSaving,
      isSummarizing: isSummarizing,
      canSave: canSave,
      canSummarize: canSummarize,
      onSave: onSave,
      onSummarize: onSummarize,
      onMore: onMore,
      onMoreWithContext: onMoreWithContext,
      saveLabel: saveLabel,
      summarizeLabel: summarizeLabel,
      moreLabel: moreLabel,
      savingLabel: savingLabel,
      summarizingLabel: summarizingLabel,
      summarizeTooltip: hasSavedNote ? null : copy.saveBeforeSummary,
      iconOnly: showPageHeader,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final tray = attachmentTray == null
            ? null
            : AnimatedSize(
                duration: NoteFlowMotion.duration(context),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: constraints.maxHeight * 0.35,
                  ),
                  child: attachmentTray,
                ),
              );
        return NoteRichTextScope(
          key: ValueKey(editorIdentity),
          controller: contentController,
          focusNode: contentFocusNode,
          readOnly: readOnly,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (showPageHeader)
                NoteFlowPageHeader(
                  breadcrumb: copy.pageBreadcrumb(pageTitle),
                  statusLabel: pageStatus,
                  statusBusy: isSaving || isSummarizing,
                  statusUnavailable: statusUnavailable,
                  statusDirty: isDirty,
                  statusError: error != null,
                  statusDraft: !hasSavedNote && !isDirty,
                  onBack: onBack,
                  backTooltip: backTooltip,
                  backKey: backKey,
                  actions: <Widget>[actionBar],
                ),
              if (!compact) NoteTextToolbar(attachmentAction: attachmentAction),
              if (!compact) ?tray,
              Expanded(
                child: SingleChildScrollView(
                  key: scrollKey,
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.fromLTRB(
                    compact
                        ? NoteFlowLayout.compactPageLeadingInsetFor(context)
                        : NoteFlowSpacing.xxl,
                    editorTopPadding,
                    compact ? NoteFlowSpacing.lg : NoteFlowSpacing.xxl,
                    NoteFlowSpacing.xl,
                  ),
                  child: Align(
                    alignment: compact
                        ? Alignment.topLeft
                        : Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: editorMaxWidth),
                      child: NoteDetailEditorForm(
                        titleController: titleController,
                        contentController: contentController,
                        titleFocusNode: titleFocusNode,
                        contentFocusNode: contentFocusNode,
                        contentFieldContextKey: contentFieldContextKey,
                        copy: copy,
                        hasSavedNote: hasSavedNote,
                        isDirty: isDirty,
                        error: error,
                        informationalError:
                            error == copy.persistenceUnavailable,
                        statusMessage: statusMessage,
                        showSaveState: !showPageHeader,
                        actionBusy: actionBusy,
                        readOnly: readOnly,
                        attachments: attachments,
                        isSummarizing: isSummarizing,
                        showBusyIndicator: showBusyIndicator,
                        provisioningReader: provisioningReader,
                        onProvisioningRetry: onProvisioningRetry,
                        onProvisioningCancel: onProvisioningCancel,
                        summary: summary,
                        summaryStale: summaryStale,
                        onCopySummary: onCopySummary,
                        onRegenerateSummary: onRegenerateSummary,
                        copySummaryLabel: copySummaryLabel,
                        regenerateSummaryLabel: regenerateSummaryLabel,
                        onErrorRetry: onErrorRetry,
                        errorRetryLabel: errorRetryLabel,
                        errorRetryEnabled: errorRetryEnabled,
                        summaryAvailability: summaryAvailability,
                        summaryCloud: summaryCloud,
                        onCancelSummary: onCancelSummary,
                      ),
                    ),
                  ),
                ),
              ),
              if (compact) ?tray,
              if (compact)
                SafeArea(
                  top: false,
                  child: NoteTextToolbar(attachmentAction: attachmentAction),
                ),
              if (!showPageHeader) actionBar,
            ],
          ),
        );
      },
    );
  }
}
