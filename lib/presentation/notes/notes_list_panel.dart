import '../labels/notes_query_panel.dart';

import 'package:flutter/material.dart';

import '../../application/notes/note_application.dart';
import 'notes_localizations.dart';
import 'notes_theme_tokens.dart';

import 'animated_note_list.dart';

/// Displays the saved Note projections and the list-level actions.
///
/// Rows render as Notion-style page rows: page icon, title, light preview and
/// a token-based selected background. All keys and callbacks are unchanged.
final class NotesListPanel extends StatelessWidget {
  const NotesListPanel({
    super.key,
    required this.notes,
    required this.selectedNoteId,
    required this.error,
    required this.actionBusy,
    required this.onNewNote,
    required this.onSelectNote,
    required this.onRetry,
    this.titleOverride,
    this.allowNewNote = true,
    this.readable,
    this.queryEnabled = true,
    this.layout = NoteLayoutPreference.list,
    this.onLayoutChanged,
    this.layoutBusy = false,
    this.refreshing = false,
    this.canPin,
    this.onTogglePinned,
    this.pinningNoteId,
    this.pinEnabled = true,
    this.queryControls,
    this.emptyMessage,
  });

  final String? titleOverride;
  final bool allowNewNote;
  final bool Function(NoteDto)? readable;
  final bool queryEnabled;
  final NoteLayoutPreference layout;
  final ValueChanged<NoteLayoutPreference>? onLayoutChanged;
  final bool layoutBusy;
  final bool refreshing;
  final bool Function(NoteDto)? canPin;
  final ValueChanged<NoteDto>? onTogglePinned;
  final String? pinningNoteId;
  final bool pinEnabled;
  final Widget? queryControls;
  final String? emptyMessage;
  final List<NoteDto> notes;
  final String? selectedNoteId;
  final String? error;
  final bool actionBusy;
  final VoidCallback onNewNote;
  final ValueChanged<NoteDto> onSelectNote;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    if (queryEnabled) return NotesQueryPanel(panel: this);
    final NotesCopy copy = NotesCopy.of(context);
    final NoteFlowUiTokens tokens = NoteFlowUiTokens.of(context);
    final bool compact =
        MediaQuery.sizeOf(context).width < NoteFlowLayout.compactBreakpoint;
    return Material(
      color: tokens.sidebarSurface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            compact
                ? NoteFlowLayout.compactPageLeadingInsetFor(context)
                : NoteFlowSpacing.xl,
            compact
                ? NoteFlowLayout.compactPageTopInset(context)
                : NoteFlowSpacing.xl,
            compact ? NoteFlowSpacing.lg : NoteFlowSpacing.xl,
            NoteFlowSpacing.xl,
          ),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: compact
                    ? NoteFlowLayout.editorMaxWidth
                    : NoteFlowLayout.wideWebEditorMaxWidth,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  LayoutBuilder(
                    builder:
                        (BuildContext context, BoxConstraints constraints) {
                          final narrow = constraints.maxWidth < 440;
                          final Widget title = Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                titleOverride ?? copy.notes,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineMedium
                                    ?.copyWith(
                                      fontSize: 30,
                                      height: 1.2,
                                      letterSpacing: 0,
                                      fontWeight: FontWeight.w700,
                                      color: tokens.textPrimary,
                                    ),
                              ),
                              const SizedBox(height: NoteFlowSpacing.xs),
                              Text(
                                copy.collectionCount(
                                  notes.length,
                                  notes.where((note) => note.isPinned).length,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: tokens.textSecondary,
                                      height: 1.5,
                                    ),
                              ),
                            ],
                          );
                          final Widget create = FilledButton.icon(
                            key: const ValueKey<String>('new-note'),
                            onPressed: actionBusy ? null : onNewNote,
                            icon: const Icon(Icons.add, size: 20),
                            label: Text(copy.newNote),
                            style: FilledButton.styleFrom(
                              backgroundColor: tokens.textPrimary,
                              foregroundColor: tokens.pageSurface,
                              minimumSize: const Size(48, 48),
                              visualDensity: VisualDensity.standard,
                              padding: const EdgeInsets.symmetric(
                                horizontal: NoteFlowSpacing.md,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  NoteFlowRadius.input,
                                ),
                              ),
                            ),
                          );
                          return Row(
                            children: <Widget>[
                              Expanded(child: title),
                              if (onLayoutChanged != null) ...<Widget>[
                                SegmentedButton<NoteLayoutPreference>(
                                  key: const ValueKey('notes-layout-control'),
                                  showSelectedIcon: false,
                                  segments:
                                      <ButtonSegment<NoteLayoutPreference>>[
                                        ButtonSegment(
                                          value: NoteLayoutPreference.grid,
                                          icon: const Icon(
                                            Icons.grid_view_outlined,
                                            size: 18,
                                          ),
                                          tooltip: copy.gridView,
                                        ),
                                        ButtonSegment(
                                          value: NoteLayoutPreference.list,
                                          icon: const Icon(
                                            Icons.view_list_outlined,
                                            size: 18,
                                          ),
                                          tooltip: copy.listView,
                                        ),
                                      ],
                                  selected: <NoteLayoutPreference>{layout},
                                  onSelectionChanged: layoutBusy || actionBusy
                                      ? null
                                      : (selection) =>
                                            onLayoutChanged!(selection.single),
                                  style: SegmentedButton.styleFrom(
                                    minimumSize: const Size(44, 48),
                                    visualDensity: VisualDensity.standard,
                                    padding: EdgeInsets.zero,
                                    foregroundColor: tokens.textSecondary,
                                    selectedForegroundColor: tokens.pageSurface,
                                    selectedBackgroundColor: tokens.textPrimary,
                                    side: BorderSide(color: tokens.divider),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(
                                        NoteFlowRadius.input,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: NoteFlowSpacing.sm),
                              ],
                              if (allowNewNote)
                                if (narrow)
                                  IconButton.filled(
                                    key: const ValueKey<String>('new-note'),
                                    tooltip: copy.newNote,
                                    onPressed: actionBusy ? null : onNewNote,
                                    icon: const Icon(Icons.add),
                                    style: IconButton.styleFrom(
                                      minimumSize: const Size(48, 48),
                                      visualDensity: VisualDensity.standard,
                                      backgroundColor: tokens.textPrimary,
                                      foregroundColor: tokens.pageSurface,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(
                                          NoteFlowRadius.input,
                                        ),
                                      ),
                                    ),
                                  )
                                else
                                  create,
                            ],
                          );
                        },
                  ),
                  const SizedBox(height: NoteFlowSpacing.xl),
                  if (queryControls != null) ...[
                    queryControls!,
                    const SizedBox(height: NoteFlowSpacing.md),
                  ],
                  Divider(height: 1, color: tokens.divider),
                  if (refreshing || layoutBusy)
                    Semantics(
                      key: const ValueKey('notes-collection-progress'),
                      liveRegion: true,
                      label: refreshing ? copy.loadingNotes : copy.savingView,
                      child: LinearProgressIndicator(
                        minHeight: 2,
                        value: MediaQuery.disableAnimationsOf(context)
                            ? 0.5
                            : null,
                      ),
                    ),
                  if (error != null && notes.isNotEmpty) ...<Widget>[
                    const SizedBox(height: NoteFlowSpacing.md),
                    Text(
                      error!,
                      key: const ValueKey<String>('notes-list-error'),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: tokens.error),
                    ),
                    if (onRetry != null)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          key: const ValueKey<String>('retry-notes'),
                          onPressed: actionBusy ? null : onRetry,
                          child: Text(copy.retry),
                        ),
                      ),
                  ],
                  const SizedBox(height: NoteFlowSpacing.lg),
                  Expanded(
                    child: notes.isEmpty
                        ? emptyMessage != null
                              ? Align(
                                  alignment: Alignment.topLeft,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: NoteFlowSpacing.xxl,
                                    ),
                                    child: Text(
                                      emptyMessage!,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            color: tokens.textSecondary,
                                          ),
                                    ),
                                  ),
                                )
                              : error != null
                              ? compact
                                    ? _buildCompactErrorState(
                                        context,
                                        copy,
                                        tokens,
                                      )
                                    : Center(
                                        key: const ValueKey<String>(
                                          'notes-load-error-state',
                                        ),
                                        child: Semantics(
                                          liveRegion: true,
                                          container: true,
                                          label: error,
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: <Widget>[
                                              Icon(
                                                Icons.cloud_off_outlined,
                                                size: 32,
                                                color: tokens.textMuted,
                                              ),
                                              const SizedBox(
                                                height: NoteFlowSpacing.sm,
                                              ),
                                              Semantics(
                                                excludeSemantics: true,
                                                child: Text(
                                                  error!,
                                                  key: const ValueKey<String>(
                                                    'notes-list-error',
                                                  ),
                                                  textAlign: TextAlign.center,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .bodySmall
                                                      ?.copyWith(
                                                        color: tokens
                                                            .textSecondary,
                                                      ),
                                                ),
                                              ),
                                              const SizedBox(
                                                height: NoteFlowSpacing.xs,
                                              ),
                                              if (onRetry != null)
                                                TextButton.icon(
                                                  key: const ValueKey<String>(
                                                    'retry-notes',
                                                  ),
                                                  onPressed: actionBusy
                                                      ? null
                                                      : onRetry,
                                                  icon: const Icon(
                                                    Icons.refresh,
                                                    size: 18,
                                                  ),
                                                  label: Text(copy.retry),
                                                ),
                                            ],
                                          ),
                                        ),
                                      )
                              : Align(
                                  key: ValueKey<String>('notes-empty'),
                                  alignment: Alignment.topLeft,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: NoteFlowSpacing.xxxl,
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: <Widget>[
                                        Icon(
                                          Icons.note_add_outlined,
                                          size: 40,
                                          color: tokens.textMuted,
                                        ),
                                        const SizedBox(
                                          height: NoteFlowSpacing.sm,
                                        ),
                                        Text(
                                          copy.noNotes,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleLarge
                                              ?.copyWith(
                                                color: tokens.textPrimary,
                                                fontWeight: FontWeight.w600,
                                              ),
                                        ),
                                        if (allowNewNote)
                                          TextButton.icon(
                                            key: const ValueKey<String>(
                                              'new-note-empty',
                                            ),
                                            onPressed: actionBusy
                                                ? null
                                                : onNewNote,
                                            icon: const Icon(
                                              Icons.add,
                                              size: 18,
                                            ),
                                            label: Text(copy.createFirstNote),
                                          ),
                                      ],
                                    ),
                                  ),
                                )
                        : AnimatedNoteList(
                            notes: notes,
                            layout: layout,
                            canPin: canPin,
                            onTogglePinned: onTogglePinned,
                            pinningNoteId: pinningNoteId,
                            pinEnabled: pinEnabled,
                            readable: readable,
                            selectedNoteId: selectedNoteId,
                            actionBusy: actionBusy,
                            onSelectNote: onSelectNote,
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCompactErrorState(
    BuildContext context,
    NotesCopy copy,
    NoteFlowUiTokens tokens,
  ) {
    return Align(
      alignment: Alignment.topCenter,
      child: Semantics(
        key: const ValueKey<String>('notes-load-error-state'),
        liveRegion: true,
        container: true,
        label: error,
        child: Container(
          key: const ValueKey<String>('notes-load-error-card'),
          width: double.infinity,
          padding: const EdgeInsets.all(NoteFlowSpacing.md),
          decoration: BoxDecoration(
            color: tokens.subtleSurface,
            border: Border.all(color: tokens.divider),
            borderRadius: BorderRadius.circular(NoteFlowRadius.card),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(
                      Icons.cloud_off_outlined,
                      size: 20,
                      color: tokens.textMuted,
                    ),
                  ),
                  const SizedBox(width: NoteFlowSpacing.sm),
                  Expanded(
                    child: Semantics(
                      excludeSemantics: true,
                      child: Text(
                        error!,
                        key: const ValueKey<String>('notes-list-error'),
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: tokens.textSecondary),
                      ),
                    ),
                  ),
                ],
              ),
              if (onRetry != null) ...<Widget>[
                const SizedBox(height: NoteFlowSpacing.xs),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: const ValueKey<String>('retry-notes'),
                    onPressed: actionBusy ? null : onRetry,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: Text(copy.retry),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
