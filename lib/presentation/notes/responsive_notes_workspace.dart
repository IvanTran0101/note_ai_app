import 'package:flutter/material.dart';

import 'notes_theme_tokens.dart';

/// Presentation-only layout frame for the Notes destination.
///
/// The frame does not know how notes are loaded or edited. It receives already
/// composed list/detail widgets and only adapts their placement to the
/// available width. Wider layouts use the available canvas for either the list
/// or the selected page instead of showing a second navigation pane.
final class ResponsiveNotesWorkspace extends StatelessWidget {
  const ResponsiveNotesWorkspace({
    super.key,
    required this.list,
    required this.detail,
    required this.hasSelection,
    this.onCompactBack,
    this.compactBackLabel = 'Back to notes',
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
  static const Key listPaneKey = ValueKey<String>('responsive-notes-list-pane');
  static const Key detailPaneKey = ValueKey<String>(
    'responsive-notes-detail-pane',
  );

  final Widget list;
  final Widget detail;
  final bool hasSelection;
  final VoidCallback? onCompactBack;
  final String compactBackLabel;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width = constraints.maxWidth;
        final bool compact = width < compactBreakpoint;
        final Key surfaceKey = compact
            ? compactKey
            : width < expandedBreakpoint
            ? mediumKey
            : expandedKey;
        final Key contentKey = hasSelection ? detailPaneKey : listPaneKey;
        final Widget content = hasSelection ? detail : list;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            KeyedSubtree(
              key: surfaceKey,
              child: compact && hasSelection && onCompactBack != null
                  ? Align(
                      alignment: Alignment.centerLeft,
                      child: IconButton(
                        tooltip: compactBackLabel,
                        icon: const Icon(Icons.arrow_back),
                        onPressed: onCompactBack,
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            Expanded(
              child: KeyedSubtree(key: contentKey, child: content),
            ),
          ],
        );
      },
    );
  }
}
