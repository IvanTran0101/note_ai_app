import '../labels/note_label_chips.dart';
import 'note_security_localizations.dart';

import 'package:flutter/material.dart';

import '../../application/notes/note_application.dart';
import 'notes_localizations.dart';
import 'notes_theme_tokens.dart';
import 'sharing_localizations.dart';

/// Animates projection changes only; mutations still belong to the controller.
final class AnimatedNoteList extends StatefulWidget {
  const AnimatedNoteList({
    super.key,
    required this.notes,
    required this.selectedNoteId,
    required this.actionBusy,
    required this.onSelectNote,
    this.readable,
  });

  final List<NoteDto> notes;
  final bool Function(NoteDto)? readable;
  final String? selectedNoteId;
  final bool actionBusy;
  final ValueChanged<NoteDto> onSelectNote;

  @override
  State<AnimatedNoteList> createState() => _AnimatedNoteListState();
}

final class _AnimatedNoteListState extends State<AnimatedNoteList> {
  final GlobalKey<AnimatedListState> _listKey = GlobalKey<AnimatedListState>();
  late final List<NoteDto> _rows = List<NoteDto>.of(widget.notes);

  bool _sameIdentity(NoteDto a, NoteDto b) =>
      a.id == b.id && a.ownerId == b.ownerId;

  @override
  void didUpdateWidget(covariant AnimatedNoteList oldWidget) {
    super.didUpdateWidget(oldWidget);
    final AnimatedListState? list = _listKey.currentState;
    if (list == null) return;
    final Duration duration = NoteFlowMotion.duration(context);
    // ponytail: O(n²) for the current small list; use an identity map if it grows.
    for (int i = _rows.length - 1; i >= 0; i--) {
      if (!widget.notes.any((NoteDto note) => _sameIdentity(note, _rows[i]))) {
        _remove(i, duration);
      }
    }
    for (int i = 0; i < widget.notes.length; i++) {
      final NoteDto note = widget.notes[i];
      final int existing = _rows.indexWhere(
        (NoteDto row) => _sameIdentity(row, note),
      );
      if (existing != i) {
        if (existing >= 0) _remove(existing, duration);
        _rows.insert(i, note);
        list.insertItem(i, duration: duration);
      } else {
        _rows[i] = note;
      }
    }
  }

  void _remove(int index, Duration duration) {
    final NoteDto removed = _rows.removeAt(index);
    _listKey.currentState!.removeItem(
      index,
      (BuildContext context, Animation<double> animation) => ExcludeFocus(
        child: ExcludeSemantics(
          child: IgnorePointer(
            child: _row(context, removed, animation, outgoing: true),
          ),
        ),
      ),
      duration: duration,
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedList(
    key: _listKey,
    initialItemCount: _rows.length,
    padding: const EdgeInsets.only(
      top: NoteFlowSpacing.xs,
      bottom: NoteFlowSpacing.xxxl,
    ),
    itemBuilder: (BuildContext context, int i, Animation<double> animation) =>
        _row(context, _rows[i], animation),
  );

  Widget _row(
    BuildContext context,
    NoteDto note,
    Animation<double> animation, {
    bool outgoing = false,
  }) {
    final NotesCopy copy = NotesCopy.of(context);
    final NoteFlowUiTokens tokens = NoteFlowUiTokens.of(context);
    final compact = NoteFlowLayout.isCompact(context);
    final bool selected = note.reference == widget.selectedNoteId;
    final bool masked =
        !(widget.readable?.call(note) ?? !note.isProtected) ||
        !note.contentAvailable ||
        outgoing && note.share != null;
    final String title = masked
        ? NoteSecurityCopy(context).protectedNote
        : note.title.trim().isEmpty
        ? copy.untitled
        : note.title;
    final String normalized = (masked ? '' : note.content)
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final String preview = masked
        ? ''
        : normalized.isEmpty
        ? copy.noContent
        : normalized;
    return SizeTransition(
      sizeFactor: animation,
      alignment: AlignmentDirectional.topStart,
      child: FadeTransition(
        opacity: animation,
        child: Padding(
          padding: EdgeInsets.only(bottom: compact ? 0 : 4),
          child: ListTile(
            key: ValueKey<String>(
              '${outgoing ? 'outgoing-' : ''}note-${note.reference}',
            ),
            selected: selected,
            selectedTileColor: tokens.textPrimary.withValues(alpha: .07),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(NoteFlowRadius.row),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: NoteFlowSpacing.md,
              vertical: 2,
            ),
            leading: Icon(
              note.isProtected
                  ? Icons.lock_outline
                  : Icons.description_outlined,
              size: 20,
              color: selected ? tokens.textPrimary : tokens.textMuted,
            ),
            title: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontSize: compact ? 18 : 14,
                fontWeight: FontWeight.w400,
                color: tokens.textPrimary,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                NoteLabelChips(note: note, readable: !masked),
                Text(
                  note.share == null || outgoing
                      ? preview
                      : '$preview\n${SharingCopy(context).metadata(note.share!)}',
                  maxLines: note.share == null ? 1 : 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: compact ? 13 : 12,
                    color: tokens.textMuted,
                  ),
                ),
              ],
            ),
            onTap: outgoing || widget.actionBusy
                ? null
                : () => widget.onSelectNote(note),
          ),
        ),
      ),
    );
  }
}
