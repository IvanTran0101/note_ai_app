import 'package:flutter/material.dart';

import 'notes_theme_tokens.dart';

/// Presentation-only layout frame for the Notes destination.
///
/// The frame does not know how notes are loaded or edited. It receives already
/// composed list/detail widgets and only adapts their placement to the
/// available width. The list stays mounted behind a center peek on tablets,
/// beside a side peek on desktop, and behind a full page on phones.
final class ResponsiveNotesWorkspace extends StatefulWidget {
  const ResponsiveNotesWorkspace({
    super.key,
    required this.list,
    required this.detail,
    required this.hasSelection,
    this.onCompactBack,
    this.onDismiss,
    this.compactBackLabel = 'Back to notes',
    this.preferFullPage = false,
  });

  static const double compactBreakpoint = NoteFlowLayout.compactBreakpoint;
  static const double expandedBreakpoint = NoteFlowLayout.expandedBreakpoint;
  static const double mediumListWidth = 320;
  static const double expandedListWidth = 336;

  static const Key compactKey = ValueKey<String>(
    'responsive-notes-compact-surface',
  );
  static const Key mediumKey = ValueKey<String>(
    'responsive-notes-medium-surface',
  );
  static const Key expandedKey = ValueKey<String>(
    'responsive-notes-expanded-surface',
  );
  static const Key fullPageKey = ValueKey<String>('responsive-notes-full-page');
  static const Key listPaneKey = ValueKey<String>('responsive-notes-list-pane');
  static const Key detailPaneKey = ValueKey<String>(
    'responsive-notes-detail-pane',
  );
  static const Key dismissBarrierKey = ValueKey<String>('notes-peek-dismiss');

  final Widget list;
  final Widget detail;
  final bool hasSelection;
  final VoidCallback? onCompactBack;
  final VoidCallback? onDismiss;
  final String compactBackLabel;
  final bool preferFullPage;

  @override
  State<ResponsiveNotesWorkspace> createState() =>
      _ResponsiveNotesWorkspaceState();
}

final class _ResponsiveNotesWorkspaceState
    extends State<ResponsiveNotesWorkspace>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion = AnimationController(
    vsync: this,
    value: widget.hasSelection ? 1 : 0,
    duration: NoteFlowMotion.standard,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _motion.duration = NoteFlowMotion.duration(context);
    if (MediaQuery.disableAnimationsOf(context)) {
      _motion.value = widget.hasSelection ? 1 : 0;
    }
  }

  @override
  void didUpdateWidget(covariant ResponsiveNotesWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hasSelection != widget.hasSelection) {
      if (MediaQuery.disableAnimationsOf(context)) {
        _motion.value = widget.hasSelection ? 1 : 0;
      } else {
        _motion.animateTo(widget.hasSelection ? 1 : 0);
      }
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width = constraints.maxWidth;
        final bool compact = width < ResponsiveNotesWorkspace.compactBreakpoint;
        final bool expanded =
            !widget.preferFullPage &&
            width >= ResponsiveNotesWorkspace.expandedBreakpoint;
        final bool fullWidth = compact || widget.preferFullPage;
        final bool centerPeek = !fullWidth && !expanded;
        final Key surfaceKey = widget.preferFullPage
            ? ResponsiveNotesWorkspace.fullPageKey
            : compact
            ? ResponsiveNotesWorkspace.compactKey
            : centerPeek
            ? ResponsiveNotesWorkspace.mediumKey
            : ResponsiveNotesWorkspace.expandedKey;
        final double paneWidth = fullWidth
            ? width
            : centerPeek
            ? (width - NoteFlowSpacing.xxxl).clamp(0, 680).toDouble()
            : (width * 0.62)
                  .clamp(480, width - ResponsiveNotesWorkspace.mediumListWidth)
                  .toDouble();
        final double inset = centerPeek ? NoteFlowSpacing.xl : 0;
        final NoteFlowUiTokens tokens = NoteFlowUiTokens.of(context);

        // Stable Stack slots keep list scroll and the active editor alive when
        // a window is resized. Closing disposes the editor immediately, so an
        // outgoing animation cannot retain an autosave timer or a stale writer.
        return AnimatedBuilder(
          animation: _motion,
          builder: (BuildContext context, Widget? _) {
            final double progress = Curves.easeOutCubic.transform(
              _motion.value,
            );
            final bool blockList = widget.hasSelection && !expanded;
            return Stack(
              fit: StackFit.expand,
              children: <Widget>[
                KeyedSubtree(key: surfaceKey, child: const SizedBox.shrink()),
                Positioned.fill(
                  right: expanded ? paneWidth * progress : 0,
                  child: Offstage(
                    offstage: fullWidth && widget.hasSelection && progress == 1,
                    child: ExcludeFocus(
                      excluding: blockList,
                      child: ExcludeSemantics(
                        excluding: blockList,
                        child: IgnorePointer(
                          ignoring: blockList,
                          child: KeyedSubtree(
                            key: ResponsiveNotesWorkspace.listPaneKey,
                            child: widget.list,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: Offstage(
                    offstage: !centerPeek || !widget.hasSelection,
                    child: GestureDetector(
                      key: ResponsiveNotesWorkspace.dismissBarrierKey,
                      // Back already provides the accessible close action.
                      // A full-screen tap semantic merges over the editor and
                      // intercepts iframe PDF/video controls on Flutter Web.
                      excludeFromSemantics: true,
                      behavior: HitTestBehavior.opaque,
                      onTap: widget.onDismiss ?? widget.onCompactBack,
                      child: ColoredBox(
                        color: Colors.black.withValues(alpha: 0.15 * progress),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: inset,
                  bottom: inset,
                  right: centerPeek ? (width - paneWidth) / 2 : 0,
                  width: paneWidth,
                  child: Offstage(
                    offstage: !widget.hasSelection && progress == 0,
                    child: IgnorePointer(
                      ignoring: !widget.hasSelection,
                      child: Transform.translate(
                        offset: centerPeek
                            ? Offset(0, 8 * (1 - progress))
                            : Offset(paneWidth * (1 - progress), 0),
                        child: Opacity(
                          opacity: centerPeek ? progress : 1,
                          child: Material(
                            color: tokens.pageSurface,
                            elevation: fullWidth ? 0 : 8,
                            shadowColor: Colors.black26,
                            borderRadius: BorderRadius.circular(
                              centerPeek ? NoteFlowRadius.dialog : 0,
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: <Widget>[
                                SizedBox(
                                  height:
                                      compact &&
                                          widget.hasSelection &&
                                          widget.onCompactBack != null
                                      ? 44
                                      : 0,
                                  child:
                                      compact &&
                                          widget.hasSelection &&
                                          widget.onCompactBack != null
                                      ? Align(
                                          alignment: Alignment.centerLeft,
                                          child: IconButton(
                                            tooltip: widget.compactBackLabel,
                                            icon: const Icon(Icons.arrow_back),
                                            onPressed: widget.onCompactBack,
                                          ),
                                        )
                                      : const SizedBox.shrink(),
                                ),
                                Expanded(
                                  child: widget.hasSelection
                                      ? KeyedSubtree(
                                          key: ResponsiveNotesWorkspace
                                              .detailPaneKey,
                                          child: widget.detail,
                                        )
                                      : const SizedBox.shrink(),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
