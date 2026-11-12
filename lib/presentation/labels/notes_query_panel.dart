import 'package:flutter/material.dart';

import '../../application/labels/note_query.dart';
import '../../application/notes/note_dto.dart';
import '../notes/note_ordering.dart';
import '../notes/notes_list_panel.dart';
import '../notes/notes_theme_tokens.dart';
import 'label_catalog_scope.dart';
import 'label_copy.dart';
import 'label_filter_bar.dart';

/// Queries loaded projections without changing workspace/editor selection.
final class NotesQueryPanel extends StatefulWidget {
  const NotesQueryPanel({super.key, required this.panel});
  final NotesListPanel panel;
  @override
  State<NotesQueryPanel> createState() => _NotesQueryPanelState();
}

final class _NotesQueryPanelState extends State<NotesQueryPanel> {
  final _search = TextEditingController();
  Set<LabelSelection> _selected = {};
  String? _actor;
  bool _readable(NoteDto n) =>
      widget.panel.readable?.call(n) ?? (!n.isProtected && n.contentAvailable);
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = LabelCatalogScope.maybeOf(context);
    final actor = scope?.application?.currentActor();
    if (_actor != actor) {
      _actor = actor;
      _search.clear();
      _selected = {};
    }
  }

  void _queryChanged() {
    setState(() {});
    widget.panel.onQueryChanged?.call(_search.text, _selected);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  NotesListPanel _panel(
    List<NoteDto> notes, {
    Widget? queryControls,
    Widget? filteredEmpty,
  }) {
    final p = widget.panel;
    return NotesListPanel(
      notes: notes,
      selectedNoteId: p.selectedNoteId,
      error: p.error,
      actionBusy: p.actionBusy,
      onNewNote: p.onNewNote,
      onSelectNote: p.onSelectNote,
      onRetry: p.onRetry,
      titleOverride: p.titleOverride,
      allowNewNote: p.allowNewNote,
      readable: p.readable,
      queryEnabled: false,
      queryControls: queryControls,
      filteredEmpty: filteredEmpty,
      pageFooter: p.pageFooter,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scope = LabelCatalogScope.maybeOf(context), p = widget.panel;
    if (scope?.application == null) return _panel(p.notes);
    final copy = LabelCopy(context);
    final compact = NoteFlowLayout.isCompact(context);
    final tokens = NoteFlowUiTokens.of(context);
    final filtered = p.onQueryChanged != null
        ? p.notes
        : queryNotes(
            p.notes,
            keyword: _search.text,
            selected: _selected,
            readable: _readable,
            labelsFor: (n) => visibleLabels(
              n,
              scope!.labels,
              actor: scope.actor,
              readable: _readable(n),
            ),
          );
    return _panel(
      sortNotes(filtered),
      queryControls: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            Semantics(
              container: true,
              explicitChildNodes: true,
              child: TextField(
                key: const ValueKey('notes-search-field'),
                controller: _search,
                onChanged: (_) => _queryChanged(),
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(
                    Icons.search,
                    size: 20,
                    color: tokens.textMuted,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  hintText: copy.search,
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: copy.clear,
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _search.clear();
                            _queryChanged();
                          },
                        ),
                ),
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 160),
              child: SingleChildScrollView(
                child: LabelFilterBar(
                  notes: p.notes,
                  additionalChoices: p.labelChoices,
                  selected: _selected,
                  onChanged: (next) {
                    _selected = next;
                    _queryChanged();
                  },
                  readable: _readable,
                  allowManage: p.allowNewNote,
                  dense: compact,
                  singleLine: compact,
                ),
              ),
            ),
          ],
        ),
      ),
      filteredEmpty:
          filtered.isEmpty &&
              p.error == null &&
              (_search.text.trim().isNotEmpty || _selected.isNotEmpty)
          ? Center(child: Text(copy.noResults))
          : null,
    );
  }
}
