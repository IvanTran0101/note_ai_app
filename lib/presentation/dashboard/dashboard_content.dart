import 'package:flutter/material.dart';

import '../../application/dashboard/dashboard_overview.dart';
import '../../application/notes/note_application.dart';
import 'dashboard_localizations.dart';
import 'dashboard_note_card.dart';
import 'dashboard_state_views.dart';
import 'dashboard_view_models.dart';

/// Loaded Dashboard surface: toolbar, local filtering and responsive note list.
final class DashboardContent extends StatelessWidget {
  const DashboardContent({
    super.key,
    required this.notes,
    required this.overview,
    required this.copy,
    required this.searchController,
    required this.searchOpen,
    required this.searchText,
    required this.layout,
    required this.sort,
    required this.selectedNoteId,
    required this.hasError,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.onSortChanged,
    required this.onLayoutChanged,
    required this.onOpenNote,
    required this.onCreateNote,
    required this.onRetry,
    required this.onRefresh,
  });

  final List<NoteDto> notes;
  final DashboardOverview? overview;
  final DashboardCopy copy;
  final TextEditingController searchController;
  final bool searchOpen;
  final String searchText;
  final DashboardLayout layout;
  final DashboardSort sort;
  final String? selectedNoteId;
  final bool hasError;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final ValueChanged<DashboardSort> onSortChanged;
  final ValueChanged<DashboardLayout> onLayoutChanged;
  final ValueChanged<NoteDto> onOpenNote;
  final VoidCallback onCreateNote;
  final VoidCallback onRetry;
  final Future<void> Function() onRefresh;

  List<NoteDto> get visibleNotes {
    final String query = searchText.trim().toLowerCase();
    final List<NoteDto> result = notes.where((NoteDto note) {
      if (query.isEmpty) {
        return true;
      }
      return note.title.toLowerCase().contains(query) ||
          note.content.toLowerCase().contains(query);
    }).toList();
    result.sort((NoteDto a, NoteDto b) {
      final DateTime aDate = sort == DashboardSort.updated
          ? a.updatedAt
          : a.createdAt;
      final DateTime bDate = sort == DashboardSort.updated
          ? b.updatedAt
          : b.createdAt;
      final int byDate = bDate.compareTo(aDate);
      return byDate == 0 ? a.id.compareTo(b.id) : byDate;
    });
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final List<NoteDto> filteredNotes = visibleNotes;
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        key: const ValueKey<String>('dashboard-content'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20.0, 20.0, 20.0, 32.0),
        children: <Widget>[
          if (searchOpen) ...<Widget>[
            _buildSearchField(context),
            const SizedBox(height: 16.0),
          ],
          _buildHeader(context),
          const SizedBox(height: 20.0),
          _buildControls(context),
          if (hasError) ...<Widget>[
            const SizedBox(height: 16.0),
            DashboardInlineError(copy: copy, onRetry: onRetry),
          ],
          const SizedBox(height: 20.0),
          if (filteredNotes.isEmpty && searchText.trim().isNotEmpty)
            DashboardFilteredEmptyView(copy: copy, onClear: onClearSearch)
          else
            _buildNoteCollection(context, filteredNotes),
        ],
      ),
    );
  }

  Widget _buildSearchField(BuildContext context) {
    return TextField(
      key: const ValueKey<String>('dashboard-search-field'),
      controller: searchController,
      autofocus: true,
      onChanged: onSearchChanged,
      decoration: InputDecoration(
        labelText: copy.searchNotes,
        prefixIcon: const Icon(Icons.search),
        suffixIcon: searchText.isEmpty
            ? null
            : IconButton(
                key: const ValueKey<String>('dashboard-clear-search-field'),
                tooltip: copy.clearSearch,
                icon: const Icon(Icons.clear),
                onPressed: onClearSearch,
              ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final int totalNotes = overview?.totalNotes ?? notes.length;
    final DateTime updatedAt = overview?.lastUpdatedAt ?? notes.first.updatedAt;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                copy.allNotes,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colors.onSurface,
                ),
              ),
              const SizedBox(height: 4.0),
              Text(
                copy.notesCount(totalNotes),
                key: const ValueKey<String>('dashboard-total-count'),
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: colors.onSurfaceVariant),
              ),
              Text(
                copy.updatedOn(
                  MaterialLocalizations.of(context)
                      .formatCompactDate(updatedAt),
                ),
                key: const ValueKey<String>('dashboard-last-updated'),
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: colors.onSurfaceVariant),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12.0),
        FilledButton.icon(
          key: const ValueKey<String>('dashboard-create-note'),
          onPressed: onCreateNote,
          icon: const Icon(Icons.add),
          label: Text(copy.newNote),
        ),
      ],
    );
  }

  Widget _buildControls(BuildContext context) {
    return Wrap(
      spacing: 8.0,
      runSpacing: 8.0,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        PopupMenuButton<DashboardSort>(
          tooltip: copy.sort,
          initialValue: sort,
          onSelected: onSortChanged,
          itemBuilder: (BuildContext context) =>
              <PopupMenuEntry<DashboardSort>>[
                PopupMenuItem<DashboardSort>(
                  value: DashboardSort.updated,
                  child: Text(copy.sortUpdated),
                ),
                PopupMenuItem<DashboardSort>(
                  value: DashboardSort.created,
                  child: Text(copy.sortCreated),
                ),
              ],
          child: Container(
            constraints: const BoxConstraints(minHeight: 48.0),
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).colorScheme.outline),
              borderRadius: BorderRadius.circular(20.0),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(Icons.sort),
                const SizedBox(width: 8.0),
                Text(
                  sort == DashboardSort.updated
                      ? copy.sortUpdated
                      : copy.sortCreated,
                ),
              ],
            ),
          ),
        ),
        SegmentedButton<DashboardLayout>(
          key: const ValueKey<String>('dashboard-layout-toggle'),
          segments: <ButtonSegment<DashboardLayout>>[
            ButtonSegment<DashboardLayout>(
              value: DashboardLayout.list,
              label: Text(copy.list),
              icon: const Icon(Icons.view_list_outlined),
            ),
            ButtonSegment<DashboardLayout>(
              value: DashboardLayout.grid,
              label: Text(copy.grid),
              icon: const Icon(Icons.grid_view_outlined),
            ),
          ],
          selected: <DashboardLayout>{layout},
          onSelectionChanged: (Set<DashboardLayout> value) {
            onLayoutChanged(value.first);
          },
        ),
      ],
    );
  }

  Widget _buildNoteCollection(BuildContext context, List<NoteDto> items) {
    if (layout == DashboardLayout.list) {
      return Column(
        children: <Widget>[
          for (int index = 0; index < items.length; index++) ...<Widget>[
            DashboardNoteCard(
              key: ValueKey<String>('dashboard-note-${items[index].id}'),
              note: items[index],
              copy: copy,
              layout: DashboardNoteCardLayout.list,
              selected: items[index].id == selectedNoteId,
              onTap: onOpenNote,
            ),
            if (index < items.length - 1) const SizedBox(height: 12.0),
          ],
        ],
      );
    }

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width = constraints.maxWidth;
        final int columns = _columnCount(width);
        const double gap = 12.0;
        final double cardWidth = (width - (columns - 1) * gap) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: <Widget>[
            for (final NoteDto note in items)
              SizedBox(
                width: cardWidth,
                child: DashboardNoteCard(
                  key: ValueKey<String>('dashboard-note-${note.id}'),
                  note: note,
                  copy: copy,
                  layout: DashboardNoteCardLayout.grid,
                  selected: note.id == selectedNoteId,
                  onTap: onOpenNote,
                ),
              ),
          ],
        );
      },
    );
  }

  int _columnCount(double width) {
    if (width < 600.0) {
      return 1;
    }
    if (width < 840.0) {
      return 2;
    }
    final int columns = (width / 300.0).floor();
    if (columns < 3) {
      return 3;
    }
    return columns > 4 ? 4 : columns;
  }
}
