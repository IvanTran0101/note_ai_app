import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../application/note_intelligence/model_provisioning/model_provisioning_boundary.dart';
import 'model_provisioning_status_panel.dart';
import 'note_detail_localizations.dart';
import 'note_detail_summary.dart';
import 'note_summary_availability.dart';
import 'note_summary_feedback.dart';
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
    this.informationalError = false,
    required this.statusMessage,
    this.showSaveState = true,
    required this.actionBusy,
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
    const double titleFontSize = 40;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        TextField(
          key: const ValueKey<String>('note-detail-title-field'),
          controller: titleController,
          focusNode: titleFocusNode,
          minLines: 1,
          maxLines: null,
          textInputAction: TextInputAction.next,
          style: titleStyle?.copyWith(
            fontSize: titleFontSize,
            fontWeight: FontWeight.w700,
            color: tokens.textPrimary,
            height: 1.2,
          ),
          decoration: InputDecoration(
            hintText: copy.titleLabel,
            hintStyle: titleStyle?.copyWith(
              fontSize: titleFontSize,
              fontWeight: FontWeight.w700,
              color: tokens.textMuted,
              height: 1.2,
            ),
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            errorBorder: InputBorder.none,
            focusedErrorBorder: InputBorder.none,
            contentPadding: EdgeInsets.fromLTRB(
              titleLeadingInset,
              NoteFlowSpacing.sm,
              0,
              NoteFlowSpacing.sm,
            ),
          ),
        ),
        const SizedBox(height: NoteFlowSpacing.sm),
        if (summaryAvailability != null)
          NoteSummaryFeedback(
            copy: copy,
            availability: summaryAvailability!,
            cloud: summaryCloud,
            isRunning: isSummarizing,
            onCancel: onCancelSummary,
          ),
        NoteDetailSummary(
          copy: copy,
          hasSavedNote: hasSavedNote,
          summary: summary,
          isStale: summaryStale,
          isSummarizing: isSummarizing,
          onCopy: onCopySummary,
          onRegenerate: onRegenerateSummary,
          copyLabel: copySummaryLabel,
          regenerateLabel: regenerateSummaryLabel,
        ),
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
                    ? NoteFlowLayout.wideWebEditorTextMaxWidthFor(
                        MediaQuery.sizeOf(context).width,
                      )
                    : NoteFlowLayout.editorTextMaxWidth,
              ),
              child: _SummaryContentMotion(
                active: animateSummary,
                controller: contentController,
                textStyle: contentStyle,
                child: TextField(
                  key: const ValueKey<String>('note-detail-content-field'),
                  controller: contentController,
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
        if (isDirty && showSaveState) ...<Widget>[
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
        if (statusMessage != null && showSaveState) ...<Widget>[
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
        if (actionBusy && !isSummarizing && showBusyIndicator) ...<Widget>[
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
      ],
    );
  }
}

/// Gives the note text a gentle breathing effect while the AI reads it.
final class _SummaryContentMotion extends StatefulWidget {
  const _SummaryContentMotion({
    required this.active,
    required this.controller,
    required this.textStyle,
    required this.child,
  });

  final bool active;
  final TextEditingController controller;
  final TextStyle textStyle;
  final Widget child;

  @override
  State<_SummaryContentMotion> createState() => _SummaryContentMotionState();
}

final class _SummaryContentMotionState extends State<_SummaryContentMotion>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotion();
  }

  @override
  void didUpdateWidget(covariant _SummaryContentMotion oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncMotion();
  }

  void _syncMotion() {
    if (widget.active && !MediaQuery.disableAnimationsOf(context)) {
      if (!_controller.isAnimating) _controller.repeat(reverse: true);
    } else {
      _controller.stop();
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active || MediaQuery.disableAnimationsOf(context)) {
      return widget.child;
    }
    final NoteFlowUiTokens tokens = NoteFlowUiTokens.of(context);
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (BuildContext context, Widget? child) {
        return Stack(
          fit: StackFit.passthrough,
          children: <Widget>[
            child!,
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: widget.controller,
              builder:
                  (BuildContext context, TextEditingValue value, Widget? _) {
                    if (value.text.isEmpty) {
                      return const SizedBox.shrink();
                    }
                    final Color baseColor =
                        widget.textStyle.color ?? tokens.textPrimary;
                    final List<TextSpan> words = RegExp(r'\S+\s*')
                        .allMatches(value.text)
                        .toList(growable: false)
                        .asMap()
                        .entries
                        .map((MapEntry<int, RegExpMatch> entry) {
                          final double phase =
                              (_controller.value + (entry.key * 0.13)) % 1;
                          final double wave = phase < 0.5
                              ? phase * 2
                              : 2 - (phase * 2);
                          final double pulse = Curves.easeInOut.transform(wave);
                          return TextSpan(
                            text: entry.value.group(0),
                            style: widget.textStyle.copyWith(
                              color: baseColor.withAlpha(
                                140 + (pulse * 115).round(),
                              ),
                            ),
                          );
                        })
                        .toList(growable: false);
                    return IgnorePointer(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: NoteFlowSpacing.sm,
                        ),
                        child: RichText(text: TextSpan(children: words)),
                      ),
                    );
                  },
            ),
          ],
        );
      },
    );
  }
}
