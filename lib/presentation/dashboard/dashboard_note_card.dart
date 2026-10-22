import '../labels/note_label_chips.dart';
import '../notes/note_security_localizations.dart';

import 'package:flutter/material.dart';

import '../../application/notes/note_application.dart';
import '../notes/notes_theme_tokens.dart';
import '../workspace/workspace_ui_tokens.dart';
import 'dashboard_localizations.dart';

/// Visual density used by a Dashboard note card.
enum DashboardNoteCardLayout { list, grid }

/// A responsive, accessible preview card for one note.
///
/// List layout renders a Notion-style page row (icon, title, light preview);
/// grid layout renders a flat preview card. Both share the same semantics and
/// data contract.
final class DashboardNoteCard extends StatelessWidget {
  const DashboardNoteCard({
    super.key,
    required this.note,
    required this.onTap,
    required this.copy,
    required this.layout,
    this.onTogglePin,
    this.selected = false,
    this.readable,
    this.showPreview = true,
    this.dense = false,
    this.mobileSearch = false,
    this.searchQueryResult = false,
    this.compactHomeList = false,
    this.listHorizontalInset = NoteFlowSpacing.md,
    this.listIconGap = NoteFlowSpacing.md,
  });

  /// Note projection shown by the card.
  final NoteDto note;

  /// Called when the user activates the card.
  final ValueChanged<NoteDto> onTap;

  /// Localized Dashboard copy supplied by the parent.
  final DashboardCopy copy;

  /// Called when the owner toggles this note's pin state.
  final ValueChanged<NoteDto>? onTogglePin;

  /// Layout context used to tune the preview without changing its data.
  final DashboardNoteCardLayout layout;

  /// Whether the card is the current selection in an expanded layout.
  final bool selected;
  final bool? readable;
  bool get _readable =>
      readable ?? (!note.isProtected && note.contentAvailable);

  /// Home can use a compact Notion-style title row/card while other callers
  /// may keep the original preview treatment.
  final bool showPreview;
  final bool dense;
  final bool mobileSearch;

  /// Applies smaller title typography to a non-empty native mobile search.
  final bool searchQueryResult;
  final bool compactHomeList;

  /// Horizontal inset and icon gap used by list rows.
  final double listHorizontalInset;
  final double listIconGap;

  static const Key cardKeyPrefix = ValueKey<String>('dashboard-note-card');

  @override
  Widget build(BuildContext context) {
    final NoteFlowWorkspaceTokens tokens = NoteFlowWorkspaceTokens.of(context);
    final securityCopy = NoteSecurityCopy(context);
    final String title = !_readable
        ? securityCopy.protectedNote
        : (note.title.trim().isEmpty ? copy.untitled : note.title);
    final String preview = !_readable
        ? securityCopy.locked
        : _preview(note.content);
    final String updatedDate = MaterialLocalizations.of(context)
        .formatCompactDate(note.updatedAt);
    final Color foreground = tokens.textPrimary;
    final Color secondaryForeground = selected
        ? tokens.textSecondary
        : tokens.textMuted;
    final bool listLayout = layout == DashboardNoteCardLayout.list;

    return Semantics(
      key: ValueKey<String>('dashboard-note-semantics-${note.id}'),
      button: true,
      selected: selected,
      label: showPreview
          ? copy.noteSemantics(
              title: title,
              preview: preview,
              pinned: note.pinnedAt != null,
            )
          : (note.pinnedAt == null ? title : '$title, ${copy.pinned}'),
      child: Card(
        key: ValueKey<String>('dashboard-note-card-${note.id}'),
        margin: EdgeInsets.zero,
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        clipBehavior: Clip.antiAlias,
        color: selected
            ? tokens.selectedSurface
            : (listLayout ? Colors.transparent : tokens.subtleSurface),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(
            listLayout
                ? mobileSearch || compactHomeList
                      ? 0
                      : dense
                      ? 10
                      : NoteFlowRadius.row
                : NoteFlowRadius.card,
          ),
          side: listLayout
              ? BorderSide.none
              : BorderSide(color: tokens.divider),
        ),
        child: InkWell(
          onTap: () => onTap(note),
          hoverColor: tokens.subtleSurface,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: layout == DashboardNoteCardLayout.grid
                  ? (showPreview ? 144.0 : 88.0)
                  : mobileSearch
                  ? 64.0
                  : compactHomeList
                  ? 48.0
                  : dense
                  ? 38.0
                  : 56.0,
            ),
            child: Padding(
              padding: layout == DashboardNoteCardLayout.grid
                  ? const EdgeInsets.all(NoteFlowSpacing.md)
                  : EdgeInsets.symmetric(
                      horizontal: listHorizontalInset,
                      vertical: dense || compactHomeList
                          ? 0
                          : NoteFlowSpacing.sm,
                    ),
              child: layout == DashboardNoteCardLayout.grid
                  ? _buildGrid(
                      context,
                      title: title,
                      preview: preview,
                      updatedDate: updatedDate,
                      foreground: foreground,
                      secondaryForeground: secondaryForeground,
                    )
                  : _buildList(
                      context,
                      title: title,
                      preview: preview,
                      updatedDate: updatedDate,
                      foreground: foreground,
                      secondaryForeground: secondaryForeground,
                      iconGap: listIconGap,
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGrid(
    BuildContext context, {
    required String title,
    required String preview,
    required String updatedDate,
    required Color foreground,
    required Color secondaryForeground,
  }) {
    final NoteFlowWorkspaceTokens tokens = NoteFlowWorkspaceTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(
              note.isProtected
                  ? Icons.lock_outline
                  : Icons.description_outlined,
              size: 18,
              color: selected ? foreground : tokens.textMuted,
            ),
            _pinButton(context),
          ],
        ),
        const SizedBox(height: NoteFlowSpacing.sm),
        Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.w600, color: foreground),
        ),
        NoteLabelChips(note: note, readable: _readable),
        if (showPreview) ...<Widget>[
          const SizedBox(height: 4),
          Text(
            preview,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: secondaryForeground, height: 1.35),
          ),
          const SizedBox(height: NoteFlowSpacing.sm),
          Text(
            updatedDate,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: secondaryForeground),
          ),
        ],
      ],
    );
  }

  Widget _pinButton(BuildContext context) {
    if (onTogglePin == null) return const SizedBox.shrink();
    final bool isPinned = note.pinnedAt != null;
    final String label = isPinned ? copy.unpinNote : copy.pinNote;
    return IconButton(
      key: ValueKey<String>('dashboard-note-pin-${note.id}'),
      tooltip: label,
      onPressed:
          note.share != null || !note.contentAvailable || note.isProtected
          ? null
          : () => onTogglePin!(note),
      visualDensity: NoteFlowLayout.isCompact(context)
          ? VisualDensity.standard
          : VisualDensity.compact,
      constraints: NoteFlowLayout.isCompact(context)
          ? const BoxConstraints(minWidth: 48, minHeight: 48)
          : null,
      icon: AnimatedSwitcher(
        duration: NoteFlowMotion.duration(context, NoteFlowMotion.fast),
        child: Icon(
          isPinned ? Icons.push_pin : Icons.push_pin_outlined,
          key: ValueKey<bool>(isPinned),
          size: dense ? 16 : 18,
        ),
      ),
    );
  }

  Widget _buildList(
    BuildContext context, {
    required String title,
    required String preview,
    required String updatedDate,
    required Color foreground,
    required Color secondaryForeground,
    required double iconGap,
  }) {
    final tokens = NoteFlowWorkspaceTokens.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final dateBelow = !mobileSearch && constraints.maxWidth < 520;
        return Row(
          children: [
            Icon(
              note.isProtected
                  ? Icons.lock_outline
                  : Icons.description_outlined,
              size: dense
                  ? 16
                  : mobileSearch || compactHomeList
                  ? 18
                  : 20,
              color: selected ? foreground : tokens.textMuted,
            ),
            SizedBox(width: iconGap),
            Expanded(
              child: _buildListText(
                context,
                title,
                preview,
                updatedDate,
                foreground,
                secondaryForeground,
                dateBelow: dateBelow,
              ),
            ),
            if (showPreview && !dense && !mobileSearch && !dateBelow) ...[
              const SizedBox(width: NoteFlowSpacing.md),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 160),
                child: _updatedText(context, updatedDate, secondaryForeground),
              ),
            ],
            if (onTogglePin != null) _pinButton(context),
          ],
        );
      },
    );
  }

  Widget _buildListText(
    BuildContext context,
    String title,
    String preview,
    String date,
    Color foreground,
    Color secondary, {
    required bool dateBelow,
  }) {
    final titleStyle = searchQueryResult || mobileSearch || compactHomeList
        ? Theme.of(context).textTheme.bodyLarge?.copyWith(
            fontSize: searchQueryResult
                ? 13.3
                : mobileSearch
                ? 16
                // Calibrated from the shared title's actual native ink bounds.
                : NoteFlowLayout.isNativePhone(context)
                ? 15.5
                : 18,
            height: 1.2,
            fontWeight: searchQueryResult ? FontWeight.w500 : FontWeight.w400,
            color: foreground,
          )
        : dense
        ? Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: foreground,
          )
        : Theme.of(context).textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.w500, color: foreground);
    final previewStyle = mobileSearch
        ? Theme.of(context).textTheme.bodySmall?.copyWith(
            fontSize: 13,
            height: 1.2,
            fontWeight: FontWeight.w400,
            color: secondary,
          )
        : dense
        ? Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: secondary,
          )
        : Theme.of(context).textTheme.bodySmall?.copyWith(color: secondary);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (dense && showPreview)
          Text.rich(
            TextSpan(
              style: titleStyle,
              children: [
                TextSpan(text: title),
                TextSpan(text: ' — $preview', style: previewStyle),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          )
        else
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: titleStyle,
          ),
        if (!dense && !mobileSearch)
          NoteLabelChips(note: note, readable: _readable),
        if (showPreview && !dense) ...[
          const SizedBox(height: 2),
          Text(
            preview,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: previewStyle,
          ),
        ],
        if (showPreview && !dense && !mobileSearch && dateBelow) ...[
          const SizedBox(height: 2),
          _updatedText(context, date, secondary),
        ],
      ],
    );
  }

  Widget _updatedText(BuildContext context, String date, Color color) => Text(
    copy.updatedOn(date),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
  );

  String _preview(String content) {
    final String normalized = content.replaceAll(RegExp(r'\s+'), ' ').trim();
    return normalized.isEmpty ? copy.noContent : normalized;
  }
}
