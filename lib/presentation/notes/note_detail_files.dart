part of 'note_detail_page.dart';

/// Presentation bridge only. Canonical attachment and document saves retain
/// their existing application owners and access fences.
extension _NoteDetailFiles on NoteDetailPageState {
  List<String> get _fileReferences {
    final ids = <String>[];
    void visit(DocumentBlock block) {
      if (block.attachmentId case final String id) ids.add(id);
      for (final child in block.children) {
        visit(child);
      }
    }

    for (final block in _editorDocument?.blocks ?? const <DocumentBlock>[]) {
      visit(block);
    }
    return ids;
  }

  List<String> get _legacyFileIds => {
    ...?_note?.attachments.map((file) => file.id),
    ..._inlineFiles.attachmentIds,
  }.toList();

  Widget _inlineFileBlock(String blockId, String? attachmentId) =>
      ListenableBuilder(
        listenable: _inlineFiles,
        builder: (context, _) => !_canRead || _securityLoading || _securityBusy
            ? const SizedBox.shrink()
            : _inlineFiles.buildBlock(context, blockId, attachmentId),
      );

  Future<void> _openInsertedFile(String id) async {
    if (!_canEdit || !mounted || _richEditor?.fileBlock(id) == null) return;
    final session = _securityController?.sessionGeneration;
    if (_note == null && !await _save()) return;
    if (!mounted ||
        !_canEdit ||
        session != _securityController?.sessionGeneration)
      return;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || !_canEdit || _richEditor?.fileBlock(id) == null) return;
    await _inlineFiles.openPicker(id);
  }
}
