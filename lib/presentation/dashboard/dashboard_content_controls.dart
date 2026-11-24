part of 'dashboard_content.dart';

extension _DashboardContentControls on DashboardContent {
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
}
