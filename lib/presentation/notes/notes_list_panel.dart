import 'package:flutter/material.dart';

import '../../application/notes/note_application.dart';
import 'notes_localizations.dart';
import 'notes_theme_tokens.dart';

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
  });

  final List<NoteDto> notes;
  final String? selectedNoteId;
  final String? error;
  final bool actionBusy;
  final VoidCallback onNewNote;
  final ValueChanged<NoteDto> onSelectNote;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final NotesCopy copy = NotesCopy.of(context);
    final NoteFlowUiTokens tokens = NoteFlowUiTokens.of(context);
    final bool compact =
        MediaQuery.sizeOf(context).width < NoteFlowLayout.compactBreakpoint;
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  LayoutBuilder(
                    builder:
                        (BuildContext context, BoxConstraints constraints) {
                          final Widget title = Text(
                            copy.notes,
                            style: Theme.of(context).textTheme.headlineLarge
                                ?.copyWith(
                                  fontSize: 40,
                                  height: 1.2,
                                  fontWeight: FontWeight.w700,
                                  color: tokens.textPrimary,
                                ),
                          );
                          final Widget create = TextButton.icon(
                            key: const ValueKey<String>('new-note'),
                            onPressed: actionBusy ? null : onNewNote,
                            icon: const Icon(Icons.add, size: 20),
                            label: Text(copy.newNote),
                            style: TextButton.styleFrom(
                              foregroundColor: tokens.textSecondary,
                              padding: const EdgeInsets.symmetric(
                                horizontal: NoteFlowSpacing.sm,
                              ),
                            ),
                          );
                          if (constraints.maxWidth < 420) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: <Widget>[
                                title,
                                const SizedBox(height: NoteFlowSpacing.sm),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: create,
                                ),
                              ],
                            );
                          }
                          return Row(
                            children: <Widget>[
                              Expanded(child: title),
                              create,
                            ],
                          );
                        },
                  ),
                  if (error != null && notes.isNotEmpty) ...<Widget>[
                    const SizedBox(height: NoteFlowSpacing.sm),
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
                  const SizedBox(height: NoteFlowSpacing.sm),
                  Expanded(
                    child: notes.isEmpty
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
                                              Text(
                                                error!,
                                                key: const ValueKey<String>(
                                                  'notes-list-error',
                                                ),
                                                textAlign: TextAlign.center,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodySmall
                                                    ?.copyWith(
                                                      color:
                                                          tokens.textSecondary,
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
                                              color: tokens.textSecondary,
                                            ),
                                      ),
                                      TextButton(
                                        key: const ValueKey<String>(
                                          'new-note-empty',
                                        ),
                                        onPressed: actionBusy
                                            ? null
                                            : onNewNote,
                                        child: Text(copy.createFirstNote),
                                      ),
                                    ],
                                  ),
                                )
                        : ListView.separated(
                            itemCount: notes.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: NoteFlowSpacing.xs),
                            itemBuilder: (BuildContext context, int index) {
                              final NoteDto note = notes[index];
                              final bool selected = note.id == selectedNoteId;
                              return Semantics(
                                selected: selected,
                                button: true,
                                label:
                                    '${note.title.trim().isEmpty ? copy.untitled : note.title}. ${_preview(note.content, copy)}',
                                child: ListTile(
                                  key: ValueKey<String>('note-${note.id}'),
                                  selected: selected,
                                  selectedTileColor: tokens.selectedSurface,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(
                                      NoteFlowRadius.row,
                                    ),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: NoteFlowSpacing.md,
                                    vertical: 2,
                                  ),
                                  leading: Icon(
                                    Icons.description_outlined,
                                    size: 20,
                                    color: selected
                                        ? tokens.textPrimary
                                        : tokens.textMuted,
                                  ),
                                  title: Text(
                                    note.title.trim().isEmpty
                                        ? copy.untitled
                                        : note.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(
                                          fontWeight: FontWeight.w600,
                                          color: tokens.textPrimary,
                                        ),
                                  ),
                                  subtitle: Text(
                                    _preview(note.content, copy),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(color: tokens.textMuted),
                                  ),
                                  onTap: actionBusy
                                      ? null
                                      : () => onSelectNote(note),
                                ),
                              );
                            },
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

  String _preview(String content, NotesCopy copy) {
    final String normalized = content.replaceAll(RegExp(r'\s+'), ' ').trim();
    return normalized.isEmpty ? copy.noContent : normalized;
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
                    child: Text(
                      error!,
                      key: const ValueKey<String>('notes-list-error'),
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: tokens.textSecondary),
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
