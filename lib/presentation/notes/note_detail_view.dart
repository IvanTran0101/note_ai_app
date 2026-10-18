part of 'note_detail_page.dart';

extension _NoteDetailView on NoteDetailPageState {
  Widget _buildDetail(BuildContext context) {
    final NoteDetailCopy copy = NoteDetailCopy.of(context);
    final String currentTitle = _titleController.text.trim();
    final String pageTitle = _note != null && !_canRead
        ? NoteSecurityCopy(context).protectedNote
        : currentTitle.isNotEmpty
        ? currentTitle
        : (_note == null ? copy.newNote : copy.editNote);
    final Widget surface = _buildSurface(copy, pageTitle);
    final Widget content = widget.onEmbeddedExit != null
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (widget.showAppBar) _buildAppBar(copy, pageTitle),
              Expanded(child: surface),
            ],
          )
        : Scaffold(
            resizeToAvoidBottomInset: !_securityBusy,
            appBar: widget.showAppBar ? _buildAppBar(copy, pageTitle) : null,
            body: surface,
          );
    return PopScope<NoteDetailRouteResult>(
      canPop:
          widget.onEmbeddedExit == null &&
          !_isDirty &&
          !_actionBusy &&
          !_didPersist,
      onPopInvokedWithResult: (bool didPop, NoteDetailRouteResult? result) {
        if (!didPop) {
          unawaited(_handleBack());
        }
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              unawaited(requestClose()),
        },
        child: content,
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(NoteDetailCopy copy, String pageTitle) {
    final VoidCallback? moreAction = _moreAction(copy);
    final List<Widget> actions = <Widget>[
      ..._contextHeaderActions(),
      if (moreAction != null)
        Builder(
          builder: (BuildContext buttonContext) => IconButton(
            key: const ValueKey<String>('note-detail-more'),
            tooltip: copy.more,
            onPressed: () =>
                unawaited(_showMoreActions(copy, anchorContext: buttonContext)),
            icon: const Icon(Icons.more_horiz),
          ),
        ),
    ];
    return AppBar(
      leading: IconButton(
        key: NoteDetailPage.backKey,
        tooltip: copy.back,
        onPressed: _actionBusy ? null : () => unawaited(_handleBack()),
        icon: const Icon(Icons.arrow_back),
      ),
      title: Text(pageTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      actions: actions.isEmpty ? null : actions,
    );
  }

  VoidCallback? _moreAction(NoteDetailCopy copy) {
    if (_note == null ||
        !_capabilities.canDelete ||
        _actionBusy ||
        _currentConflict != null) {
      return null;
    }
    return () => unawaited(_showMoreActions(copy));
  }

  ValueChanged<BuildContext>? _moreActionWithContext(NoteDetailCopy copy) {
    if (_note == null ||
        !_capabilities.canDelete ||
        _actionBusy ||
        _currentConflict != null) {
      return null;
    }
    return (BuildContext anchorContext) =>
        unawaited(_showMoreActions(copy, anchorContext: anchorContext));
  }

  Future<void> _showMoreActions(
    NoteDetailCopy copy, {
    BuildContext? anchorContext,
  }) {
    return runNoteDetailMoreActions(
      context: context,
      copy: copy,
      anchorContext: anchorContext,
      onDelete: _delete,
    );
  }

  Widget _buildSurface(NoteDetailCopy copy, String pageTitle) {
    if (_note != null && !_canRead) {
      return Align(
        alignment: Alignment.topCenter,
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: _securityPanel(),
          ),
        ),
      );
    }
    final NoteSummaryFailureCopy? summaryFailure = noteSummaryFailureCopy(
      copy: copy,
      controller: _summaryController,
      suppressed: _provisioningFailed,
      retryEnabled: _canSummarize,
    );
    final Widget editor = NoteDetailSurface(
      titleController: _titleController,
      contentController: _contentController,
      titleFocusNode: _titleFocusNode,
      contentFocusNode: _contentFocusNode,
      contentFieldContextKey: _contentFieldContextKey,
      copy: copy,
      pageTitle: pageTitle,
      showPageHeader: !widget.showAppBar,
      statusUnavailable: false,
      onBack: widget.showAppBar ? null : () => unawaited(_handleBack()),
      backTooltip: copy.back,
      backKey: NoteDetailPage.backKey,
      hasSavedNote: _note != null,
      isDirty: _isDirty,
      error: _error ?? summaryFailure?.message,
      statusMessage: _statusMessage,
      actionBusy: _actionBusy,
      readOnly: _securityBusy || _securityLoading || !_canEdit,
      attachments: _buildNoteExtras(),
      richEditorBuilder: _richEditor == null ? null : _richEditorWidget,
      headerActions: widget.showAppBar ? const [] : _contextHeaderActions(),
      syncController: widget.syncController,
      provisioningReader: widget.provisioningReader,
      onProvisioningRetry: _note == null ? null : _summarize,
      onProvisioningCancel: widget.onProvisioningCancel,
      summary: _summaryController.summary,
      summaryStale: _summaryController.isStale,
      onCopySummary: !_canExport || _summaryController.summary == null
          ? null
          : () => unawaited(_copySummary()),
      onRegenerateSummary: _canSummarize ? () => unawaited(_summarize()) : null,
      copySummaryLabel: copy.copySummary,
      regenerateSummaryLabel: copy.regenerate,
      onErrorRetry: _saveFailed
          ? () => unawaited(_save())
          : summaryFailure == null
          ? null
          : () => unawaited(_summarize()),
      errorRetryLabel: _saveFailed ? copy.retry : summaryFailure?.retryLabel,
      errorRetryEnabled: _saveFailed
          ? !_actionBusy
          : summaryFailure?.retryEnabled ?? false,
      summaryAvailability: _summaryAvailability,
      summaryCloud:
          widget.notesController.summaryConsent?.requiresCloudConsent ?? false,
      onCancelSummary: _summaryController.isRunning ? _cancelSummary : null,
      isSaving: _saving,
      isSummarizing: _summaryController.isRunning,
      showBusyIndicator: !_summaryController.isAwaitingConsent,
      canSave: false,
      canSummarize: _canSummarize,
      onSave: null,
      onSummarize: _canSummarize ? () => unawaited(_summarize()) : null,
      onMore: widget.showAppBar ? null : _moreAction(copy),
      onMoreWithContext: widget.showAppBar
          ? null
          : _moreActionWithContext(copy),
      saveLabel: copy.save,
      summarizeLabel: copy.summarize,
      moreLabel: copy.more,
      savingLabel: copy.saving,
      summarizingLabel: copy.summarizing,
    );
    final SyncConflict? conflict = _currentConflict;
    final SyncPresentationController? sync = widget.syncController;
    if (_note == null &&
        conflict == null &&
        (sync == null || widget.onEmbeddedExit != null)) {
      return editor;
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final minimumHeight = NoteFlowLayout.isShortEditor(context)
            ? 88.0
            : MediaQuery.textScalerOf(context).scale(320);
        final content = Column(
          children: <Widget>[
            if (_hasRemoteEditorChange) _remoteEditorNotice(),
            if (_note?.share != null) _sharingPanel(),
            if (sync != null && widget.onEmbeddedExit == null)
              SyncStatusPanel(controller: sync, compact: true),
            if (conflict != null) _buildConflictNotice(),
            Expanded(child: editor),
          ],
        );
        // Keyboard and accessibility text may leave less room than the fixed
        // controls need. Scroll the complete surface while keeping editor state.
        if (constraints.hasBoundedHeight &&
            constraints.maxHeight < minimumHeight) {
          return SingleChildScrollView(
            child: SizedBox(height: minimumHeight, child: content),
          );
        }
        return content;
      },
    );
  }

  Widget _buildConflictNotice() {
    final SyncCopy copy = SyncCopy.of(context);
    return Card(
      key: const ValueKey<String>('note-sync-conflict'),
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: <Widget>[
            const Icon(Icons.compare_arrows),
            const SizedBox(width: 10),
            Expanded(child: Text(copy.conflictTitle)),
            FilledButton.tonal(
              key: const ValueKey<String>('note-sync-resolve-conflict'),
              onPressed: _actionBusy || !_canEdit
                  ? null
                  : () => unawaited(_resolveConflict()),
              child: Text(copy.resolveConflict),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _contextHeaderActions() {
    final note = _note;
    if (note == null) {
      // The first local create must not add a toolbar row while the IME owns
      // the draft. Reserve only the slots the same note will use after save.
      return [
        if (widget.notesController is SharingNotesController)
          const SizedBox.square(dimension: 48),
        const SizedBox.square(dimension: 48),
        if (widget.onOpenNoteRag != null) const SizedBox.square(dimension: 48),
      ];
    }
    if (!_canRead) return const [];
    return [
      if (note.share == null &&
          _capabilities.canManage &&
          widget.notesController is SharingNotesController)
        _sharingPanel(compact: true),
      _securityPanel(),
      // Keep the horizontal slot across local edits and ACKs.
      if (widget.onOpenNoteRag != null &&
          !note.isProtected &&
          note.share == null)
        SizedBox.square(
          dimension: 48,
          child: _canOpenNoteRag ? _buildNoteRagAction(context) : null,
        ),
    ];
  }
}
