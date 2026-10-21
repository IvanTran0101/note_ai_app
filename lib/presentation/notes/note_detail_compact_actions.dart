part of 'note_detail_page.dart';

/// Presentation of existing secondary actions in the phone's More sheet.
/// The existing security, summary and RAG handlers retain their state/guards.
extension _NoteDetailCompactActions on NoteDetailPageState {
  List<Widget> _compactMoreActions(
    BuildContext menuContext,
    NoteDetailCopy copy,
  ) {
    void closeMenu() => Navigator.of(menuContext).pop();
    final note = _note;
    return [
      if (note != null && _canRead)
        _securityPanel(menuItem: true, onBeforeAction: closeMenu),
      if (note != null &&
          !note.isProtected &&
          note.share == null &&
          widget.onOpenNoteRag != null)
        _buildNoteRagAction(context, menuItem: true, onBeforeAction: closeMenu),
      NoteFlowMenuItem(
        key: const ValueKey<String>('note-detail-summarize'),
        label: _summaryController.isRunning ? copy.summarizing : copy.summarize,
        icon: Icons.auto_awesome_outlined,
        onTap: _canSummarize && !_actionBusy
            ? () {
                closeMenu();
                unawaited(_summarize());
              }
            : null,
      ),
    ];
  }
}
