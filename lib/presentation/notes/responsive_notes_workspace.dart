import 'package:flutter/material.dart';

/// Presentation-only layout frame for the Notes destination.
///
/// The frame does not know how notes are loaded or edited. It receives already
/// composed list/detail widgets and only adapts their placement to the
/// available width.
final class ResponsiveNotesWorkspace extends StatelessWidget {
  const ResponsiveNotesWorkspace({
    super.key,
    required this.list,
    required this.detail,
    required this.hasSelection,
    this.onCompactBack,
    this.compactBackLabel = 'Back to notes',
  });

  static const double compactBreakpoint = 600;
  static const double expandedBreakpoint = 840;
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
        if (width < compactBreakpoint) {
          return _buildCompact();
        }
        if (width < expandedBreakpoint) {
          return _buildSplit(
            surfaceKey: mediumKey,
            listWidth: _mediumListWidth(width),
          );
        }
        return _buildSplit(
          surfaceKey: expandedKey,
          listWidth: expandedListWidth,
        );
      },
    );
  }

  Widget _buildCompact() {
    final Widget child = hasSelection ? detail : list;
    if (!hasSelection || onCompactBack == null) {
      return KeyedSubtree(key: compactKey, child: child);
    }
    return KeyedSubtree(
      key: compactKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              tooltip: compactBackLabel,
              icon: const Icon(Icons.arrow_back),
              onPressed: onCompactBack,
            ),
          ),
          Expanded(child: detail),
        ],
      ),
    );
  }

  Widget _buildSplit({required Key surfaceKey, required double listWidth}) {
    return KeyedSubtree(
      key: surfaceKey,
      child: Row(
        key: const ValueKey<String>('responsive-notes-split-row'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SizedBox(key: listPaneKey, width: listWidth, child: list),
          const VerticalDivider(width: 1, thickness: 1),
          Expanded(key: detailPaneKey, child: detail),
        ],
      ),
    );
  }

  double _mediumListWidth(double availableWidth) {
    final double proportional = availableWidth * 0.38;
    if (proportional < 280) {
      return 280;
    }
    if (proportional > mediumListWidth) {
      return mediumListWidth;
    }
    return proportional;
  }
}
