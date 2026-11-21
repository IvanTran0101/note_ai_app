part of 'dashboard_content.dart';

extension _DashboardContentCollection on DashboardContent {
  Widget _buildSectionHeading(
    BuildContext context,
    String label, {
    double leadingInset = 0,
    bool subdued = false,
    bool compactHome = false,
    bool compactMobileSearch = false,
  }) {
    final bool muted = subdued || compactHome || compactMobileSearch;
    return Semantics(
      header: true,
      child: Padding(
        padding: EdgeInsets.only(left: leadingInset),
        child: Text(
          label,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: muted
                ? NoteFlowWorkspaceTokens.of(context).textMuted
                : NoteFlowWorkspaceTokens.of(context).textSecondary,
            fontSize: compactMobileSearch
                ? 14
                : subdued
                ? (dockCompactSearch ? 14 : 12)
                : compactHome
                ? 14
                : null,
            fontWeight: muted ? FontWeight.w400 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildRecentRail(
    BuildContext context,
    List<NoteDto> items,
    double viewportWidth,
  ) => DashboardRecentRail(
    notes: items,
    copy: copy,
    readable: _readable,
    onOpenNote: onOpenNote,
    embeddedInWorkspace: embeddedInWorkspace,
  );

  Widget _buildNoteCollection(
    BuildContext context,
    List<NoteDto> items,
    double viewportWidth,
  ) {
    final bool compact = _compactLayout(context);
    final bool compactHomeList =
        compact &&
        !searchOpen &&
        !searchOverlay &&
        layout == DashboardLayout.list;
    if (searchOpen && searchText.trim().isEmpty) {
      return items.isEmpty
          ? DashboardEmptyView(copy: copy, onCreateNote: onCreateNote)
          : _buildSearchResults(
              context,
              items,
              showResultsHeading: false,
              groupByDate: true,
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
              readable: _readable(items[index]),
              copy: copy,
              layout: DashboardNoteCardLayout.list,
              selected: items[index].id == selectedNoteId,
              onTap: onOpenNote,
              onTogglePin: onTogglePin,
              showPreview: false,
              compactHomeList: compactHomeList,
            ),
            if (index < items.length - 1 && !compactHomeList)
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
                  readable: _readable(note),
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
    final bool mobileSearch = compact && searchOpen && !searchOverlay;
    final bool nativeQuerySearch =
        mobileSearch && !kIsWeb && searchText.trim().isNotEmpty;
    final bool webQuerySearch =
        kIsWeb && searchOverlay && !compact && searchText.trim().isNotEmpty;
    final bool showDateSections = groupByDate && !webQuerySearch;
    final groupedNotes = showDateSections
        ? dashboardSearchSections(
            context,
            items,
            copy: copy,
            byCreatedAt: sort == DashboardSort.created,
          )
        : <String, List<NoteDto>>{if (items.isNotEmpty) '': items};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (showResultsHeading) ...<Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: _buildSectionHeading(
                  context,
                  copy.results,
                  compactMobileSearch: nativeQuerySearch,
                  subdued: webQuerySearch,
                ),
              ),
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
          if (showDateSections) ...<Widget>[
            _buildSectionHeading(context, section.key, subdued: true),
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
              readable: _readable(section.value[index]),
              copy: copy,
              layout: DashboardNoteCardLayout.list,
              selected: section.value[index].id == selectedNoteId,
              onTap: onOpenNote,
              onTogglePin: onTogglePin,
              showPreview: true,
              dense: searchOverlay && !compact,
              mobileSearch: mobileSearch,
              searchQueryResult: nativeQuerySearch,
              webQueryResult: webQuerySearch,
              listHorizontalInset: compact ? 2 : NoteFlowSpacing.md,
              listIconGap: compact
                  ? NoteFlowSpacing.lg
                  : searchOverlay
                  ? NoteFlowSpacing.sm
                  : NoteFlowSpacing.md,
            ),
            if (index < section.value.length - 1)
              mobileSearch
                  ? Divider(
                      height: 1,
                      thickness: 1,
                      color: NoteFlowWorkspaceTokens.of(context).divider,
                    )
                  : SizedBox(
                      height: searchOverlay && !compact
                          ? 0
                          : NoteFlowSpacing.sm,
                    ),
          ],
          if (showDateSections) const SizedBox(height: NoteFlowSpacing.lg),
        ],
      ],
    );
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
