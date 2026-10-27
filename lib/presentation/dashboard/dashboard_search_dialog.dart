import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../notes/notes_theme_tokens.dart';
import '../workspace/workspace_ui_tokens.dart';

/// The existing search route's surface; query state stays with DashboardPage.
final class DashboardSearchDialog extends StatelessWidget {
  const DashboardSearchDialog({
    super.key,
    required this.surfaceKey,
    required this.builder,
  });

  final Key surfaceKey;
  final LayoutWidgetBuilder builder;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, available) {
      final viewport = MediaQuery.sizeOf(context);
      final tokens = NoteFlowWorkspaceTokens.of(context);
      final usableHeight =
          (available.maxHeight - MediaQuery.viewInsetsOf(context).vertical)
              .clamp(0.0, double.infinity)
              .toDouble();
      // Live Notion Web: 9vh top, 700px cap and 16px bottom clearance.
      // Use route constraints so an embedded host does not count its chrome.
      final top = kIsWeb ? usableHeight * 0.09 : 60.0;
      final bottom = kIsWeb ? 16.0 : 20.0;
      final horizontal = kIsWeb ? 0.0 : NoteFlowSpacing.xl;
      final width =
          ((kIsWeb ? available.maxWidth : viewport.width) - 2 * horizontal)
              .clamp(0.0, 600.0)
              .toDouble();
      final height = kIsWeb
          ? (usableHeight - top - bottom).clamp(0.0, 700.0).toDouble()
          : (viewport.height - 80).clamp(0.0, 704.0).toDouble();
      return Dialog(
        alignment: Alignment.topCenter,
        insetPadding: EdgeInsets.fromLTRB(horizontal, top, horizontal, bottom),
        constraints: BoxConstraints(maxWidth: 600, maxHeight: height),
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF202020)
            : tokens.elevatedSurface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: tokens.divider),
        ),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          key: surfaceKey,
          width: width,
          height: height,
          child: LayoutBuilder(builder: builder),
        ),
      );
    },
  );
}
