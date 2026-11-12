import '../../application/labels/note_query.dart';
import '../../application/notes/note_page.dart';
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
import 'dashboard_native_search_empty.dart';
import 'dashboard_recent_rail.dart';
import 'dashboard_search_sections.dart';
import 'dashboard_search_viewport.dart';
import 'dashboard_state_views.dart';
import 'dashboard_view_models.dart';

part 'dashboard_content_search.dart';
part 'dashboard_content_controls.dart';
part 'dashboard_content_collection.dart';

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
    this.page,
    this.pageFooter,
    this.recentNotes,
  });

  final NotePage? page;
  final Widget? pageFooter;
  final List<NoteDto>? recentNotes;
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

  // A Web popup keeps its search composition when the host window narrows.
  // Native search still uses the existing compact dock.
  bool _compactLayout(BuildContext context) =>
      NoteFlowLayout.isCompact(context) && !(kIsWeb && searchOverlay);

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
    if (page != null) return notes;
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
    final bool compact = _compactLayout(context);
    final bool nativeSearch =
        !kIsWeb && compact && searchOpen && !searchOverlay;
    final bool showingDesktopSearchHistory =
        searchOpen && searchOverlay && !compact && searchText.trim().isEmpty;
    if (kIsWeb && searchOpen && searchOverlay) {
      return _buildWebSearch(context, filteredNotes, viewportWidth);
    }
    final content = RefreshIndicator(
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
                    : nativeSearch
                    ? double.infinity
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
                  nativeSearch
                      ? NoteFlowLayout.compactPageLeadingInsetFor(context)
                      : compact
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
                        _buildOverlaySearchFieldRow(context)
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
                        additionalChoices: page?.labelChoices,
                        selected: selectedLabels,
                        onChanged: onLabelsChanged!,
                        readable: _readable,
                        dense: compact,
                        singleLine: compact,
                      ),
                    if (searchOverlay && !compact)
                      _buildOverlaySearchFilters(context),
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
                      _buildRecentRail(
                        context,
                        page == null ? filteredNotes : recentNotes ?? notes,
                        viewportWidth,
                      ),
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
                        additionalChoices: page?.labelChoices,
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
                      nativeSearch
                          ? DashboardNativeSearchEmpty(
                              key: const ValueKey('dashboard-filtered-empty'),
                              copy: copy,
                              onClear: onClearSearch,
                            )
                          : DashboardFilteredEmptyView(
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
    if (pageFooter == null) return content;
    return Column(
      children: [
        Expanded(child: content),
        SafeArea(top: false, child: pageFooter!),
      ],
    );
  }
}
