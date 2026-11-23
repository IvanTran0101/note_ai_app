import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../application/notes/note_dto.dart';
import '../notes/note_security_localizations.dart';
import '../notes/notes_theme_tokens.dart';
import '../workspace/workspace_ui_tokens.dart';
import 'dashboard_localizations.dart';

const double _compactTitleFontSize = 14;
const double _wideTitleFontSize = 16;
const double _titleLineHeight = 1.3;
const double _titleTopAfterDivider = 19;
const double _titleBottomInset = 8;

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
    final height = _recentCardHeight(context, compact);
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

double _recentCardHeight(BuildContext context, bool compact) {
  final textScaler = MediaQuery.textScalerOf(context);
  final fontSize = compact ? _compactTitleFontSize : _wideTitleFontSize;
  final lines = compact ? 2 : 1;
  final titleHeight = textScaler.scale(fontSize) * _titleLineHeight * lines;
  final requiredHeight =
      2 * (titleHeight + _titleTopAfterDivider + _titleBottomInset);
  final minimumHeight = compact ? 132.0 : 160.0;
  return math.max(minimumHeight, requiredHeight).toDouble();
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
    final nativeDarkCard =
        compact && Theme.of(context).brightness == Brightness.dark;
    final cardSurface = compact
        ? tokens.compactHomeSurface
        : tokens.pageSurface;
    final coverSurface = nativeDarkCard
        ? const Color(0xFF333333)
        : tokens.subtleSurface;
    final titleFontSize = compact ? _compactTitleFontSize : _wideTitleFontSize;
    final titleStyle =
        (Theme.of(context).textTheme.titleSmall ?? const TextStyle()).copyWith(
          color: tokens.textPrimary,
          fontSize: titleFontSize,
          height: _titleLineHeight,
          fontWeight: FontWeight.w600,
        );
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
        color: cardSurface,
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
                  Expanded(child: ColoredBox(color: coverSurface)),
                  Expanded(child: ColoredBox(color: cardSurface)),
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
                top: height / 2 + _titleTopAfterDivider,
                bottom: _titleBottomInset,
                child: Text(
                  title,
                  maxLines: compact ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: titleStyle,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
