import 'package:flutter/material.dart';

import '../../application/notes/note_dto.dart';
import '../notes/note_security_localizations.dart';
import '../notes/notes_theme_tokens.dart';
import '../workspace/workspace_ui_tokens.dart';
import 'dashboard_localizations.dart';

/// The existing recent-note projection, presented as compact page cards.
final class DashboardRecentRail extends StatelessWidget {
  const DashboardRecentRail({
    super.key,
    required this.notes,
    required this.copy,
    required this.readable,
    required this.onOpenNote,
    required this.embeddedInWorkspace,
  });

  final List<NoteDto> notes;
  final DashboardCopy copy;
  final bool Function(NoteDto) readable;
  final ValueChanged<NoteDto> onOpenNote;
  final bool embeddedInWorkspace;

  @override
  Widget build(BuildContext context) {
    if (notes.isEmpty) return const SizedBox.shrink();
    final compact = NoteFlowLayout.isCompact(context);
    final tokens = NoteFlowWorkspaceTokens.of(context);
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final height = compact ? 132 + ((scale - 1).clamp(0.0, 1.0) * 32) : 160.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.only(
            left: compact && embeddedInWorkspace ? 4 : 0,
          ),
          child: Text(
            copy.recents,
            style: TextStyle(
              fontSize: compact ? 14 : 16,
              fontWeight: compact ? FontWeight.w400 : FontWeight.w500,
              color: compact ? tokens.textMuted : tokens.textSecondary,
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: height,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: notes.length.clamp(0, 6),
            separatorBuilder: (_, _) => SizedBox(width: compact ? 16 : 12),
            itemBuilder: (context, index) => _RecentCard(
              note: notes[index],
              copy: copy,
              readable: readable(notes[index]),
              onOpenNote: onOpenNote,
              compact: compact,
              height: height,
            ),
          ),
        ),
      ],
    );
  }
}

final class _RecentCard extends StatelessWidget {
  const _RecentCard({
    required this.note,
    required this.copy,
    required this.readable,
    required this.onOpenNote,
    required this.compact,
    required this.height,
  });
  final NoteDto note;
  final DashboardCopy copy;
  final bool readable;
  final ValueChanged<NoteDto> onOpenNote;
  final bool compact;
  final double height;

  @override
  Widget build(BuildContext context) {
    final tokens = NoteFlowWorkspaceTokens.of(context);
    final title = !readable
        ? NoteSecurityCopy(context).protectedNote
        : note.title.trim().isEmpty
        ? copy.untitled
        : note.title.trim();
    return SizedBox(
      width: compact ? 132 : 196,
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: tokens.pageSurface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(
            compact ? 12 : NoteFlowRadius.card,
          ),
          side: BorderSide(color: tokens.divider),
        ),
        child: InkWell(
          onTap: () => onOpenNote(note),
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: ColoredBox(color: tokens.subtleSurface)),
                  Expanded(child: ColoredBox(color: tokens.pageSurface)),
                ],
              ),
              Positioned(
                left: 12,
                top: height / 2 - 12,
                child: Icon(
                  note.isProtected
                      ? Icons.lock_outline
                      : Icons.description_outlined,
                  size: 24,
                  color: tokens.textMuted,
                ),
              ),
              Positioned(
                left: 12,
                right: 12,
                top: height / 2 + 19,
                child: Text(
                  title,
                  maxLines: compact ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    height: 1.3,
                    fontWeight: compact ? FontWeight.w500 : FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
