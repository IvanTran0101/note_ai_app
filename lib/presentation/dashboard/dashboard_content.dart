import '../../application/labels/note_query.dart';
import '../labels/label_catalog_scope.dart';
import '../labels/label_filter_bar.dart';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../application/dashboard/dashboard_overview.dart';
import '../../application/notes/note_application.dart';
import '../notes/note_ordering.dart';
import '../notes/notes_theme_tokens.dart';
import '../workspace/workspace_ui_tokens.dart';
import 'dashboard_localizations.dart';
import 'dashboard_note_card.dart';
import 'dashboard_recent_rail.dart';
import 'dashboard_search_sections.dart';
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
    this.selectedLabels = const {},
    this.onLabelsChanged,
    this.readable,
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

  final Set<LabelSelection> selectedLabels;
  final ValueChanged<Set<LabelSelection>>? onLabelsChanged;
  final bool Function(NoteDto)? readable;
  bool _readable(NoteDto n) =>
      readable?.call(n) ?? (!n.isProtected && n.contentAvailable);

  List<NoteDto> get visibleNotes {
    return sortNotes(
      queryNotes(
        notes,
        keyword: searchText,
        readable: _readable,
        labelsFor: (_) => const [],
      ),
      byCreatedAt: sort == DashboardSort.created,
    );
  }

  List<NoteDto> _filtered(BuildContext context) {
    final scope = LabelCatalogScope.maybeOf(context);
    return sortNotes(
      queryNotes(
        notes,
        keyword: searchText,
        selected: selectedLabels,
        readable: _readable,
        labelsFor: (n) => visibleLabels(
          n,
          scope?.labels ?? const [],
          actor: scope?.actor ?? '',
          readable: _readable(n),
        ),
      ),
      byCreatedAt: sort == DashboardSort.created,
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<NoteDto> filteredNotes = _filtered(context);
    final double viewportWidth = MediaQuery.sizeOf(context).width;
    final bool compact = NoteFlowLayout.isCompact(context);
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
                    ? 600
                    : compact
                    ? NoteFlowLayout.compactPageFrameMaxWidthFor(context)
                    : NoteFlowLayout.dashboardContentMaxWidth,
              ),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  compact
                      ? NoteFlowLayout.compactPageLeadingInsetFor(context)
                      : searchOverlay
                      ? NoteFlowSpacing.md
                      : NoteFlowSpacing.xl,
                  compact
                      ? embeddedInWorkspace
                            ? searchOpen
                                  ? NoteFlowSpacing.xl
                                  : 18
                            : NoteFlowLayout.compactPageTopInset(context)
                      : searchOverlay
                      ? NoteFlowSpacing.sm
                      : NoteFlowLayout.dashboardTopPadding,
                  compact
                      ? NoteFlowSpacing.lg
                      : searchOverlay
                      ? NoteFlowSpacing.md
                      : NoteFlowSpacing.xl,
                  searchOverlay ? NoteFlowSpacing.lg : NoteFlowSpacing.xxxl,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    if (searchOpen) ...<Widget>[
                      if (searchOverlay && !compact)
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: _buildSearchField(
                                context,
                                desktopOverlay: true,
                              ),
                            ),
                            if (onCloseSearch != null)
                              IconButton(
                                key: const ValueKey<String>(
                                  'dashboard-search-close',
                                ),
                                tooltip: copy.closeSearch,
                                onPressed: onCloseSearch,
                                constraints: const BoxConstraints(
                                  minWidth: 40,
                                  minHeight: 40,
                                ),
                                padding: EdgeInsets.zero,
                                iconSize: 20,
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
                        SizedBox(
                          height: searchOverlay && !compact
                              ? 0
                              : NoteFlowSpacing.sm,
                        ),
                      ],
                    ],
                    if (searchOpen &&
                        !(searchOverlay && !compact) &&
                        onLabelsChanged != null)
                      LabelFilterBar(
                        notes: notes,
                        selected: selectedLabels,
                        onChanged: onLabelsChanged!,
                        readable: _readable,
                        dense: compact,
                        singleLine: compact,
                      ),
                    if (searchOverlay && !compact)
                      Padding(
                        padding: EdgeInsets.zero,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: onLabelsChanged == null
                                  ? const SizedBox.shrink()
                                  : LabelFilterBar(
                                      notes: notes,
                                      selected: selectedLabels,
                                      onChanged: onLabelsChanged!,
                                      readable: _readable,
                                      dense: true,
                                    ),
                            ),
                            const SizedBox(width: 12),
                            _buildSortControl(context, iconsOnly: false),
                          ],
                        ),
                      ),
                    if ((!compact || !embeddedInWorkspace) && !searchOpen)
                      _buildHeader(context),
                    if (searchOpen && dockCompactSearch) ...<Widget>[
                      const SizedBox(height: NoteFlowSpacing.lg),
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
                                compactHome: compact && !searchOpen,
                              ),
                            ),
                            const SizedBox(width: NoteFlowSpacing.xs),
                            SizedBox(
                              width: 200,
                              child: _buildControls(
                                context,
                                includeLayout: !searchOverlay,
                                compactHome: compact && !searchOpen,
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
                              compactHome: !searchOpen,
                            ),
                            const SizedBox(height: NoteFlowSpacing.xs),
                            _buildControls(
                              context,
                              includeLayout: !searchOverlay,
                              compactHome: !searchOpen,
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
                    ] else if ((!searchOpen || !compact) &&
                        !searchOverlay) ...<Widget>[
                      SizedBox(
                        height: searchOverlay
                            ? NoteFlowSpacing.md
                            : NoteFlowSpacing.xl,
                      ),
                      _buildControls(context, includeLayout: !searchOverlay),
                    ],
                    if (onLabelsChanged != null && !searchOpen)
                      LabelFilterBar(
                        notes: notes,
                        selected: selectedLabels,
                        onChanged: onLabelsChanged!,
                        readable: _readable,
                        dense: compact,
                        singleLine: compact,
                      ),
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

  Widget _buildSearchField(
    BuildContext context, {
    bool desktopOverlay = false,
  }) {
    final NoteFlowWorkspaceTokens tokens = NoteFlowWorkspaceTokens.of(context);
    final OutlineInputBorder searchBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(desktopOverlay ? 20 : 28),
      borderSide: BorderSide(color: tokens.divider),
    );
    return TextField(
      key: const ValueKey<String>('dashboard-search-field'),
      controller: searchController,
      autofocus: true,
      onChanged: onSearchChanged,
      decoration: InputDecoration(
        isDense: desktopOverlay,
        hintText: copy.searchNotes,
        filled: !desktopOverlay,
        fillColor: tokens.subtleSurface,
        prefixIcon: Icon(
          Icons.search,
          size: desktopOverlay ? 18 : 20,
          color: tokens.textMuted,
        ),
        prefixIconConstraints: desktopOverlay
            ? const BoxConstraints(minWidth: 40, minHeight: 40)
            : null,
        suffixIcon: searchText.isEmpty
            ? null
            : IconButton(
                key: const ValueKey<String>('dashboard-clear-search-field'),
                tooltip: copy.clearSearch,
                icon: const Icon(Icons.clear),
                onPressed: onClearSearch,
              ),
        contentPadding: EdgeInsets.symmetric(
          horizontal: desktopOverlay ? 0 : NoteFlowSpacing.md,
          vertical: desktopOverlay ? 8 : NoteFlowSpacing.md,
        ),
        border: desktopOverlay ? InputBorder.none : searchBorder,
        enabledBorder: desktopOverlay
            ? InputBorder.none
            : searchBorder.copyWith(
                borderSide: BorderSide(color: tokens.divider),
              ),
        focusedBorder: desktopOverlay
            ? InputBorder.none
            : searchBorder.copyWith(
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
      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
        color: tokens.textPrimary,
        fontSize: NoteFlowLayout.isNativePhone(context)
            ? 28
            : compact
            ? 32
            : null,
        fontWeight: FontWeight.w700,
      ),
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

  Widget _buildControls(
    BuildContext context, {
    bool includeLayout = true,
    bool compactHome = false,
  }) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool iconsOnly = constraints.maxWidth < 520;
        final tokens = NoteFlowUiTokens.of(context);
        if (!includeLayout) {
          return Align(
            alignment: Alignment.centerLeft,
            child: _buildSortControl(context, iconsOnly: iconsOnly),
          );
        }
        return Wrap(
          spacing: compactHome ? NoteFlowSpacing.xs : NoteFlowSpacing.sm,
          runSpacing: compactHome ? NoteFlowSpacing.xs : NoteFlowSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            _buildSortControl(context, iconsOnly: iconsOnly),
            SegmentedButton<DashboardLayout>(
              key: const ValueKey<String>('dashboard-layout-toggle'),
              style: ButtonStyle(
                backgroundColor: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.selected)
                      ? tokens.textPrimary.withValues(alpha: .07)
                      : Colors.transparent,
                ),
                foregroundColor: WidgetStatePropertyAll(tokens.textSecondary),
                side: WidgetStatePropertyAll(BorderSide(color: tokens.divider)),
                iconSize: const WidgetStatePropertyAll(18),
                minimumSize: WidgetStatePropertyAll<Size?>(
                  Size(48, compactHome ? 48 : 32),
                ),
                padding: const WidgetStatePropertyAll<EdgeInsetsGeometry?>(
                  EdgeInsets.zero,
                ),
                tapTargetSize: compactHome
                    ? MaterialTapTargetSize.padded
                    : MaterialTapTargetSize.shrinkWrap,
              ),
              segments: <ButtonSegment<DashboardLayout>>[
                ButtonSegment<DashboardLayout>(
                  value: DashboardLayout.list,
                  label: iconsOnly ? const SizedBox.shrink() : Text(copy.list),
                  icon: const Icon(Icons.view_list_outlined),
                  tooltip: copy.list,
                ),
                ButtonSegment<DashboardLayout>(
                  value: DashboardLayout.grid,
                  label: iconsOnly ? const SizedBox.shrink() : Text(copy.grid),
                  icon: const Icon(Icons.grid_view_outlined),
                  tooltip: copy.grid,
                ),
              ],
              selected: <DashboardLayout>{layout},
              showSelectedIcon: !iconsOnly,
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
              constraints: BoxConstraints(minHeight: searchOverlay ? 36 : 48),
              padding: EdgeInsets.symmetric(
                horizontal: searchOverlay ? 8 : NoteFlowSpacing.md,
              ),
              decoration: BoxDecoration(
                border: searchOverlay
                    ? null
                    : Border.all(
                        color: NoteFlowWorkspaceTokens.of(context).divider,
                      ),
                borderRadius: BorderRadius.circular(NoteFlowRadius.input),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(Icons.sort, size: searchOverlay ? 16 : 20),
                  SizedBox(width: searchOverlay ? 4 : NoteFlowSpacing.sm),
                  Text(
                    sort == DashboardSort.updated
                        ? copy.sortUpdated
                        : copy.sortCreated,
                    style: searchOverlay
                        ? Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                            color: NoteFlowWorkspaceTokens.of(context)
                                .textSecondary,
                          )
                        : null,
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
    final bool compact = NoteFlowLayout.isCompact(context);
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
    final groupedNotes = groupByDate
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
          if (groupByDate) ...<Widget>[
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
          if (groupByDate) const SizedBox(height: NoteFlowSpacing.lg),
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
