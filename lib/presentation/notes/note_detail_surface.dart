import 'package:flutter/material.dart';

import '../../application/note_intelligence/model_provisioning/model_provisioning_boundary.dart';
import 'note_detail_action_bar.dart';
import 'note_detail_editor_form.dart';
import 'note_detail_localizations.dart';

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
    required this.isSaving,
    required this.isSummarizing,
    required this.canSave,
    required this.canSummarize,
    required this.onSave,
    required this.onSummarize,
    required this.onMore,
    required this.saveLabel,
    required this.summarizeLabel,
    required this.moreLabel,
    required this.savingLabel,
    required this.summarizingLabel,
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

  final bool isSaving;
  final bool isSummarizing;
  final bool canSave;
  final bool canSummarize;
  final VoidCallback? onSave;
  final VoidCallback? onSummarize;
  final VoidCallback? onMore;
  final String saveLabel;
  final String summarizeLabel;
  final String moreLabel;
  final String savingLabel;
  final String summarizingLabel;

  static const Key scrollKey = ValueKey<String>('note-detail-scroll');

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(
          child: SingleChildScrollView(
            key: scrollKey,
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: NoteDetailEditorForm(
                  titleController: titleController,
                  contentController: contentController,
                  contentFocusNode: contentFocusNode,
                  contentFieldContextKey: contentFieldContextKey,
                  copy: copy,
                  hasSavedNote: hasSavedNote,
                  isDirty: isDirty,
                  error: error,
                  statusMessage: statusMessage,
                  actionBusy: actionBusy,
                  provisioningReader: provisioningReader,
                  onProvisioningRetry: onProvisioningRetry,
                  onProvisioningCancel: onProvisioningCancel,
                  summary: summary,
                  summaryStale: summaryStale,
                ),
              ),
            ),
          ),
        ),
        NoteDetailActionBar(
          isSaving: isSaving,
          isSummarizing: isSummarizing,
          canSave: canSave,
          canSummarize: canSummarize,
          onSave: onSave,
          onSummarize: onSummarize,
          onMore: onMore,
          saveLabel: saveLabel,
          summarizeLabel: summarizeLabel,
          moreLabel: moreLabel,
          savingLabel: savingLabel,
          summarizingLabel: summarizingLabel,
        ),
      ],
    );
  }
}
