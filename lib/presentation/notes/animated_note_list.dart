import '../labels/note_label_chips.dart';
import 'note_security_localizations.dart';

import 'package:flutter/material.dart';

import '../../application/notes/note_application.dart';
import 'notes_localizations.dart';
import 'notes_theme_tokens.dart';
import 'sharing_localizations.dart';
import '../../domain/notes/note_body.dart';

/// Animates projection changes only; mutations still belong to the controller.
final class AnimatedNoteList extends StatefulWidget {
  const AnimatedNoteList({
    super.key,
    required this.notes,
    required this.selectedNoteId,
    required this.actionBusy,
    required this.onSelectNote,
    this.readable,
    this.layout = NoteLayoutPreference.list,
    this.canPin,
    this.onTogglePinned,
    this.pinningNoteId,
    this.pinEnabled = true,
  });

  final List<NoteDto> notes;
  final bool Function(NoteDto)? readable;
  final NoteLayoutPreference layout;
  final bool Function(NoteDto)? canPin;
  final ValueChanged<NoteDto>? onTogglePinned;
  final String? pinningNoteId;
  final bool pinEnabled;
  final String? selectedNoteId;
  final bool actionBusy;
  final ValueChanged<NoteDto> onSelectNote;

  @override
  State<AnimatedNoteList> createState() => _AnimatedNoteListState();
}

final class _NoteGridCard extends StatefulWidget {
  const _NoteGridCard({
    super.key,
    required this.title,
    required this.preview,
    required this.selected,
    required this.onTap,
    required this.indicators,
    required this.labels,
    required this.metadata,
    required this.updatedLabel,
  });

  final String title;
  final String preview;
  final bool selected;
  final VoidCallback? onTap;
  final Widget indicators;
  final Widget labels;
  final String? metadata;
  final String updatedLabel;

  @override
  State<_NoteGridCard> createState() => _NoteGridCardState();
}

final class _NoteGridCardState extends State<_NoteGridCard> {
  bool _focused = false;
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final tokens = NoteFlowUiTokens.of(context);
    return Semantics(
      selected: widget.selected,
      button: true,
      enabled: widget.onTap != null,
      child: AnimatedContainer(
        duration: NoteFlowMotion.duration(context, NoteFlowMotion.fast),
        curve: Curves.easeOutCubic,
        transform: Matrix4.translationValues(
          0,
          widget.onTap != null &&
                  _hovered &&
                  !_pressed &&
                  !MediaQuery.disableAnimationsOf(context)
              ? -2
              : 0,
          0,
        ),
        decoration: BoxDecoration(
          color: widget.selected
              ? tokens.selectedSurface
              : widget.onTap != null && (_hovered || _pressed)
              ? tokens.subtleSurface
              : tokens.pageSurface,
          borderRadius: BorderRadius.circular(NoteFlowRadius.card),
          border: Border.all(
            color: _focused
                ? tokens.focusRing
                : widget.selected
                ? tokens.link
                : tokens.divider,
            width: 1.5,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            onFocusChange: (value) => setState(() => _focused = value),
            onHover: (value) => setState(() => _hovered = value),
            onHighlightChanged: (value) => setState(() => _pressed = value),
            mouseCursor: widget.onTap == null
                ? SystemMouseCursors.basic
                : SystemMouseCursors.click,
            borderRadius: BorderRadius.circular(NoteFlowRadius.card),
            hoverColor: Colors.transparent,
            focusColor: tokens.link.withValues(alpha: 0.06),
            highlightColor: tokens.link.withValues(alpha: 0.12),
            splashColor: tokens.link.withValues(alpha: 0.10),
            splashFactory: MediaQuery.disableAnimationsOf(context)
                ? NoSplash.splashFactory
                : InkRipple.splashFactory,
            child: Padding(
              padding: const EdgeInsets.all(NoteFlowSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.description_outlined,
                        size: 22,
                        color: tokens.textPrimary,
                      ),
                      const Spacer(),
                      SizedBox(height: 48, child: widget.indicators),
                    ],
                  ),
                  Text(
                    widget.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontSize: 18,
                      color: tokens.textPrimary,
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: NoteFlowSpacing.sm),
                  Expanded(
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: Text(
                        widget.preview,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: tokens.textSecondary,
                          height: 1.5,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                  ),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: widget.labels,
                  ),
                  if (widget.metadata != null) ...[
                    const SizedBox(height: NoteFlowSpacing.sm),
                    Text(
                      widget.metadata!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall
                          ?.copyWith(color: tokens.textMuted, height: 1.4),
                    ),
                  ],
                  const SizedBox(height: NoteFlowSpacing.md),
                  Divider(height: 1, color: tokens.divider),
                  const SizedBox(height: NoteFlowSpacing.md),
                  Text(
                    widget.updatedLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall
                        ?.copyWith(color: tokens.textMuted, height: 1.4),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

final class _AnimatedNoteListState extends State<AnimatedNoteList> {
  GlobalKey<AnimatedListState> _listKey = GlobalKey<AnimatedListState>();
  late final List<NoteDto> _rows = List<NoteDto>.of(widget.notes);

  bool _sameIdentity(NoteDto a, NoteDto b) =>
      a.id == b.id && a.ownerId == b.ownerId;

  @override
  void didUpdateWidget(covariant AnimatedNoteList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.layout != widget.layout ||
        widget.layout == NoteLayoutPreference.grid) {
      _rows
        ..clear()
        ..addAll(widget.notes);
      if (oldWidget.layout != widget.layout) {
        _listKey = GlobalKey<AnimatedListState>();
      }
      return;
    }
    final AnimatedListState? list = _listKey.currentState;
    if (list == null) return;
    final Duration duration = NoteFlowMotion.duration(context);
    // shortcut: O(n²) for the current small list; use an identity map if it grows.
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
  Widget build(BuildContext context) {
    if (widget.layout == NoteLayoutPreference.grid) {
      return _layoutEntrance(
        context,
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = (constraints.maxWidth / 260).floor().clamp(1, 4);
            return GridView.builder(
              key: const PageStorageKey('notes-grid'),
              padding: const EdgeInsets.only(
                top: NoteFlowSpacing.xs,
                bottom: NoteFlowSpacing.xxxl,
              ),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisExtent:
                    MediaQuery.textScalerOf(context).scale(220) + 48,
                crossAxisSpacing: NoteFlowSpacing.md,
                mainAxisSpacing: NoteFlowSpacing.md,
              ),
              itemCount: widget.notes.length,
              itemBuilder: (context, index) {
                final note = widget.notes[index];
                final facts = _projection(context, note);
                return _NoteGridCard(
                  key: ValueKey('note-${note.reference}'),
                  title: facts.title,
                  preview: facts.preview,
                  selected: note.reference == widget.selectedNoteId,
                  onTap: widget.actionBusy
                      ? null
                      : () => widget.onSelectNote(note),
                  indicators: _indicators(context, note),
                  labels: NoteLabelChips(note: note, readable: !facts.masked),
                  metadata: note.share == null
                      ? null
                      : SharingCopy(context).metadata(note.share!),
                  updatedLabel: _updatedLabel(context, note),
                );
              },
            );
          },
        ),
      );
    }
    return _layoutEntrance(
      context,
      AnimatedList(
        key: _listKey,
        initialItemCount: _rows.length,
        padding: const EdgeInsets.only(
          top: NoteFlowSpacing.xs,
          bottom: NoteFlowSpacing.xxxl,
        ),
        itemBuilder: (
          BuildContext context,
          int i,
          Animation<double> animation,
        ) => _row(context, _rows[i], animation),
      ),
    );
  }

  Widget _layoutEntrance(BuildContext context, Widget child) =>
      TweenAnimationBuilder<double>(
        key: ValueKey(widget.layout),
        tween: Tween(begin: 0.92, end: 1),
        duration: NoteFlowMotion.duration(context, NoteFlowMotion.fast),
        curve: Curves.easeOutCubic,
        builder: (context, value, content) =>
            Opacity(opacity: value, child: content),
        child: child,
      );

  String _updatedLabel(BuildContext context, NoteDto note) =>
      NotesCopy.of(context).updatedOn(
        MaterialLocalizations.of(context)
            .formatShortDate(note.updatedAt.toLocal()),
      );

  ({String title, String preview, bool masked}) _projection(
    BuildContext context,
    NoteDto note, {
    bool outgoing = false,
  }) {
    final copy = NotesCopy.of(context);
    final masked =
        !(widget.readable?.call(note) ?? !note.isProtected) ||
        !note.contentAvailable ||
        outgoing && note.share != null;
    final title = masked
        ? NoteSecurityCopy(context).protectedNote
        : note.title.trim().isEmpty
        ? copy.untitled
        : note.title;
    final normalized = (masked ? '' : NoteBody.plainText(note.content))
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return (
      title: title,
      preview: masked
          ? ''
          : normalized.isEmpty
          ? copy.noContent
          : normalized,
      masked: masked,
    );
  }

  Widget _indicators(
    BuildContext context,
    NoteDto note, {
    bool outgoing = false,
  }) {
    final copy = NotesCopy.of(context);
    final tokens = NoteFlowUiTokens.of(context);
    Widget badge(IconData icon, String label) => Semantics(
      label: label,
      child: Tooltip(
        message: label,
        child: ExcludeSemantics(
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Icon(icon, size: 18, color: tokens.textSecondary),
          ),
        ),
      ),
    );
    final hasPinAction =
        !outgoing &&
        widget.onTogglePinned != null &&
        (widget.canPin?.call(note) ?? false);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (note.isProtected)
          badge(Icons.lock_outline, NoteSecurityCopy(context).protectedNote),
        if (note.share != null) badge(Icons.people_outline, copy.sharedNote),
        if (hasPinAction)
          IconButton(
            isSelected: note.isPinned,
            key: ValueKey('pin-${note.reference}'),
            tooltip: note.isPinned ? copy.unpin : copy.pin,
            onPressed: widget.actionBusy || !widget.pinEnabled
                ? null
                : () => widget.onTogglePinned!(note),
            style: IconButton.styleFrom(
              minimumSize: const Size(48, 48),
              visualDensity: VisualDensity.standard,
              foregroundColor: tokens.textSecondary,
              backgroundColor: note.isPinned ? tokens.selectedSurface : null,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(NoteFlowRadius.input),
              ),
            ),
            icon: widget.pinningNoteId == note.reference
                ? MediaQuery.disableAnimationsOf(context)
                      ? const Icon(Icons.hourglass_top, size: 18)
                      : const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                : Icon(
                    note.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                    size: 18,
                  ),
          )
        else if (note.isPinned)
          badge(Icons.push_pin, copy.pinned),
      ],
    );
  }

  Widget _row(
    BuildContext context,
    NoteDto note,
    Animation<double> animation, {
    bool outgoing = false,
  }) {
    final NoteFlowUiTokens tokens = NoteFlowUiTokens.of(context);
    final bool selected = note.reference == widget.selectedNoteId;
    final facts = _projection(context, note, outgoing: outgoing);
    final title = facts.title;
    final preview = facts.preview;
    return SizeTransition(
      sizeFactor: animation,
      alignment: AlignmentDirectional.topStart,
      child: FadeTransition(
        opacity: animation,
        child: Padding(
          padding: const EdgeInsets.only(bottom: NoteFlowSpacing.md),
          child: Semantics(
            selected: selected,
            button: true,
            label: '$title. $preview',
            child: ListTile(
              key: ValueKey<String>(
                '${outgoing ? 'outgoing-' : ''}note-${note.reference}',
              ),
              selected: selected,
              selectedTileColor: tokens.selectedSurface,
              tileColor: tokens.elevatedSurface,
              hoverColor: tokens.subtleSurface,
              focusColor: tokens.selectedSurface,
              enabled: !outgoing && !widget.actionBusy,
              trailing: _indicators(context, note, outgoing: outgoing),
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
                  fontWeight: FontWeight.w600,
                  color: tokens.textPrimary,
                ),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    note.share == null || outgoing
                        ? preview
                        : '$preview\n${SharingCopy(context).metadata(note.share!)}',
                    maxLines: note.share == null ? 1 : 3,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: tokens.textSecondary, height: 1.5),
                  ),
                  NoteLabelChips(note: note, readable: !facts.masked),
                  Padding(
                    padding: const EdgeInsets.only(top: NoteFlowSpacing.xs),
                    child: Text(
                      _updatedLabel(context, note),
                      style: Theme.of(context).textTheme.labelSmall
                          ?.copyWith(color: tokens.textMuted),
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
      ),
    );
  }
}
