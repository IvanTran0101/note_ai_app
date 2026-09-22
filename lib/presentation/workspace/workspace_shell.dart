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
/// * `< 600` — a compact top bar with the workspace title and a bottom-sheet
///   navigation menu; the active page fills the rest of the screen;
/// * `600–839` — an accessible [NavigationRail] with visible labels;
/// * `>= 840` — a Notion-inspired sidebar (collapsible to a slim icon rail)
///   with a workspace header, section label, active rows and a footer for the
///   optional settings/diagnostics actions.
class WorkspaceShell extends StatefulWidget {
  const WorkspaceShell({
    super.key,
    required this.dashboard,
    required this.notes,
    this.initialDestination = WorkspaceDestination.dashboard,
    this.onDestinationChanged,
    this.onOpenSettings,
    this.onOpenDiagnostics,
  });

  /// Width below which navigation chrome is hidden (compact). Inclusive lower
  /// bound of the medium layout.
  static const double compactBreakpoint = 600.0;

  /// Width at and above which the expanded sidebar replaces the rail.
  static const double expandedBreakpoint = 840.0;

  /// Expanded sidebar width, kept inside the 240–264dp Notion-like range.
  static const double sidebarWidth = 248.0;

  /// Width of the collapsed sidebar icon rail.
  static const double collapsedSidebarWidth = 56.0;

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

  /// Stable key for the medium [NavigationRail].
  static const Key navigationRailKey = ValueKey<String>(
    'workspace-navigation-rail',
  );

  /// Sidebar collapse/expand toggle.
  static const Key collapseToggleKey = ValueKey<String>(
    'workspace-collapse-toggle',
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
        if (width < WorkspaceShell.compactBreakpoint) {
          return _buildCompact(copy);
        }
        final Widget navigation = width < WorkspaceShell.expandedBreakpoint
            ? _buildNavigationRail(copy)
            : (_sidebarCollapsed
                  ? _buildCollapsedSidebar(copy)
                  : _buildSidebar(copy));
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            navigation,
            const VerticalDivider(width: 1.0, thickness: 1.0),
            Expanded(child: _buildPages()),
          ],
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

  Widget _buildCompact(WorkspaceCopy copy) {
    final NoteFlowUiTokens tokens = NoteFlowUiTokens.of(context);
    return Scaffold(
      backgroundColor: tokens.pageSurface,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _buildCompactTopBar(copy),
            const Divider(height: 1.0),
            Expanded(child: _buildPages()),
          ],
        ),
      ),
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
          if (widget.onOpenDiagnostics != null)
            IconButton(
              key: WorkspaceShell.diagnosticsKey,
              tooltip: copy.diagnostics,
              onPressed: widget.onOpenDiagnostics,
              icon: const Icon(Icons.bug_report_outlined, size: 20),
            ),
          if (widget.onOpenSettings != null)
            IconButton(
              key: WorkspaceShell.settingsKey,
              tooltip: copy.settings,
              onPressed: widget.onOpenSettings,
              icon: const Icon(Icons.settings_outlined, size: 20),
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
              NoteFlowSectionLabel(label: copy.navigationLabel),
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
                NoteFlowSectionLabel(label: copy.navigationLabel),
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
          Expanded(
            child: Text(
              copy.workspaceTitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: titleStyle?.copyWith(
                color: tokens.textSecondary,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4,
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
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: NoteFlowSpacing.sm,
        vertical: NoteFlowSpacing.sm,
      ),
      child: Row(
        children: <Widget>[
          if (widget.onOpenDiagnostics != null)
            IconButton(
              key: WorkspaceShell.diagnosticsKey,
              tooltip: copy.diagnostics,
              onPressed: widget.onOpenDiagnostics,
              icon: const Icon(Icons.bug_report_outlined, size: 20),
            ),
          if (widget.onOpenSettings != null)
            IconButton(
              key: WorkspaceShell.settingsKey,
              tooltip: copy.settings,
              onPressed: widget.onOpenSettings,
              icon: const Icon(Icons.settings_outlined, size: 20),
            ),
        ],
      ),
    );
  }

  Widget _buildCollapsedSidebar(WorkspaceCopy copy) {
    final NoteFlowUiTokens tokens = NoteFlowUiTokens.of(context);
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: copy.navigationLabel,
      child: SizedBox(
        width: WorkspaceShell.collapsedSidebarWidth,
        child: Material(
          color: tokens.sidebarSurface,
          child: SafeArea(
            right: false,
            child: Column(
              children: <Widget>[
                const SizedBox(height: NoteFlowSpacing.sm),
                IconButton(
                  key: WorkspaceShell.collapseToggleKey,
                  tooltip: copy.expandSidebar,
                  onPressed: () => setState(() => _sidebarCollapsed = false),
                  icon: const Icon(Icons.keyboard_double_arrow_right, size: 18),
                ),
                const SizedBox(height: NoteFlowSpacing.sm),
                for (final WorkspaceDestination destination
                    in WorkspaceDestination.values)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 2,
                      horizontal: NoteFlowSpacing.xs,
                    ),
                    child: IconButton(
                      key: WorkspaceShell.destinationKey(destination),
                      tooltip: _labelFor(copy, destination),
                      onPressed: () => showDestination(destination),
                      icon: Icon(
                        destination == _destination
                            ? _iconFor(destination, active: true)
                            : _iconFor(destination, active: false),
                        size: 20,
                      ),
                      style: IconButton.styleFrom(
                        backgroundColor: destination == _destination
                            ? tokens.selectedSurface
                            : Colors.transparent,
                        foregroundColor: destination == _destination
                            ? tokens.textPrimary
                            : tokens.textSecondary,
                      ),
                    ),
                  ),
                const Spacer(),
                if (widget.onOpenDiagnostics != null)
                  IconButton(
                    key: WorkspaceShell.diagnosticsKey,
                    tooltip: copy.diagnostics,
                    onPressed: widget.onOpenDiagnostics,
                    icon: const Icon(Icons.bug_report_outlined, size: 20),
                  ),
                if (widget.onOpenSettings != null)
                  IconButton(
                    key: WorkspaceShell.settingsKey,
                    tooltip: copy.settings,
                    onPressed: widget.onOpenSettings,
                    icon: const Icon(Icons.settings_outlined, size: 20),
                  ),
                const SizedBox(height: NoteFlowSpacing.sm),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
