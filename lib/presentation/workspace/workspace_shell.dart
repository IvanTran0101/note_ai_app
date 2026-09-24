import 'package:flutter/material.dart';

import '../common/note_flow_primitives.dart';
import '../notes/notes_theme_tokens.dart';
import 'workspace_localizations.dart';

/// Top-level destinations owned by the workspace shell.
enum WorkspaceDestination { dashboard, notes }

/// Presentation-only shell that hosts the workspace pages and owns navigation
/// between [WorkspaceDestination.dashboard] and [WorkspaceDestination.notes].
///
/// The shell knows nothing about repositories, controllers, or business rules:
/// it only keeps both pages alive, switches between them, and reports the
/// active destination to the composition root through [onDestinationChanged].
/// Responsive behaviour is driven entirely by the incoming width:
///
/// * `< 600` — a compact brand/search bar and a bottom-sheet navigation menu
///   with the remaining workspace actions; the active page fills the screen;
/// * `600–839` — an accessible [NavigationRail] with visible labels;
/// * `>= 840` — a Notion-inspired sidebar (hideable to a narrow reopen control)
///   with a workspace header, section label, active rows and a footer for the
///   optional settings/diagnostics actions.
class WorkspaceShell extends StatefulWidget {
  const WorkspaceShell({
    super.key,
    required this.dashboard,
    required this.notes,
    this.initialDestination = WorkspaceDestination.dashboard,
    this.onDestinationChanged,
    this.onOpenSearch,
    this.onCreateNote,
    this.onOpenSettings,
    this.onOpenDiagnostics,
  });

  /// Width below which navigation chrome is hidden (compact). Inclusive lower
  /// bound of the medium layout.
  static const double compactBreakpoint = NoteFlowLayout.compactBreakpoint;

  /// Width at and above which the expanded sidebar replaces the rail.
  static const double expandedBreakpoint = NoteFlowLayout.expandedBreakpoint;

  /// Expanded sidebar width measured from the active Notion reference.
  static const double sidebarWidth = 280.0;

  /// Width used by the labelled medium navigation rail.
  static const double navigationRailWidth = 80.0;

  /// Size of the floating reopen control while the desktop sidebar is hidden.
  static const double collapsedSidebarWidth = 44.0;
  static const double collapsedSidebarTopInset = 44.0;

  /// Stable key for the Dashboard navigation item.
  static const Key dashboardDestinationKey = ValueKey<String>(
    'workspace-nav-dashboard',
  );

  /// Stable key for the Notes navigation item.
  static const Key notesDestinationKey = ValueKey<String>(
    'workspace-nav-notes',
  );

  /// Stable key for the expanded sidebar surface.
  static const Key sidebarKey = ValueKey<String>('workspace-sidebar');

  /// Stable key for the narrow sidebar reopen control.
  static const Key collapsedSidebarKey = ValueKey<String>(
    'workspace-collapsed-sidebar',
  );

  /// Stable key for the medium [NavigationRail].
  static const Key navigationRailKey = ValueKey<String>(
    'workspace-navigation-rail',
  );

  /// Sidebar collapse/expand toggle.
  static const Key collapseToggleKey = ValueKey<String>(
    'workspace-collapse-toggle',
  );

  static const Key sidebarSearchKey = ValueKey<String>(
    'workspace-sidebar-search',
  );
  static const Key sidebarNewNoteKey = ValueKey<String>(
    'workspace-sidebar-new-note',
  );
  static const Key compactSearchKey = ValueKey<String>(
    'workspace-compact-search',
  );
  static const Key compactNewNoteKey = ValueKey<String>(
    'workspace-compact-new-note',
  );
  static const Key compactMenuSearchKey = ValueKey<String>(
    'workspace-compact-menu-search',
  );
  static const Key compactMenuNewNoteKey = ValueKey<String>(
    'workspace-compact-menu-new-note',
  );

  /// Compact top-bar button opening the bottom-sheet navigation menu.
  static const Key compactMenuKey = ValueKey<String>('workspace-compact-menu');

  /// Footer/compact settings action.
  static const Key settingsKey = ValueKey<String>('workspace-open-settings');

  /// Footer/compact diagnostics action.
  static const Key diagnosticsKey = ValueKey<String>(
    'workspace-open-diagnostics',
  );

  /// Key for the navigation item that represents [destination].
  static Key destinationKey(WorkspaceDestination destination) {
    return switch (destination) {
      WorkspaceDestination.dashboard => dashboardDestinationKey,
      WorkspaceDestination.notes => notesDestinationKey,
    };
  }

  /// Page shown for the Dashboard destination.
  final Widget dashboard;

  /// Page shown for the Notes destination.
  final Widget notes;

  /// Destination selected on the first build.
  final WorkspaceDestination initialDestination;

  /// Called whenever the active destination actually changes.
  final ValueChanged<WorkspaceDestination>? onDestinationChanged;

  /// Opens the existing Dashboard search UI in the active page.
  final VoidCallback? onOpenSearch;

  /// Starts the existing NoteFlow create-note flow.
  final VoidCallback? onCreateNote;

  /// Optional appearance/settings action for the navigation footer.
  final VoidCallback? onOpenSettings;

  /// Optional local-AI diagnostics action for the navigation footer.
  final VoidCallback? onOpenDiagnostics;

  @override
  WorkspaceShellState createState() => WorkspaceShellState();
}

/// Public state for [WorkspaceShell].
///
/// Exposed so a composition root can hold a `GlobalKey<WorkspaceShellState>`
/// and call [showDestination] after an action elsewhere in the app (for
/// example, switching to Notes from a Dashboard call to action).
class WorkspaceShellState extends State<WorkspaceShell> {
  late WorkspaceDestination _destination = widget.initialDestination;
  bool _sidebarCollapsed = false;

  /// Destination currently shown by the shell.
  WorkspaceDestination get destination => _destination;

  /// Selects [destination], rebuilding the shell and notifying
  /// [WorkspaceShell.onDestinationChanged] when the selection changes.
  ///
  /// Safe to call from the composition root; selecting the already-active
  /// destination is a no-op so listeners are not re-notified.
  void showDestination(WorkspaceDestination destination) {
    if (_destination == destination) {
      return;
    }
    setState(() => _destination = destination);
    widget.onDestinationChanged?.call(destination);
  }

  int get _selectedIndex => switch (_destination) {
    WorkspaceDestination.dashboard => 0,
    WorkspaceDestination.notes => 1,
  };

  String _labelFor(WorkspaceCopy copy, WorkspaceDestination destination) {
    return switch (destination) {
      WorkspaceDestination.dashboard => copy.dashboard,
      WorkspaceDestination.notes => copy.notes,
    };
  }

  IconData _iconFor(WorkspaceDestination destination, {required bool active}) {
    return switch (destination) {
      WorkspaceDestination.dashboard =>
        active ? Icons.dashboard : Icons.dashboard_outlined,
      WorkspaceDestination.notes =>
        active ? Icons.description : Icons.description_outlined,
    };
  }

  @override
  Widget build(BuildContext context) {
    final WorkspaceCopy copy = WorkspaceCopy.of(context);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width = constraints.maxWidth;
        final bool compact = width < WorkspaceShell.compactBreakpoint;
        final bool medium = width < WorkspaceShell.expandedBreakpoint;
        final bool collapsedDesktop = !compact && !medium && _sidebarCollapsed;
        final Widget? navigation = compact
            ? null
            : medium
            ? _buildNavigationRail(copy)
            : _sidebarCollapsed
            ? null
            : _buildSidebar(copy);
        final double navigationWidth = compact || collapsedDesktop
            ? 0
            : medium
            ? WorkspaceShell.navigationRailWidth
            : WorkspaceShell.sidebarWidth;
        final double dividerWidth = compact || collapsedDesktop ? 0 : 1;
        final NoteFlowUiTokens tokens = NoteFlowUiTokens.of(context);

        // Keep the page stack at the same element path at every width. Moving
        // it between a compact Scaffold/Column and an expanded Row used to
        // dispose an active editor, losing its unsaved draft on resize.
        return Scaffold(
          backgroundColor: tokens.pageSurface,
          body: SafeArea(
            top: compact,
            left: compact,
            right: compact,
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                SizedBox(
                  height: compact ? 44 : 0,
                  child: compact
                      ? _buildCompactTopBar(copy)
                      : const SizedBox.shrink(),
                ),
                SizedBox(
                  height: compact ? 1 : 0,
                  child: compact
                      ? const Divider(height: 1)
                      : const SizedBox.shrink(),
                ),
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          SizedBox(
                            width: navigationWidth,
                            child: navigation ?? const SizedBox.shrink(),
                          ),
                          SizedBox(
                            width: dividerWidth,
                            child: dividerWidth == 0
                                ? const SizedBox.shrink()
                                : const VerticalDivider(width: 1, thickness: 1),
                          ),
                          Expanded(child: _buildPages()),
                        ],
                      ),
                      if (collapsedDesktop)
                        Positioned(
                          left: 0,
                          top: WorkspaceShell.collapsedSidebarTopInset,
                          child: _buildCollapsedSidebar(copy),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Both pages stay mounted so switching preserves their state.
  Widget _buildPages() {
    return IndexedStack(
      index: _selectedIndex,
      sizing: StackFit.expand,
      children: <Widget>[widget.dashboard, widget.notes],
    );
  }

  Widget _buildCompactTopBar(WorkspaceCopy copy) {
    final NoteFlowUiTokens tokens = NoteFlowUiTokens.of(context);
    final TextStyle? titleStyle = Theme.of(context).textTheme.titleSmall;
    return SizedBox(
      height: 44,
      child: Row(
        children: <Widget>[
          IconButton(
            key: WorkspaceShell.compactMenuKey,
            tooltip: copy.openMenu,
            onPressed: () => _showCompactMenu(copy),
            icon: const Icon(Icons.menu, size: 22),
          ),
          Expanded(
            child: Text(
              copy.workspaceTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: titleStyle?.copyWith(
                color: tokens.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (widget.onOpenSearch != null)
            IconButton(
              key: WorkspaceShell.compactSearchKey,
              tooltip: copy.search,
              onPressed: widget.onOpenSearch,
              icon: const Icon(Icons.search, size: 20),
            ),
        ],
      ),
    );
  }

  Future<void> _showCompactMenu(WorkspaceCopy copy) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) {
        return NoteFlowSurface(
          tone: NoteFlowSurfaceTone.elevated,
          padding: const EdgeInsets.fromLTRB(
            NoteFlowSpacing.sm,
            0,
            NoteFlowSpacing.sm,
            NoteFlowSpacing.xl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (widget.onOpenSearch != null)
                NoteFlowSidebarRow(
                  key: WorkspaceShell.compactMenuSearchKey,
                  label: copy.search,
                  icon: Icons.search,
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    widget.onOpenSearch?.call();
                  },
                ),
              if (widget.onCreateNote != null)
                KeyedSubtree(
                  key: WorkspaceShell.compactNewNoteKey,
                  child: NoteFlowSidebarRow(
                    key: WorkspaceShell.compactMenuNewNoteKey,
                    label: copy.newNote,
                    icon: Icons.add,
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      widget.onCreateNote?.call();
                    },
                  ),
                ),
              NoteFlowSectionLabel(label: copy.pagesSection),
              for (final WorkspaceDestination destination
                  in WorkspaceDestination.values)
                NoteFlowSidebarRow(
                  key: WorkspaceShell.destinationKey(destination),
                  label: _labelFor(copy, destination),
                  icon: _iconFor(destination, active: false),
                  selectedIcon: _iconFor(destination, active: true),
                  selected: destination == _destination,
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    showDestination(destination);
                  },
                ),
              if (widget.onOpenSettings != null ||
                  widget.onOpenDiagnostics != null) ...<Widget>[
                const Divider(height: NoteFlowSpacing.lg),
                if (widget.onOpenDiagnostics != null)
                  NoteFlowSidebarRow(
                    key: WorkspaceShell.diagnosticsKey,
                    label: copy.diagnostics,
                    icon: Icons.bug_report_outlined,
                    dense: true,
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      widget.onOpenDiagnostics?.call();
                    },
                  ),
                if (widget.onOpenSettings != null)
                  NoteFlowSidebarRow(
                    key: WorkspaceShell.settingsKey,
                    label: copy.settings,
                    icon: Icons.settings_outlined,
                    dense: true,
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      widget.onOpenSettings?.call();
                    },
                  ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildNavigationRail(WorkspaceCopy copy) {
    final NoteFlowUiTokens tokens = NoteFlowUiTokens.of(context);
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: copy.navigationLabel,
      child: NavigationRail(
        key: WorkspaceShell.navigationRailKey,
        backgroundColor: tokens.sidebarSurface,
        selectedIndex: _selectedIndex,
        labelType: NavigationRailLabelType.all,
        scrollable: true,
        onDestinationSelected: (int index) {
          showDestination(WorkspaceDestination.values[index]);
        },
        destinations: <NavigationRailDestination>[
          for (final WorkspaceDestination destination
              in WorkspaceDestination.values)
            NavigationRailDestination(
              icon: Icon(_iconFor(destination, active: false)),
              selectedIcon: Icon(_iconFor(destination, active: true)),
              label: Text(
                _labelFor(copy, destination),
                key: WorkspaceShell.destinationKey(destination),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSidebar(WorkspaceCopy copy) {
    final NoteFlowUiTokens tokens = NoteFlowUiTokens.of(context);
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: copy.navigationLabel,
      child: SizedBox(
        key: WorkspaceShell.sidebarKey,
        width: WorkspaceShell.sidebarWidth,
        child: Material(
          color: tokens.sidebarSurface,
          child: SafeArea(
            right: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _buildSidebarHeader(copy),
                const Divider(height: 1.0),
                if (widget.onOpenSearch != null || widget.onCreateNote != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      NoteFlowSpacing.sm,
                      NoteFlowSpacing.xs,
                      NoteFlowSpacing.sm,
                      NoteFlowSpacing.sm,
                    ),
                    child: Column(
                      children: <Widget>[
                        if (widget.onOpenSearch != null)
                          NoteFlowSidebarRow(
                            key: WorkspaceShell.sidebarSearchKey,
                            label: copy.search,
                            icon: Icons.search,
                            dense: true,
                            onTap: widget.onOpenSearch,
                          ),
                        if (widget.onCreateNote != null)
                          NoteFlowSidebarRow(
                            key: WorkspaceShell.sidebarNewNoteKey,
                            label: copy.newNote,
                            icon: Icons.add,
                            dense: true,
                            onTap: widget.onCreateNote,
                          ),
                      ],
                    ),
                  ),
                NoteFlowSectionLabel(label: copy.pagesSection),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(
                      vertical: NoteFlowSpacing.xs,
                    ),
                    children: <Widget>[
                      for (final WorkspaceDestination destination
                          in WorkspaceDestination.values)
                        NoteFlowSidebarRow(
                          key: WorkspaceShell.destinationKey(destination),
                          label: _labelFor(copy, destination),
                          icon: _iconFor(destination, active: false),
                          selectedIcon: _iconFor(destination, active: true),
                          selected: destination == _destination,
                          onTap: () => showDestination(destination),
                        ),
                    ],
                  ),
                ),
                _buildSidebarFooter(copy),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSidebarHeader(WorkspaceCopy copy) {
    final NoteFlowUiTokens tokens = NoteFlowUiTokens.of(context);
    final TextStyle? titleStyle = Theme.of(context).textTheme.titleSmall;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        NoteFlowSpacing.lg,
        NoteFlowSpacing.md,
        NoteFlowSpacing.xs,
        NoteFlowSpacing.xs,
      ),
      child: Row(
        children: <Widget>[
          Semantics(
            excludeSemantics: true,
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: tokens.selectedSurface,
                borderRadius: BorderRadius.circular(NoteFlowRadius.row),
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.description_outlined,
                size: 16,
                color: tokens.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: NoteFlowSpacing.sm),
          Expanded(
            child: Text(
              copy.workspaceTitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: titleStyle?.copyWith(
                color: tokens.textSecondary,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.1,
              ),
            ),
          ),
          IconButton(
            key: WorkspaceShell.collapseToggleKey,
            tooltip: copy.collapseSidebar,
            onPressed: () => setState(() => _sidebarCollapsed = true),
            icon: const Icon(Icons.keyboard_double_arrow_left, size: 18),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarFooter(WorkspaceCopy copy) {
    if (widget.onOpenSettings == null && widget.onOpenDiagnostics == null) {
      return const SizedBox.shrink();
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: NoteFlowSpacing.sm,
            vertical: NoteFlowSpacing.sm,
          ),
          child: Column(
            children: <Widget>[
              if (widget.onOpenDiagnostics != null)
                NoteFlowSidebarRow(
                  key: WorkspaceShell.diagnosticsKey,
                  label: copy.diagnostics,
                  icon: Icons.bug_report_outlined,
                  onTap: widget.onOpenDiagnostics,
                  dense: true,
                ),
              if (widget.onOpenSettings != null)
                NoteFlowSidebarRow(
                  key: WorkspaceShell.settingsKey,
                  label: copy.settings,
                  icon: Icons.settings_outlined,
                  onTap: widget.onOpenSettings,
                  dense: true,
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCollapsedSidebar(WorkspaceCopy copy) {
    final NoteFlowUiTokens tokens = NoteFlowUiTokens.of(context);
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: copy.navigationLabel,
      child: SizedBox(
        key: WorkspaceShell.collapsedSidebarKey,
        width: WorkspaceShell.collapsedSidebarWidth,
        height: WorkspaceShell.collapsedSidebarWidth,
        child: Material(
          color: tokens.pageSurface,
          child: IconButton(
            key: WorkspaceShell.collapseToggleKey,
            tooltip: copy.expandSidebar,
            onPressed: () => setState(() => _sidebarCollapsed = false),
            icon: const Icon(Icons.keyboard_double_arrow_right, size: 18),
            style: IconButton.styleFrom(
              minimumSize: Size.square(WorkspaceShell.collapsedSidebarWidth),
              maximumSize: Size.square(WorkspaceShell.collapsedSidebarWidth),
              padding: EdgeInsets.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ),
      ),
    );
  }
}
