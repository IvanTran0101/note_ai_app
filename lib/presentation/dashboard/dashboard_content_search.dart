part of 'dashboard_content.dart';

extension _DashboardContentSearch on DashboardContent {
  Widget _buildOverlaySearchFieldRow(BuildContext context) => Row(
    children: <Widget>[
      Expanded(child: _buildSearchField(context, desktopOverlay: true)),
      if (onCloseSearch != null)
        IconButton(
          key: const ValueKey<String>('dashboard-search-close'),
          tooltip: copy.closeSearch,
          onPressed: onCloseSearch,
          constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          padding: EdgeInsets.zero,
          iconSize: 20,
          icon: const Icon(Icons.close),
        ),
    ],
  );

  Widget _buildOverlaySearchFilters(BuildContext context) => Padding(
    padding: EdgeInsets.zero,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: onLabelsChanged == null
              ? const SizedBox.shrink()
              : LabelFilterBar(
                  notes: notes,
                  additionalChoices: page?.labelChoices,
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
  );

  Widget _buildWebSearch(
    BuildContext context,
    List<NoteDto> filteredNotes,
    double viewportWidth,
  ) {
    final empty = filteredNotes.isEmpty && searchText.trim().isNotEmpty;
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: DashboardSearchViewport(
        header: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildOverlaySearchFieldRow(context),
              _buildOverlaySearchFilters(context),
              if (hasError) ...[
                const SizedBox(height: NoteFlowSpacing.lg),
                DashboardInlineError(copy: copy, onRetry: onRetry),
              ],
            ],
          ),
        ),
        centerBody: empty,
        body: Padding(
          padding: EdgeInsets.fromLTRB(empty ? 16 : 12, 0, 16, empty ? 0 : 16),
          child: empty
              ? DashboardSearchEmptyState(copy: copy, onClear: onClearSearch)
              : _buildNoteCollection(context, filteredNotes, viewportWidth),
        ),
        footer: Column(
          mainAxisSize: MainAxisSize.min,
          children: [?pageFooter, _buildSearchFooter(context)],
        ),
      ),
    );
  }

  Widget _buildSearchFooter(BuildContext context) {
    final tokens = NoteFlowWorkspaceTokens.of(context);
    return Container(
      key: const ValueKey('dashboard-search-footer'),
      constraints: const BoxConstraints(minHeight: 42),
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: tokens.divider)),
      ),
      child: Text(
        'Esc Ã‚Â· ${copy.closeSearch}',
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(fontSize: 11, color: tokens.textMuted),
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
}
