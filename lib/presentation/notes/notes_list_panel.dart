import '../labels/notes_query_panel.dart';
import '../../application/labels/note_query.dart';

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
    this.queryControls,
    this.filteredEmpty,
    this.pageFooter,
    this.onQueryChanged,
    this.labelChoices,
  });

  final Widget? pageFooter;
  final void Function(String, Set<LabelSelection>)? onQueryChanged;
  final Map<LabelSelection, String>? labelChoices;
  final String? titleOverride;
  final bool allowNewNote;
  final bool Function(NoteDto)? readable;
  final bool queryEnabled;
  final Widget? queryControls;
  final Widget? filteredEmpty;
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
    final bool compact = NoteFlowLayout.isCompact(context);
    return Material(
      color: tokens.pageSurface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            compact
                ? NoteFlowLayout.compactPageLeadingInsetFor(context)
                : NoteFlowSpacing.xl,
            compact
                ? NoteFlowLayout.compactPageTopInset(context)
                : NoteFlowLayout.editorTopPadding,
            compact ? NoteFlowSpacing.lg : NoteFlowSpacing.xl,
            NoteFlowSpacing.xl,
          ),
          child: Align(
            alignment: compact ? Alignment.topLeft : Alignment.center,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: compact
                    ? NoteFlowLayout.compactPageMaxWidth
                    : NoteFlowLayout.editorMaxWidth,
              ),
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints panelBounds) {
                  final double queryMaxHeight = panelBounds.hasBoundedHeight
                      // Leave room for the scaled heading and a tappable note
                      // row; tall filter content keeps its own scroll surface.
                      ? panelBounds.maxHeight / 3
                      : double.infinity;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      LayoutBuilder(
                        builder: (BuildContext context, BoxConstraints bounds) {
                          final TextScaler textScaler = MediaQuery.textScalerOf(
                            context,
                          );
                          final bool compactAction =
                              compact ||
                              bounds.maxWidth <
                                  NoteFlowLayout.compactBreakpoint ||
                              textScaler.scale(16) > 16;
                          final Widget title = Text(
                            titleOverride ?? copy.notes,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.headlineLarge
                                ?.copyWith(
                                  fontSize: compact ? 32 : 40,
                                  height: 1.2,
                                  fontWeight: FontWeight.w700,
                                  color: tokens.textPrimary,
                                ),
                          );
                          final Widget create = FilledButton.icon(
                            key: const ValueKey<String>('new-note'),
                            onPressed: actionBusy ? null : onNewNote,
                            icon: const Icon(Icons.add, size: 20),
                            label: Text(copy.newNote),
                            style: FilledButton.styleFrom(
                              backgroundColor: tokens.link,
                              foregroundColor: Theme.of(context)
                                  .colorScheme
                                  .onPrimary,
                              minimumSize: const Size(48, 44),
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
                          if (compactAction) {
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: <Widget>[
                                Expanded(child: title),
                                if (allowNewNote)
                                  IconButton(
                                    key: const ValueKey<String>('new-note'),
                                    tooltip: copy.newNote,
                                    onPressed: actionBusy ? null : onNewNote,
                                    icon: const Icon(Icons.add),
                                  ),
                              ],
                            );
                          }
                          return Row(
                            children: <Widget>[
                              Expanded(child: title),
                              if (allowNewNote) create,
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: NoteFlowSpacing.sm),
                      if (queryControls != null)
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight: queryMaxHeight,
                          ),
                          child: SingleChildScrollView(
                            key: const ValueKey<String>(
                              'notes-query-controls-scroll',
                            ),
                            primary: false,
                            child: queryControls!,
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
                      const SizedBox(height: NoteFlowSpacing.md),
                      Expanded(
                        child:
                            filteredEmpty ??
                            (notes.isEmpty
                                ? error != null
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
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: <Widget>[
                                                      Icon(
                                                        Icons
                                                            .cloud_off_outlined,
                                                        size: 32,
                                                        color: tokens.textMuted,
                                                      ),
                                                      const SizedBox(
                                                        height:
                                                            NoteFlowSpacing.sm,
                                                      ),
                                                      Semantics(
                                                        excludeSemantics: true,
                                                        child: Text(
                                                          error!,
                                                          key:
                                                              const ValueKey<
                                                                String
                                                              >(
                                                                'notes-list-error',
                                                              ),
                                                          textAlign:
                                                              TextAlign.center,
                                                          style:
                                                              Theme.of(context)
                                                                  .textTheme
                                                                  .bodySmall
                                                                  ?.copyWith(
                                                                    color: tokens
                                                                        .textSecondary,
                                                                  ),
                                                        ),
                                                      ),
                                                      const SizedBox(
                                                        height:
                                                            NoteFlowSpacing.xs,
                                                      ),
                                                      if (onRetry != null)
                                                        TextButton.icon(
                                                          key:
                                                              const ValueKey<
                                                                String
                                                              >('retry-notes'),
                                                          onPressed: actionBusy
                                                              ? null
                                                              : onRetry,
                                                          icon: const Icon(
                                                            Icons.refresh,
                                                            size: 18,
                                                          ),
                                                          label: Text(
                                                            copy.retry,
                                                          ),
                                                        ),
                                                    ],
                                                  ),
                                                ),
                                              )
                                      : Center(
                                          key: ValueKey<String>('notes-empty'),
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: <Widget>[
                                              Icon(
                                                Icons.note_add_outlined,
                                                size: 32,
                                                color: tokens.textMuted,
                                              ),
                                              const SizedBox(
                                                height: NoteFlowSpacing.sm,
                                              ),
                                              Text(
                                                copy.noNotes,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodySmall
                                                    ?.copyWith(
                                                      color:
                                                          tokens.textSecondary,
                                                    ),
                                              ),
                                              if (allowNewNote)
                                                TextButton(
                                                  key: const ValueKey<String>(
                                                    'new-note-empty',
                                                  ),
                                                  onPressed: actionBusy
                                                      ? null
                                                      : onNewNote,
                                                  child: Text(
                                                    copy.createFirstNote,
                                                  ),
                                                ),
                                            ],
                                          ),
                                        )
                                : AnimatedNoteList(
                                    notes: notes,
                                    readable: readable,
                                    selectedNoteId: selectedNoteId,
                                    actionBusy: actionBusy,
                                    onSelectNote: onSelectNote,
                                  )),
                      ),
                      ?pageFooter,
                    ],
                  );
                },
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
