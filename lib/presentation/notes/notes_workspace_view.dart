part of 'notes_workspace_page.dart';

extension _NotesWorkspaceView on NotesWorkspacePageState {
  Widget _buildWorkspace(BuildContext context) {
    _reportDetailVisibility();
    final NotesCopy copy = NotesCopy.of(context);
    final bool persistenceUnavailable = _error is UnsupportedError;
    final String? loadError = _error == null
        ? null
        : persistenceUnavailable
        ? copy.persistenceUnavailable
        : copy.loadError;
    final bool compact =
        MediaQuery.sizeOf(context).width <
        ResponsiveNotesWorkspace.compactBreakpoint;
    return Scaffold(
      appBar: _showDetail || widget.embeddedInWorkspace
          ? null
          : _buildWorkspaceAppBar(copy),
      body: _loading
          ? NotesWorkspaceLoadingView(copy: copy)
          : Column(
              children: <Widget>[
                if (widget.syncController != null ||
                    _application is SharingNotesController)
                  Offstage(
                    offstage: _hasEmbeddedSyncHeader,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: _application is SharingNotesController
                                ? Offstage(
                                    offstage: _showDetail,
                                    child: _sharingTabs(),
                                  )
                                : const SizedBox.shrink(),
                          ),
                          if (widget.syncController
                              case final SyncPresentationController sync)
                            SyncStatusPanel(
                              controller: sync,
                              compact: true,
                              iconOnly: true,
                            ),
                        ],
                      ),
                    ),
                  ),
                Expanded(
                  child: CallbackShortcuts(
                    bindings: {
                      const SingleActivator(LogicalKeyboardKey.escape): () =>
                          unawaited(_requestDetailClose()),
                    },
                    child: ResponsiveNotesWorkspace(
                      preferFullPage: widget.embeddedInWorkspace,
                      list: NotesListPanel(
                        readable: _readableNote,
                        pageFooter: _workspacePageFooter(),
                        onQueryChanged: supportsNotePages(_application)
                            ? _changePageQuery
                            : null,
                        labelChoices: _notePage?.labelChoices,
                        notes: _notes
                            .where((n) => (n.share != null) == _sharedOnly)
                            .toList(),
                        titleOverride: _sharedOnly
                            ? SharingCopy(context).sharedWithMe
                            : null,
                        allowNewNote: !_sharedOnly,
                        selectedNoteId: _selectedNoteId,
                        error: loadError,
                        actionBusy: _detailBusy || _pageBusy,
                        onNewNote: _startNewNote,
                        onSelectNote: _selectNote,
                        onRetry: persistenceUnavailable ? null : reload,
                      ),
                      detail: _buildDetail(
                        copy,
                        showAppBar: compact && !widget.embeddedInWorkspace,
                      ),
                      hasSelection: _showDetail,
                      onDismiss: () => unawaited(_requestDetailClose()),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  PreferredSizeWidget _buildWorkspaceAppBar(NotesCopy copy) {
    final bool expanded =
        MediaQuery.sizeOf(context).width >= 840 && widget.embeddedInWorkspace;
    return AppBar(
      title: Text(copy.notes),
      actions:
          expanded ||
              widget.onOpenSettings == null && widget.onOpenDiagnostics == null
          ? null
          : <Widget>[
              if (!expanded && widget.onOpenSettings != null) _settingsAction(),
              if (!expanded && widget.onOpenDiagnostics != null)
                TextButton(
                  key: const ValueKey<String>('open-diagnostics'),
                  onPressed: widget.onOpenDiagnostics,
                  child: Text(copy.diagnostics),
                ),
            ],
    );
  }

  Widget _buildDetail(NotesCopy copy, {required bool showAppBar}) {
    if (!_showDetail) {
      final NoteFlowUiTokens tokens = NoteFlowUiTokens.of(context);
      if (_error != null) {
        final bool persistenceUnavailable = _error is UnsupportedError;
        final String errorMessage = persistenceUnavailable
            ? copy.persistenceUnavailable
            : copy.loadError;
        return Center(
          key: const ValueKey<String>('notes-workspace-detail-error'),
          child: Semantics(
            liveRegion: true,
            container: true,
            label: errorMessage,
            child: Padding(
              padding: const EdgeInsets.all(NoteFlowSpacing.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    Icons.cloud_off_outlined,
                    size: 32,
                    color: tokens.textMuted,
                  ),
                  const SizedBox(height: NoteFlowSpacing.sm),
                  Text(
                    errorMessage,
                    key: const ValueKey<String>(
                      'notes-workspace-detail-error-message',
                    ),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: tokens.textSecondary),
                  ),
                  if (!persistenceUnavailable) ...<Widget>[
                    const SizedBox(height: NoteFlowSpacing.xs),
                    TextButton.icon(
                      key: const ValueKey<String>(
                        'notes-workspace-detail-retry',
                      ),
                      onPressed: reload,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: Text(copy.retry),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      }
      return Center(
        key: const ValueKey<String>('notes-workspace-detail-empty'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.description_outlined, size: 40, color: tokens.textMuted),
            const SizedBox(height: NoteFlowSpacing.sm),
            Text(
              copy.createFirstNote,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: tokens.textSecondary),
            ),
          ],
        ),
      );
    }
    final NoteDto? note = _selectedNote;
    return NoteDetailPage(
      key: _detailKeyFor(note?.reference ?? 'new'),
      notesController: _application,
      note: note,
      provisioningReader: widget.provisioningReader,
      onProvisioningCancel: widget.onProvisioningCancel,
      showAppBar: showAppBar,
      onEmbeddedExit: _handleDetailExit,
      onDirtyChanged: _handleDetailDirtyChanged,
      initialContentSelection: _pendingSelectionRequest,
      onNoteEdited: widget.onNoteEdited,
      onOpenNoteRag: widget.onOpenNoteRag,
      syncController: widget.syncController,
    );
  }

  Widget _settingsAction() {
    final NotesCopy copy = NotesCopy.of(context);
    return IconButton(
      key: const ValueKey<String>('open-settings'),
      tooltip: copy.appearanceAndLanguage,
      icon: const Icon(Icons.tune_outlined),
      onPressed: widget.onOpenSettings,
    );
  }
}
