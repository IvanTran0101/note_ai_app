import 'package:flutter/material.dart';

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
/// * `< 600` — the active page fills the screen with no navigation chrome;
/// * `600–839` — an accessible [NavigationRail] with visible labels;
/// * `>= 840` — a Notion-inspired sidebar with visible labels and an active
///   indicator.
class WorkspaceShell extends StatefulWidget {
  const WorkspaceShell({
    super.key,
    required this.dashboard,
    required this.notes,
    this.initialDestination = WorkspaceDestination.dashboard,
    this.onDestinationChanged,
  });

  /// Width below which navigation chrome is hidden (compact). Inclusive lower
  /// bound of the medium layout.
  static const double compactBreakpoint = 600.0;

  /// Width at and above which the expanded sidebar replaces the rail.
  static const double expandedBreakpoint = 840.0;

  /// Expanded sidebar width, kept inside the 240–264dp Notion-like range.
  static const double sidebarWidth = 248.0;

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
          return _buildPages();
        }
        final Widget navigation = width < WorkspaceShell.expandedBreakpoint
            ? _buildNavigationRail(copy)
            : _buildSidebar(copy);
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

  Widget _buildNavigationRail(WorkspaceCopy copy) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: copy.navigationLabel,
      child: NavigationRail(
        key: WorkspaceShell.navigationRailKey,
        backgroundColor: colors.surfaceContainerLow,
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
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSidebar(WorkspaceCopy copy) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextStyle? titleStyle = Theme.of(context).textTheme.titleSmall;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: copy.navigationLabel,
      child: SizedBox(
        key: WorkspaceShell.sidebarKey,
        width: WorkspaceShell.sidebarWidth,
        child: Material(
          color: colors.surfaceContainerLow,
          child: SafeArea(
            right: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20.0, 20.0, 20.0, 12.0),
                  child: Text(
                    copy.workspaceTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: titleStyle?.copyWith(
                      color: colors.onSurfaceVariant,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
                const Divider(height: 1.0),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(vertical: 12.0),
                    children: <Widget>[
                      for (final WorkspaceDestination destination
                          in WorkspaceDestination.values)
                        _WorkspaceSidebarTile(
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WorkspaceSidebarTile extends StatelessWidget {
  const _WorkspaceSidebarTile({
    super.key,
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final Color foreground = selected
        ? colors.onSecondaryContainer
        : colors.onSurface;
    final TextStyle? baseStyle = Theme.of(context).textTheme.labelLarge;
    return Semantics(
      button: true,
      selected: selected,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 2.0),
        child: Material(
          color: selected
              ? colors.secondaryContainer
              : colors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(10.0),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48.0),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12.0),
                child: Row(
                  children: <Widget>[
                    Icon(
                      selected ? selectedIcon : icon,
                      size: 20.0,
                      color: foreground,
                    ),
                    const SizedBox(width: 12.0),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: baseStyle?.copyWith(
                          color: foreground,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
