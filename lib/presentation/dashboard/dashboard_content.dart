import 'package:flutter/material.dart';

import '../../application/dashboard/dashboard_overview.dart';
import '../../application/notes/note_application.dart';
import '../notes/notes_theme_tokens.dart';
import '../workspace/workspace_ui_tokens.dart';
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
    this.onTogglePin,
    required this.onCreateNote,
    required this.onRetry,
    required this.onRefresh,
    required this.embeddedInWorkspace,
    this.onCloseSearch,
    this.dockCompactSearch = false,
    this.searchOverlay = false,
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
  final ValueChanged<NoteDto>? onTogglePin;
  final VoidCallback onCreateNote;
  final VoidCallback onRetry;
  final Future<void> Function() onRefresh;
  final bool embeddedInWorkspace;
  final VoidCallback? onCloseSearch;
  final bool dockCompactSearch;
  final bool searchOverlay;

  List<NoteDto> get visibleNotes {
    final String query = searchText.trim().toLowerCase();
    final Iterable<NoteDto> result = notes.where((NoteDto note) {
      if (query.isEmpty) {
        return true;
      }
      return note.title.toLowerCase().contains(query) ||
          note.content.toLowerCase().contains(query);
    });
    return sortNotes(result, byCreatedAt: sort == DashboardSort.created);
  }

  @override
  Widget build(BuildContext context) {
    final List<NoteDto> filteredNotes = visibleNotes;
    final double viewportWidth = MediaQuery.sizeOf(context).width;
    final bool compact = viewportWidth < NoteFlowLayout.compactBreakpoint;
    final bool showingDesktopSearchHistory =
        searchOpen && searchOverlay && !compact && searchText.trim().isEmpty;
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        key: const ValueKey<String>('dashboard-content'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        children: <Widget>[
          Align(
            alignment: compact ? Alignment.topLeft : Alignment.center,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: searchOverlay
                    ? 1008
                    : compact
                    ? NoteFlowLayout.compactPageFrameMaxWidthFor(context)
                    : NoteFlowLayout.dashboardContentMaxWidth,
              ),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  compact
                      ? NoteFlowLayout.compactPageLeadingInsetFor(context)
                      : NoteFlowSpacing.xl,
                  compact
                      ? embeddedInWorkspace
                            ? searchOpen
                                  ? NoteFlowSpacing.xl
                                  : NoteFlowSpacing.sm + NoteFlowSpacing.xs
                            : NoteFlowLayout.compactPageTopInset(context)
                      : searchOverlay
                      ? NoteFlowSpacing.lg
                      : NoteFlowLayout.dashboardTopPadding,
                  compact ? NoteFlowSpacing.lg : NoteFlowSpacing.xl,
                  searchOverlay ? NoteFlowSpacing.lg : NoteFlowSpacing.xxxl,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    if (searchOpen) ...<Widget>[
                      if (searchOverlay && !compact)
                        Row(
                          children: <Widget>[
                            Expanded(child: _buildSearchField(context)),
                            if (onCloseSearch != null)
                              IconButton(
                                key: const ValueKey<String>(
                                  'dashboard-search-close',
                                ),
                                tooltip: copy.closeSearch,
                                onPressed: onCloseSearch,
                                icon: const Icon(Icons.close),
                              ),
                          ],
                        )
                      else
                        _buildSearchHeading(
                          context,
                          compact: compact,
                          showCloseButton: !dockCompactSearch,
                        ),
                      if (!dockCompactSearch) ...<Widget>[
                        if (!(searchOverlay && !compact)) ...<Widget>[
                          SizedBox(
                            height: compact
                                ? NoteFlowSpacing.md
                                : NoteFlowSpacing.sm,
                          ),
                          _buildSearchField(context),
                        ],
                        const SizedBox(height: NoteFlowSpacing.sm),
                      ],
                    ],
                    if ((!compact || !embeddedInWorkspace) && !searchOpen)
                      _buildHeader(context),
                    if (searchOpen && dockCompactSearch) ...<Widget>[
                      const SizedBox(height: NoteFlowSpacing.xxxl),
                      Center(
                        child: Text(
                          copy.searchNotes,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: NoteFlowWorkspaceTokens.of(context)
                                    .textMuted,
                              ),
                        ),
                      ),
                      if (searchText.trim().isNotEmpty)
                        const SizedBox(
                          height: NoteFlowSpacing.xl + NoteFlowSpacing.xs,
                        ),
                    ] else if (!showingDesktopSearchHistory &&
                        searchText.trim().isEmpty) ...<Widget>[
                      SizedBox(
                        height: compact && embeddedInWorkspace
                            ? NoteFlowSpacing.sm
                            : NoteFlowSpacing.lg,
                      ),
                      _buildRecentRail(context, filteredNotes, viewportWidth),
                      const SizedBox(height: NoteFlowSpacing.md),
                      if (compact && viewportWidth >= 360)
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: _buildSectionHeading(
                                context,
                                copy.allNotes,
                                leadingInset: compact && embeddedInWorkspace
                                    ? NoteFlowSpacing.xs
                                    : 0,
                              ),
                            ),
                            const SizedBox(width: NoteFlowSpacing.xs),
                            SizedBox(
                              width: 200,
                              child: _buildControls(
                                context,
                                includeLayout: !searchOverlay,
                              ),
                            ),
                          ],
                        )
                      else if (compact)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            _buildSectionHeading(
                              context,
                              copy.allNotes,
                              leadingInset: embeddedInWorkspace
                                  ? NoteFlowSpacing.xs
                                  : 0,
                            ),
                            const SizedBox(height: NoteFlowSpacing.xs),
                            _buildControls(
                              context,
                              includeLayout: !searchOverlay,
                            ),
                          ],
                        )
                      else ...<Widget>[
                        _buildSectionHeading(context, copy.allNotes),
                        const SizedBox(height: NoteFlowSpacing.sm),
                        _buildControls(context, includeLayout: !searchOverlay),
                      ],
                      SizedBox(
                        height: compact
                            ? NoteFlowSpacing.xs
                            : NoteFlowSpacing.xl,
                      ),
                    ] else if (!searchOpen || !compact) ...<Widget>[
                      SizedBox(
                        height: searchOverlay
                            ? NoteFlowSpacing.md
                            : NoteFlowSpacing.xl,
                      ),
                      _buildControls(context, includeLayout: !searchOverlay),
                    ],
                    if (hasError) ...<Widget>[
                      const SizedBox(height: NoteFlowSpacing.lg),
                      DashboardInlineError(copy: copy, onRetry: onRetry),
                    ],
                    SizedBox(
                      height: compact
                          ? 0
                          : searchOverlay
                          ? NoteFlowSpacing.sm
                          : NoteFlowSpacing.xl,
                    ),
                    if (filteredNotes.isEmpty && searchText.trim().isNotEmpty)
                      DashboardFilteredEmptyView(
                        copy: copy,
                        onClear: onClearSearch,
                      )
                    else ...<Widget>[
                      _buildNoteCollection(
                        context,
                        filteredNotes,
                        viewportWidth,
                      ),
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
    final NoteFlowWorkspaceTokens tokens = NoteFlowWorkspaceTokens.of(context);
    final OutlineInputBorder searchBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(28),
      borderSide: BorderSide(color: tokens.divider),
    );
    return TextField(
      key: const ValueKey<String>('dashboard-search-field'),
      controller: searchController,
      autofocus: true,
      onChanged: onSearchChanged,
      decoration: InputDecoration(
        hintText: copy.searchNotes,
        filled: true,
        fillColor: tokens.subtleSurface,
        prefixIcon: const Icon(Icons.search, size: 20),
        suffixIcon: searchText.isEmpty
            ? null
            : IconButton(
                key: const ValueKey<String>('dashboard-clear-search-field'),
                tooltip: copy.clearSearch,
                icon: const Icon(Icons.clear),
                onPressed: onClearSearch,
              ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: NoteFlowSpacing.md,
          vertical: NoteFlowSpacing.md,
        ),
        border: searchBorder,
        enabledBorder: searchBorder.copyWith(
          borderSide: BorderSide(color: tokens.divider),
        ),
        focusedBorder: searchBorder.copyWith(
          borderSide: BorderSide(color: tokens.focusRing),
        ),
      ),
    );
  }

  Widget _buildSearchHeading(
    BuildContext context, {
    required bool compact,
    required bool showCloseButton,
  }) {
    final NoteFlowWorkspaceTokens tokens = NoteFlowWorkspaceTokens.of(context);
    final Text heading = Text(
      copy.search,
      style: Theme.of(context).textTheme.headlineSmall
          ?.copyWith(color: tokens.textPrimary, fontWeight: FontWeight.w700),
    );
    if (!showCloseButton) {
      return Semantics(header: true, child: heading);
    }
    return Row(
      children: <Widget>[
        Expanded(child: Semantics(header: true, child: heading)),
        if (onCloseSearch != null)
          IconButton(
            key: const ValueKey<String>('dashboard-search-close'),
            tooltip: copy.closeSearch,
            onPressed: onCloseSearch,
            icon: const Icon(Icons.close),
          ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final NoteFlowWorkspaceTokens tokens = NoteFlowWorkspaceTokens.of(context);
    final int totalNotes = overview?.totalNotes ?? notes.length;
    final DateTime? updatedAt =
        overview?.lastUpdatedAt ??
        (notes.isEmpty ? null : notes.first.updatedAt);
    final Widget heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          copy.title,
          style: Theme.of(context).textTheme.headlineLarge?.copyWith(
            fontSize:
                MediaQuery.sizeOf(context).width <
                    NoteFlowLayout.compactBreakpoint
                ? 32
                : 40,
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
            if (updatedAt != null)
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
      ],
    );
    final Widget createButton = FilledButton.icon(
      key: const ValueKey<String>('dashboard-create-note'),
      onPressed: onCreateNote,
      icon: const Icon(Icons.add),
      label: Text(copy.newNote),
      style: FilledButton.styleFrom(
        backgroundColor: tokens.selectedSurface,
        foregroundColor: tokens.textPrimary,
        minimumSize: const Size(48, 44),
        padding: const EdgeInsets.symmetric(horizontal: NoteFlowSpacing.md),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(NoteFlowRadius.input),
        ),
      ),
    );

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final Widget content;
        if (constraints.maxWidth < 600.0) {
          content = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              heading,
              const SizedBox(height: NoteFlowSpacing.md),
              Align(alignment: Alignment.centerLeft, child: createButton),
            ],
          );
        } else {
          content = Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Expanded(child: heading),
              const SizedBox(width: NoteFlowSpacing.md),
              createButton,
            ],
          );
        }
        return Padding(
          padding: const EdgeInsets.only(top: NoteFlowSpacing.xs),
          child: content,
        );
      },
    );
  }

  Widget _buildControls(BuildContext context, {bool includeLayout = true}) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool iconsOnly = constraints.maxWidth < 520;
        if (!includeLayout) {
          return Align(
            alignment: Alignment.centerLeft,
            child: _buildSortControl(context, iconsOnly: iconsOnly),
          );
        }
        return Wrap(
          spacing: NoteFlowSpacing.sm,
          runSpacing: NoteFlowSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            _buildSortControl(context, iconsOnly: iconsOnly),
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

  Widget _buildSortControl(
    BuildContext context, {
    required bool iconsOnly,
    Key? key,
  }) {
    return PopupMenuButton<DashboardSort>(
      key: key,
      tooltip: copy.sort,
      initialValue: sort,
      onSelected: onSortChanged,
      itemBuilder: (BuildContext context) => <PopupMenuEntry<DashboardSort>>[
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
              constraints: const BoxConstraints(minHeight: 48),
              padding: const EdgeInsets.symmetric(
                horizontal: NoteFlowSpacing.md,
              ),
              decoration: BoxDecoration(
                border: Border.all(
                  color: NoteFlowWorkspaceTokens.of(context).divider,
                ),
                borderRadius: BorderRadius.circular(NoteFlowRadius.input),
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
    );
  }

  Widget _buildSectionHeading(
    BuildContext context,
    String label, {
    double leadingInset = 0,
  }) {
    return Semantics(
      header: true,
      child: Padding(
        padding: EdgeInsets.only(left: leadingInset),
        child: Text(
          label,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: NoteFlowWorkspaceTokens.of(context).textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildRecentRail(
    BuildContext context,
    List<NoteDto> items,
    double viewportWidth,
  ) {
    final int count = items.length > 6 ? 6 : items.length;
    if (count == 0) {
      return const SizedBox.shrink();
    }
    final bool compact = viewportWidth < NoteFlowLayout.compactBreakpoint;
    final double cardWidth = compact ? 132 : 196;
    final double titleFontSize =
        Theme.of(context).textTheme.titleSmall?.fontSize ?? 14;
    final double titleScale =
        MediaQuery.textScalerOf(context).scale(titleFontSize) / titleFontSize;
    final double cardHeight = compact
        ? 132 + ((titleScale - 1).clamp(0.0, 1.0) * 8)
        : 160;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _buildSectionHeading(
          context,
          copy.recents,
          leadingInset: embeddedInWorkspace && viewportWidth < 600
              ? NoteFlowSpacing.xs
              : 0,
        ),
        const SizedBox(height: NoteFlowSpacing.sm + NoteFlowSpacing.xs),
        SizedBox(
          height: cardHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: count,
            separatorBuilder: (_, _) =>
                const SizedBox(width: NoteFlowSpacing.md),
            itemBuilder: (BuildContext context, int index) {
              final NoteDto note = items[index];
              final NoteFlowWorkspaceTokens tokens = NoteFlowWorkspaceTokens.of(
                context,
              );
              final String title = note.title.trim().isEmpty
                  ? copy.untitled
                  : note.title.trim();
              return SizedBox(
                width: cardWidth,
                child: Card(
                  margin: EdgeInsets.zero,
                  elevation: 0,
                  color: tokens.pageSurface,
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(NoteFlowRadius.card),
                    side: BorderSide(
                      color: NoteFlowWorkspaceTokens.of(context).divider,
                    ),
                  ),
                  child: InkWell(
                    onTap: () => onOpenNote(note),
                    child: Stack(
                      children: <Widget>[
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            Expanded(
                              child: ColoredBox(color: tokens.subtleSurface),
                            ),
                            Expanded(
                              child: ColoredBox(color: tokens.pageSurface),
                            ),
                          ],
                        ),
                        Positioned(
                          left: NoteFlowSpacing.md,
                          top: (cardHeight / 2) - 12,
                          child: Icon(
                            Icons.description_outlined,
                            size: 24,
                            color: tokens.textMuted,
                          ),
                        ),
                        Positioned(
                          left: NoteFlowSpacing.md,
                          right: NoteFlowSpacing.md,
                          top: (cardHeight / 2) + 19,
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildNoteCollection(
    BuildContext context,
    List<NoteDto> items,
    double viewportWidth,
  ) {
    final bool compact = viewportWidth < NoteFlowLayout.compactBreakpoint;
    if (searchOpen && searchOverlay && searchText.trim().isEmpty) {
      return items.isEmpty
          ? DashboardEmptyView(copy: copy, onCreateNote: onCreateNote)
          : _buildSearchResults(
              context,
              items,
              showResultsHeading: false,
              groupByDate: !compact,
              compact: compact,
            );
    }
    if (searchText.trim().isNotEmpty &&
        (searchOverlay ||
            layout == DashboardLayout.list ||
            (searchOpen && viewportWidth < NoteFlowLayout.compactBreakpoint))) {
      return _buildSearchResults(
        context,
        items,
        groupByDate: !compact,
        compact: compact,
      );
    }

    if (searchOverlay || layout == DashboardLayout.list) {
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
              onTogglePin: onTogglePin,
              showPreview: false,
            ),
            if (index < items.length - 1)
              const SizedBox(height: NoteFlowSpacing.sm),
          ],
        ],
      );
    }

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width = constraints.maxWidth;
        final int columns = _columnCount(width, viewportWidth);
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
                  onTogglePin: onTogglePin,
                  showPreview: false,
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildSearchResults(
    BuildContext context,
    List<NoteDto> items, {
    bool showResultsHeading = true,
    bool groupByDate = true,
    bool compact = false,
  }) {
    final Map<String, List<NoteDto>> groupedNotes = <String, List<NoteDto>>{};
    if (groupByDate) {
      final DateTime now = DateTime.now();
      for (final NoteDto note in items) {
        final DateTime updatedAt = note.updatedAt.toLocal();
        final int dayDifference = _calendarDayDifference(now, updatedAt);
        final String section = switch (dayDifference) {
          0 => copy.today,
          1 => copy.yesterday,
          _ => MaterialLocalizations.of(context).formatCompactDate(updatedAt),
        };
        groupedNotes.putIfAbsent(section, () => <NoteDto>[]).add(note);
      }
    } else if (items.isNotEmpty) {
      groupedNotes[''] = items;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (showResultsHeading) ...<Widget>[
          Row(
            children: <Widget>[
              Expanded(child: _buildSectionHeading(context, copy.results)),
              if (!dockCompactSearch && !searchOverlay)
                _buildSortControl(
                  context,
                  iconsOnly: true,
                  key: const ValueKey<String>('dashboard-search-sort'),
                ),
            ],
          ),
          SizedBox(
            height: compact
                ? NoteFlowSpacing.sm + NoteFlowSpacing.xs
                : NoteFlowSpacing.xs,
          ),
        ],
        for (final MapEntry<String, List<NoteDto>> section
            in groupedNotes.entries) ...<Widget>[
          if (groupByDate) ...<Widget>[
            _buildSectionHeading(context, section.key),
            const SizedBox(height: NoteFlowSpacing.sm),
          ],
          for (
            int index = 0;
            index < section.value.length;
            index++
          ) ...<Widget>[
            DashboardNoteCard(
              key: ValueKey<String>(
                'dashboard-note-${section.value[index].id}',
              ),
              note: section.value[index],
              copy: copy,
              layout: DashboardNoteCardLayout.list,
              selected: section.value[index].id == selectedNoteId,
              onTap: onOpenNote,
              onTogglePin: onTogglePin,
              showPreview: true,
              listHorizontalInset: compact ? 2 : NoteFlowSpacing.md,
              listIconGap: compact ? NoteFlowSpacing.lg : NoteFlowSpacing.md,
            ),
            if (index < section.value.length - 1)
              const SizedBox(height: NoteFlowSpacing.sm),
          ],
          if (groupByDate) const SizedBox(height: NoteFlowSpacing.lg),
        ],
      ],
    );
  }

  int _calendarDayDifference(DateTime today, DateTime date) {
    final DateTime todayDate = DateTime(today.year, today.month, today.day);
    final DateTime noteDate = DateTime(date.year, date.month, date.day);
    return todayDate.difference(noteDate).inDays;
  }

  int _columnCount(double width, double viewportWidth) {
    if (viewportWidth < NoteFlowLayout.expandedBreakpoint) {
      // Keep Grid meaningfully different from List at compact widths. The
      // List remains the single-column reading mode on phone and tablet.
      return 2;
    }
    const double gap = NoteFlowSpacing.md;
    const double minimumCardWidth = 136.0;
    return ((width + gap) / (minimumCardWidth + gap))
        .floor()
        .clamp(3, 4)
        .toInt();
  }
}
