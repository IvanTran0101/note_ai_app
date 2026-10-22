import 'package:flutter/material.dart';

import '../common/note_flow_primitives.dart';
import '../common/note_flow_header_inset.dart';
import '../notes/notes_theme_tokens.dart';
import 'workspace_localizations.dart';
import 'workspace_ui_tokens.dart';

/// Top-level destinations owned by the workspace shell.
enum WorkspaceDestination { dashboard, notes }

/// Presentation-only shell that hosts the workspace pages and owns navigation
/// between [WorkspaceDestination.dashboard] and [WorkspaceDestination.notes].
///
/// The shell knows nothing about repositories, controllers, or business rules:
/// it only keeps both pages alive, switches between them, and reports the
/// active destination to the composition root through [onDestinationChanged].
/// Responsive behaviour uses width and retains mobile layout on rotated phones:
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
    this.onOpenRag,
    this.accountName,
    this.accountAvatar,
  });

  /// Width below which navigation chrome is hidden (compact). Inclusive lower
  /// bound of the medium layout.
  static const double compactBreakpoint = NoteFlowLayout.compactBreakpoint;

  /// Width at and above which the expanded sidebar replaces the rail.
  static const double expandedBreakpoint = NoteFlowLayout.expandedBreakpoint;

  /// Expanded sidebar width measured from the active Notion reference.
  static const double sidebarWidth = 270.0;

  /// Width used by the labelled medium navigation rail.
  static const double navigationRailWidth = 80.0;

  /// Size of the floating reopen control while the desktop sidebar is hidden.
  static const double collapsedSidebarWidth = 44.0;
  static const double collapsedSidebarTopInset = 0.0;

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
  static const Key compactFabNewNoteKey = ValueKey<String>(
    'workspace-compact-fab-new-note',
  );
  static const Key compactBottomNavigationKey = ValueKey<String>(
    'workspace-compact-bottom-navigation',
  );
  static const Key compactBrandKey = ValueKey<String>(
    'workspace-compact-brand-home',
  );
  static const Key notionBrandMarkKey = ValueKey<String>('notion-brand-mark');
  static const String notionBrandAsset = 'assets/branding/notion-logo.png';
  static const Key compactMenuSearchKey = ValueKey<String>(
    'workspace-compact-menu-search',
  );
  static const Key compactMenuNewNoteKey = ValueKey<String>(
    'workspace-compact-menu-new-note',
  );

  /// Compact top-bar button opening the bottom-sheet navigation menu.
  static const Key compactMenuKey = ValueKey<String>('workspace-compact-menu');

  /// Stable key for the compact account/avatar control.
  static const Key compactAvatarKey = ValueKey<String>(
    'workspace-compact-avatar',
  );

  /// Footer/compact settings action.
  static const Key settingsKey = ValueKey<String>('workspace-open-settings');

  /// Footer/compact diagnostics action.
  static const Key diagnosticsKey = ValueKey<String>(
    'workspace-open-diagnostics',
  );

  /// Account-wide "ask my notes" action in the sidebar and compact menu.
  static const Key askNotesKey = ValueKey<String>('workspace-open-rag');

  /// Account-wide "ask my notes" action in the compact navigation menu.
  static const Key compactMenuAskNotesKey = ValueKey<String>(
    'workspace-compact-menu-ask-notes',
  );

  /// Account-wide "ask my notes" action in the medium navigation rail.
  static const Key railAskNotesKey = ValueKey<String>(
    'workspace-rail-ask-notes',
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

  /// Optional account-wide "ask my notes" action. Supplied by the composition
  /// root only when the RAG endpoint/feature is configured; it is not a new
  /// destination and adds no shell state.
  final VoidCallback? onOpenRag;

  /// Display name used for the compact avatar initial. Email/local identity
  /// may be supplied by the composition root when no profile image exists.
  final String? accountName;
  final ImageProvider? accountAvatar;

  @override
  WorkspaceShellState createState() => WorkspaceShellState();
}

/// Public state for [WorkspaceShell].
///
/// Exposed so a composition root can hold a `GlobalKey<WorkspaceShellState>`
/// and call [showDestination] after an action elsewhere in the app (for
/// example, switching to Notes from a Dashboard call to action).
class WorkspaceShellState extends State<WorkspaceShell>
    with SingleTickerProviderStateMixin {
  late WorkspaceDestination _destination = widget.initialDestination;
  bool _sidebarCollapsed = false;
  bool _compactSearchActive = false;
  bool _noteEditorActive = false;
  late final AnimationController _pageMotionController = AnimationController(
    vsync: this,
    duration: NoteFlowMotion.standard,
  )..value = 1;
  double _pageTravel = 0;
  double _horizontalSwipeDistance = 0;
  bool _pointerSwipeHandled = false;

  /// Destination currently shown by the shell.
  WorkspaceDestination get destination => _destination;

  /// Hides compact workspace chrome while the Dashboard is in its dedicated
  /// search state. The search page owns its own heading and close affordance.
  void setCompactSearchActive(bool active) {
    if (_compactSearchActive == active) {
      return;
    }
    setState(() => _compactSearchActive = active);
  }

  /// The note already owns Back and page actions while its editor is open.
  void setNoteEditorActive(bool active) {
    if (!mounted || _noteEditorActive == active) return;
    setState(() => _noteEditorActive = active);
  }

  /// Selects [destination], rebuilding the shell and notifying
  /// [WorkspaceShell.onDestinationChanged] when the selection changes.
  ///
  /// Safe to call from the composition root; selecting the already-active
  /// destination is a no-op so listeners are not re-notified.
  void showDestination(WorkspaceDestination destination) {
    if (_destination == destination) {
      return;
    }
    _pageTravel = _destinationIndex(destination) > _selectedIndex
        ? 0.035
        : -0.035;
    setState(() => _destination = destination);
    if (MediaQuery.disableAnimationsOf(context)) {
      _pageMotionController.value = 1;
    } else {
      _pageMotionController.forward(from: 0);
    }
    widget.onDestinationChanged?.call(destination);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _pageMotionController.duration = NoteFlowMotion.duration(context);
    if (MediaQuery.disableAnimationsOf(context)) {
      _pageMotionController.value = 1;
    }
  }

  int _destinationIndex(WorkspaceDestination destination) =>
      switch (destination) {
        WorkspaceDestination.dashboard => 0,
        WorkspaceDestination.notes => 1,
      };

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
        active ? Icons.home_filled : Icons.home_outlined,
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
        final bool compact = NoteFlowLayout.isCompact(
          context,
          availableWidth: width,
        );
        final bool compactEditor =
            compact &&
            _destination == WorkspaceDestination.notes &&
            _noteEditorActive;
        final bool compactBottomBarVisible =
            compact &&
            !_compactSearchActive &&
            (widget.onOpenSearch != null ||
                widget.onCreateNote != null ||
                widget.onOpenRag != null);
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
        final NoteFlowWorkspaceTokens tokens = NoteFlowWorkspaceTokens.of(
          context,
        );

        // Keep the page stack at the same element path at every width. Moving
        // it between a compact Scaffold/Column and an expanded Row used to
        // dispose an active editor, losing its unsaved draft on resize.
        return Scaffold(
          backgroundColor:
              compact &&
                  _destination == WorkspaceDestination.dashboard &&
                  !_compactSearchActive
              ? tokens.compactHomeSurface
              : tokens.pageSurface,
          floatingActionButton: null,
          bottomNavigationBar: compactBottomBarVisible
              ? _buildCompactBottomBar(copy)
              : null,
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              SafeArea(
                // Keep content below status bars, notches and Dynamic Island
                // at every width. The sidebar opts out because this full-width
                // safe strip already reserves the top inset for the whole row.
                top: true,
                left: compact,
                right: compact,
                bottom: false,
                child: SizedBox(
                  height: compact && !_compactSearchActive && !compactEditor
                      ? 48
                      : 0,
                  child: compact && !_compactSearchActive && !compactEditor
                      ? _buildCompactTopBar(copy)
                      : const SizedBox.shrink(),
                ),
              ),
              Expanded(
                child: Builder(
                  builder: (bodyContext) => MediaQuery.removePadding(
                    // Preserve the Scaffold body's consumed IME metrics. Reading
                    // the outer context would restore the full inset and make
                    // the embedded Notes Scaffold subtract the keyboard twice.
                    context: bodyContext,
                    // The full-width strip above already consumes the top
                    // inset, including while its navigation child is hidden.
                    removeTop: true,
                    child: SafeArea(
                      top: false,
                      left: compact,
                      right: compact,
                      // The compact navigation bar handles the system inset when
                      // present. When it is hidden, keep search/page content above
                      // the Android navbar or iOS Home Indicator.
                      bottom: compact && !compactBottomBarVisible,
                      child: Stack(
                        fit: StackFit.expand,
                        children: <Widget>[
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              AnimatedContainer(
                                // A phone viewport cannot reserve the old desktop
                                // sidebar width while its page changes layout.
                                duration: compact
                                    ? Duration.zero
                                    : NoteFlowMotion.duration(context),
                                curve: Curves.easeOutCubic,
                                width: navigationWidth,
                                child: ClipRect(
                                  child: OverflowBox(
                                    alignment: Alignment.centerLeft,
                                    minWidth: medium
                                        ? WorkspaceShell.navigationRailWidth
                                        : WorkspaceShell.sidebarWidth,
                                    maxWidth: medium
                                        ? WorkspaceShell.navigationRailWidth
                                        : WorkspaceShell.sidebarWidth,
                                    child: NoteFlowStateTransition(
                                      child:
                                          navigation ?? const SizedBox.shrink(),
                                    ),
                                  ),
                                ),
                              ),
                              AnimatedContainer(
                                duration: compact
                                    ? Duration.zero
                                    : NoteFlowMotion.duration(context),
                                curve: Curves.easeOutCubic,
                                width: dividerWidth,
                                child: dividerWidth == 0
                                    ? const SizedBox.shrink()
                                    : const VerticalDivider(
                                        width: 1,
                                        thickness: 1,
                                      ),
                              ),
                              Expanded(
                                child: NoteFlowHeaderInset(
                                  leading: collapsedDesktop
                                      ? WorkspaceShell.collapsedSidebarWidth
                                      : 0,
                                  child: _buildSwipePages(compact: compact),
                                ),
                              ),
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
                  ),
                ),
              ),
            ],
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

  Widget _buildSwipePages({required bool compact}) {
    // The editor owns horizontal text-selection handles and block gestures.
    // A shell drag recognizer would win slow drags before the inner pan reaches
    // its slop threshold, even when no page change ultimately occurs.
    final allowPageSwipe = compact && !_noteEditorActive;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: allowPageSwipe
          ? (_) {
              _horizontalSwipeDistance = 0;
              _pointerSwipeHandled = false;
            }
          : null,
      onHorizontalDragUpdate: allowPageSwipe
          ? (DragUpdateDetails details) {
              if (_pointerSwipeHandled) {
                return;
              }
              _horizontalSwipeDistance += details.delta.dx;
              if (_horizontalSwipeDistance.abs() < 80) {
                return;
              }
              final int nextIndex =
                  (_selectedIndex + (_horizontalSwipeDistance < 0 ? 1 : -1))
                      .clamp(0, 1);
              _pointerSwipeHandled = true;
              if (nextIndex != _selectedIndex) {
                showDestination(WorkspaceDestination.values[nextIndex]);
              }
            }
          : null,
      onHorizontalDragEnd: allowPageSwipe
          ? (_) {
              _horizontalSwipeDistance = 0;
              _pointerSwipeHandled = false;
            }
          : null,
      onHorizontalDragCancel: allowPageSwipe
          ? () {
              _horizontalSwipeDistance = 0;
              _pointerSwipeHandled = false;
            }
          : null,
      child: AnimatedBuilder(
        animation: _pageMotionController,
        child: _buildPages(),
        builder: (BuildContext context, Widget? child) {
          final double progress = Curves.easeOutCubic.transform(
            _pageMotionController.value,
          );
          return FractionalTranslation(
            translation: compact
                ? Offset(_pageTravel * (1 - progress), 0)
                : Offset.zero,
            child: Opacity(
              opacity: compact ? 0.94 + (0.06 * progress) : 1,
              child: child,
            ),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _pageMotionController.dispose();
    super.dispose();
  }

  Widget _buildCompactTopBar(WorkspaceCopy copy) {
    final NoteFlowWorkspaceTokens tokens = NoteFlowWorkspaceTokens.of(context);
    final ThemeData theme = Theme.of(context);
    return SizedBox(
      height: 48,
      child: Padding(
        padding: const EdgeInsets.only(left: 16),
        child: Row(
          children: <Widget>[
            KeyedSubtree(
              key: WorkspaceShell.compactBrandKey,
              child: KeyedSubtree(
                key: WorkspaceShell.compactMenuKey,
                child: IconButton(
                  key: WorkspaceShell.compactAvatarKey,
                  tooltip: copy.openMenu,
                  onPressed: () => _showCompactMenu(copy),
                  padding: EdgeInsets.zero,
                  icon: CircleAvatar(
                    radius: 19,
                    backgroundColor: tokens.selectedSurface,
                    foregroundColor: tokens.textPrimary,
                    backgroundImage: widget.accountAvatar,
                    child: widget.accountAvatar != null
                        ? null
                        : Text(
                            _avatarInitial,
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: tokens.textPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: NoteFlowSpacing.xs),
            Expanded(child: _buildCompactTopNavigation(copy)),
          ],
        ),
      ),
    );
  }

  Widget? _buildCompactBottomBar(WorkspaceCopy copy) {
    final bool canSearch = widget.onOpenSearch != null;
    final bool canCreate = widget.onCreateNote != null;
    final bool canAsk = widget.onOpenRag != null;
    if (!canSearch && !canCreate && !canAsk) {
      return null;
    }

    final NoteFlowWorkspaceTokens tokens = NoteFlowWorkspaceTokens.of(context);
    return KeyedSubtree(
      key: WorkspaceShell.compactBottomNavigationKey,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            NoteFlowSpacing.lg,
            NoteFlowSpacing.sm,
            NoteFlowSpacing.lg,
            NoteFlowSpacing.sm,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              if (canSearch)
                Tooltip(
                  message: copy.search,
                  child: Material(
                    color: tokens.pageSurface,
                    shape: CircleBorder(
                      side: BorderSide(color: tokens.divider),
                    ),
                    child: InkWell(
                      key: WorkspaceShell.compactSearchKey,
                      customBorder: const CircleBorder(),
                      onTap: widget.onOpenSearch,
                      child: SizedBox.square(
                        dimension: 48,
                        child: Icon(Icons.search, color: tokens.textSecondary),
                      ),
                    ),
                  ),
                ),
              if (canAsk)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: OutlinedButton.icon(
                      key: const ValueKey('workspace-bottom-ask-notes'),
                      onPressed: widget.onOpenRag,
                      icon: const Icon(Icons.forum_outlined, size: 20),
                      label: Text(
                        copy.askNotes,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(48, 48),
                        foregroundColor: tokens.textSecondary,
                        side: BorderSide(color: tokens.divider),
                        shape: const StadiumBorder(),
                      ),
                    ),
                  ),
                ),
              if (canCreate)
                Tooltip(
                  message: copy.newNote,
                  child: Material(
                    color: tokens.pageSurface,
                    shape: CircleBorder(
                      side: BorderSide(color: tokens.divider),
                    ),
                    child: InkWell(
                      key: WorkspaceShell.compactFabNewNoteKey,
                      customBorder: const CircleBorder(),
                      onTap: widget.onCreateNote,
                      child: SizedBox.square(
                        dimension: 48,
                        child: Icon(
                          Icons.edit_outlined,
                          color: tokens.textPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String get _avatarInitial {
    final String value = widget.accountName?.trim() ?? '';
    return value.isEmpty ? 'U' : value.substring(0, 1).toUpperCase();
  }

  Widget _buildBrandMark(double size) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(NoteFlowRadius.row),
      child: SizedBox.square(
        dimension: size,
        child: Image.asset(
          WorkspaceShell.notionBrandAsset,
          key: WorkspaceShell.notionBrandMarkKey,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.high,
        ),
      ),
    );
  }

  Widget _buildCompactTopNavigation(WorkspaceCopy copy) {
    final List<Widget> items = <Widget>[
      _buildCompactTopAction(
        key: const ValueKey<String>('workspace-compact-home'),
        tooltip: _labelFor(copy, WorkspaceDestination.dashboard),
        icon: _iconFor(WorkspaceDestination.dashboard, active: false),
        activeIcon: _iconFor(WorkspaceDestination.dashboard, active: true),
        selected: _destination == WorkspaceDestination.dashboard,
        onPressed: () => showDestination(WorkspaceDestination.dashboard),
      ),
      _buildCompactTopAction(
        key: const ValueKey<String>('workspace-compact-notes'),
        tooltip: _labelFor(copy, WorkspaceDestination.notes),
        icon: _iconFor(WorkspaceDestination.notes, active: false),
        activeIcon: _iconFor(WorkspaceDestination.notes, active: true),
        selected: _destination == WorkspaceDestination.notes,
        onPressed: () => showDestination(WorkspaceDestination.notes),
      ),
    ];
    return Align(
      alignment: Alignment.centerLeft,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (int index = 0; index < items.length; index++) ...<Widget>[
              items[index],
              if (index < items.length - 1)
                const SizedBox(width: NoteFlowSpacing.xs),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCompactTopAction({
    required Key key,
    required String tooltip,
    required IconData icon,
    required IconData activeIcon,
    required VoidCallback onPressed,
    bool selected = false,
  }) {
    final NoteFlowWorkspaceTokens tokens = NoteFlowWorkspaceTokens.of(context);
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: 64,
        height: 40,
        child: Material(
          color: selected ? tokens.selectedSurface : tokens.subtleSurface,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            key: key,
            borderRadius: BorderRadius.circular(18),
            onTap: onPressed,
            child: Center(
              child: AnimatedSwitcher(
                duration: NoteFlowMotion.duration(context, NoteFlowMotion.fast),
                child: Icon(
                  selected ? activeIcon : icon,
                  key: ValueKey<bool>(selected),
                  size: selected ? 22 : 20,
                  color: tokens.textPrimary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showCompactMenu(WorkspaceCopy copy) {
    return showGeneralDialog<void>(
      context: context,
      // Keep the opening tap from immediately dismissing the newly-created
      // route on Android; the drawer has an explicit close affordance.
      barrierDismissible: false,
      barrierLabel: copy.openMenu,
      barrierColor: Colors.black54,
      transitionDuration: NoteFlowMotion.duration(context),
      pageBuilder:
          (
            BuildContext sheetContext,
            Animation<double> animation,
            Animation<double> secondaryAnimation,
          ) {
            final double viewportWidth = MediaQuery.sizeOf(sheetContext).width;
            final double leftInset = MediaQuery.paddingOf(sheetContext).left;
            final double rightInset = MediaQuery.paddingOf(sheetContext).right;
            final double preferredDrawerWidth = (viewportWidth * 0.84)
                .clamp(280.0, 340.0)
                .toDouble();
            final double availableDrawerWidth =
                (viewportWidth - leftInset - rightInset - 16)
                    .clamp(0.0, 340.0)
                    .toDouble();
            final double drawerWidth =
                preferredDrawerWidth > availableDrawerWidth
                ? availableDrawerWidth
                : preferredDrawerWidth;
            return Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: EdgeInsets.only(
                  top: MediaQuery.paddingOf(context).top + 56,
                ),
                child: SafeArea(
                  top: false,
                  right: false,
                  child: SizedBox(
                    width: drawerWidth,
                    height: double.infinity,
                    child: NoteFlowSurface(
                      tone: NoteFlowSurfaceTone.elevated,
                      padding: const EdgeInsets.fromLTRB(
                        NoteFlowSpacing.sm,
                        NoteFlowSpacing.sm,
                        NoteFlowSpacing.sm,
                        NoteFlowSpacing.xl,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              widget.accountAvatar == null
                                  ? _buildBrandMark(28)
                                  : CircleAvatar(
                                      radius: 14,
                                      backgroundImage: widget.accountAvatar,
                                    ),
                              const SizedBox(width: NoteFlowSpacing.sm),
                              Expanded(
                                child: Text(
                                  widget.accountName ?? copy.workspaceTitle,
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                              ),
                              IconButton(
                                tooltip: MaterialLocalizations.of(context)
                                    .closeButtonTooltip,
                                onPressed: () =>
                                    Navigator.of(sheetContext).pop(),
                                icon: const Icon(Icons.close),
                              ),
                            ],
                          ),
                          const Divider(height: NoteFlowSpacing.lg),
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
                          if (widget.onOpenRag != null)
                            KeyedSubtree(
                              key: WorkspaceShell.askNotesKey,
                              child: NoteFlowSidebarRow(
                                key: WorkspaceShell.compactMenuAskNotesKey,
                                label: copy.askNotes,
                                icon: Icons.forum_outlined,
                                onTap: () {
                                  Navigator.of(sheetContext).pop();
                                  widget.onOpenRag?.call();
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
                    ),
                  ),
                ),
              ),
            );
          },
      transitionBuilder:
          (
            BuildContext context,
            Animation<double> animation,
            Animation<double> secondaryAnimation,
            Widget child,
          ) {
            return SlideTransition(
              position:
                  Tween<Offset>(begin: const Offset(-1, 0), end: Offset.zero)
                      .chain(CurveTween(curve: Curves.easeOutCubic))
                      .animate(animation),
              child: child,
            );
          },
    );
  }

  Widget _buildNavigationRail(WorkspaceCopy copy) {
    final NoteFlowWorkspaceTokens tokens = NoteFlowWorkspaceTokens.of(context);
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
        trailing: widget.onOpenRag == null
            ? null
            : Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: NoteFlowSpacing.sm,
                ),
                child: IconButton(
                  key: WorkspaceShell.railAskNotesKey,
                  tooltip: copy.askNotes,
                  onPressed: widget.onOpenRag,
                  icon: const Icon(Icons.forum_outlined),
                ),
              ),
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
    final NoteFlowWorkspaceTokens tokens = NoteFlowWorkspaceTokens.of(context);
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
            top: false,
            right: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _buildSidebarHeader(copy),
                const Divider(height: 1.0),
                if (widget.onOpenSearch != null)
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
                          DecoratedBox(
                            decoration: BoxDecoration(
                              color: tokens.subtleSurface.withValues(
                                alpha: .45,
                              ),
                              border: Border.all(color: tokens.divider),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: NoteFlowSidebarRow(
                              key: WorkspaceShell.sidebarSearchKey,
                              label: copy.search,
                              icon: Icons.search,
                              dense: true,
                              onTap: widget.onOpenSearch,
                            ),
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
                          dense: true,
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
    final NoteFlowWorkspaceTokens tokens = NoteFlowWorkspaceTokens.of(context);
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
            child: InkWell(
              borderRadius: BorderRadius.circular(NoteFlowRadius.row),
              onTap: () => showDestination(WorkspaceDestination.dashboard),
              child: Row(
                children: <Widget>[
                  Semantics(
                    excludeSemantics: true,
                    child: widget.accountAvatar == null
                        ? _buildBrandMark(24)
                        : CircleAvatar(
                            radius: 12,
                            backgroundImage: widget.accountAvatar,
                          ),
                  ),
                  const SizedBox(width: NoteFlowSpacing.sm),
                  Expanded(
                    child: Text(
                      widget.accountName ?? copy.workspaceTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: titleStyle?.copyWith(
                        color: tokens.textSecondary,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (widget.onCreateNote != null)
            IconButton(
              key: WorkspaceShell.sidebarNewNoteKey,
              tooltip: copy.newNote,
              onPressed: widget.onCreateNote,
              icon: const Icon(Icons.edit_square, size: 19),
              visualDensity: VisualDensity.compact,
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
    if (widget.onOpenRag == null &&
        widget.onOpenSettings == null &&
        widget.onOpenDiagnostics == null) {
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
              if (widget.onOpenRag != null)
                NoteFlowSidebarRow(
                  key: WorkspaceShell.askNotesKey,
                  label: copy.askNotes,
                  icon: Icons.forum_outlined,
                  onTap: widget.onOpenRag,
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
              if (widget.onOpenDiagnostics != null)
                NoteFlowSidebarRow(
                  key: WorkspaceShell.diagnosticsKey,
                  label: copy.diagnostics,
                  icon: Icons.bug_report_outlined,
                  onTap: widget.onOpenDiagnostics,
                  dense: true,
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCollapsedSidebar(WorkspaceCopy copy) {
    final NoteFlowWorkspaceTokens tokens = NoteFlowWorkspaceTokens.of(context);
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
            icon: const Icon(Icons.menu, size: 20),
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
