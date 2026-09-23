import 'package:flutter/material.dart';

import '../../application/dashboard/dashboard_overview.dart';
import '../../application/notes/note_application.dart';
import '../notes/notes_theme_tokens.dart';
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
    final double viewportWidth = MediaQuery.sizeOf(context).width;
    final bool compact = viewportWidth < NoteFlowLayout.compactBreakpoint;
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        key: const ValueKey<String>('dashboard-content'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        children: <Widget>[
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: NoteFlowLayout.dashboardContentMaxWidth,
              ),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  compact ? NoteFlowSpacing.lg : NoteFlowSpacing.xl,
                  compact
                      ? NoteFlowSpacing.xxl
                      : NoteFlowLayout.dashboardTopPadding,
                  compact ? NoteFlowSpacing.lg : NoteFlowSpacing.xl,
                  NoteFlowSpacing.xxxl,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    if (searchOpen) ...<Widget>[
                      _buildSearchField(context),
                      const SizedBox(height: NoteFlowSpacing.lg),
                    ],
                    _buildHeader(context),
                    const SizedBox(height: NoteFlowSpacing.xl),
                    _buildControls(context),
                    if (hasError) ...<Widget>[
                      const SizedBox(height: NoteFlowSpacing.lg),
                      DashboardInlineError(copy: copy, onRetry: onRetry),
                    ],
                    const SizedBox(height: NoteFlowSpacing.xl),
                    if (filteredNotes.isEmpty && searchText.trim().isNotEmpty)
                      DashboardFilteredEmptyView(
                        copy: copy,
                        onClear: onClearSearch,
                      )
                    else ...<Widget>[
                      if (searchText.trim().isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(
                            bottom: NoteFlowSpacing.sm,
                          ),
                          child: Semantics(
                            header: true,
                            child: Text(
                              copy.recentlyUpdated,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    color: NoteFlowUiTokens.of(context)
                                        .textPrimary,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ),
                        ),
                      _buildNoteCollection(context, filteredNotes),
                    ],
                  ],
                ),
              ),
            ),
          ),
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
    final NoteFlowUiTokens tokens = NoteFlowUiTokens.of(context);
    final int totalNotes = overview?.totalNotes ?? notes.length;
    final DateTime updatedAt = overview?.lastUpdatedAt ?? notes.first.updatedAt;
    final Widget heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          copy.title,
          style: Theme.of(context).textTheme.headlineLarge?.copyWith(
            fontSize: 40,
            height: 1.2,
            fontWeight: FontWeight.w700,
            color: colors.onSurface,
          ),
        ),
        const SizedBox(height: NoteFlowSpacing.sm),
        Wrap(
          spacing: NoteFlowSpacing.md,
          runSpacing: NoteFlowSpacing.xs,
          children: <Widget>[
            Text(
              copy.notesCount(totalNotes),
              key: const ValueKey<String>('dashboard-total-count'),
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: colors.onSurfaceVariant),
            ),
            Text(
              copy.updatedOn(
                MaterialLocalizations.of(context).formatCompactDate(updatedAt),
              ),
              key: const ValueKey<String>('dashboard-last-updated'),
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: colors.onSurfaceVariant),
            ),
          ],
        ),
      ],
    );
    final Widget createButton = OutlinedButton.icon(
      key: const ValueKey<String>('dashboard-create-note'),
      onPressed: onCreateNote,
      icon: const Icon(Icons.add),
      label: Text(copy.newNote),
      style: OutlinedButton.styleFrom(
        foregroundColor: tokens.textPrimary,
        minimumSize: const Size(48, 44),
        padding: const EdgeInsets.symmetric(horizontal: NoteFlowSpacing.md),
        side: BorderSide(color: tokens.divider),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(NoteFlowRadius.input),
        ),
      ),
    );

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        if (constraints.maxWidth < 600.0) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              heading,
              const SizedBox(height: NoteFlowSpacing.md),
              Align(alignment: Alignment.centerLeft, child: createButton),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Expanded(child: heading),
            const SizedBox(width: NoteFlowSpacing.md),
            createButton,
          ],
        );
      },
    );
  }

  Widget _buildControls(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool iconsOnly = constraints.maxWidth < 520;
        return Wrap(
          spacing: NoteFlowSpacing.sm,
          runSpacing: NoteFlowSpacing.sm,
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
              child: iconsOnly
                  ? const SizedBox.square(
                      dimension: 48,
                      child: Center(child: Icon(Icons.sort, size: 20)),
                    )
                  : Container(
                      constraints: const BoxConstraints(minHeight: 48.0),
                      padding: const EdgeInsets.symmetric(
                        horizontal: NoteFlowSpacing.md,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: NoteFlowUiTokens.of(context).divider,
                        ),
                        borderRadius: BorderRadius.circular(
                          NoteFlowRadius.input,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          const Icon(Icons.sort, size: 20),
                          const SizedBox(width: NoteFlowSpacing.sm),
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
                  label: iconsOnly ? const SizedBox.shrink() : Text(copy.list),
                  icon: Tooltip(
                    message: copy.list,
                    child: const Icon(Icons.view_list_outlined),
                  ),
                ),
                ButtonSegment<DashboardLayout>(
                  value: DashboardLayout.grid,
                  label: iconsOnly ? const SizedBox.shrink() : Text(copy.grid),
                  icon: Tooltip(
                    message: copy.grid,
                    child: const Icon(Icons.grid_view_outlined),
                  ),
                ),
              ],
              selected: <DashboardLayout>{layout},
              onSelectionChanged: (Set<DashboardLayout> value) {
                onLayoutChanged(value.first);
              },
            ),
          ],
        );
      },
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
            if (index < items.length - 1)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: NoteFlowSpacing.xl,
                ),
                child: Divider(
                  height: 1,
                  thickness: 1,
                  color: NoteFlowUiTokens.of(context).divider,
                ),
              ),
          ],
        ],
      );
    }

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width = constraints.maxWidth;
        final int columns = _columnCount(width);
        const double gap = NoteFlowSpacing.md;
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
    if (width < NoteFlowLayout.expandedBreakpoint) {
      // Keep Grid meaningfully different from List at compact widths. The
      // List remains the single-column reading mode on phone and tablet.
      return 2;
    }
    const double gap = NoteFlowSpacing.md;
    const double minimumCardWidth = 136.0;
    return ((width + gap) / (minimumCardWidth + gap))
        .floor()
        .clamp(3, 6)
        .toInt();
  }
}
