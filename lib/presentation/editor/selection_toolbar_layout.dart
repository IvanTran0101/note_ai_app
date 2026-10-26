import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../notes/notes_theme_tokens.dart';

/// Existing formatting commands wrap on normal screens and scroll on a short
/// phone viewport, leaving room for the selected line above the keyboard.
final class SelectionToolbarLayout extends StatelessWidget {
  const SelectionToolbarLayout({
    super.key,
    required this.children,
    this.desktopRows,
  });

  final List<Widget> children;
  final List<List<Widget>>? desktopRows;

  // Notion's visible surface is192px; its224px hit region includes16px
  // of transparent padding on either side. Measure the painted panel.
  static const double desktopPopupWidth = 192;
  static const double desktopPopupHeight = 110;

  static bool isDesktopPopup(BuildContext context) =>
      kIsWeb && !NoteFlowLayout.isCompact(context);

  static double widthFor(BuildContext context) => isDesktopPopup(context)
      ? desktopPopupWidth
      : !kIsWeb && NoteFlowLayout.isCompact(context)
      ? MediaQuery.sizeOf(context).width -
            MediaQuery.paddingOf(context).horizontal
      : math.min(MediaQuery.sizeOf(context).width - 40, 670);

  static bool singleRowFor(BuildContext context) =>
      NoteFlowLayout.isShortEditor(context) ||
      (!kIsWeb && NoteFlowLayout.isCompact(context));

  static double heightFor(BuildContext context) {
    if (isDesktopPopup(context)) return desktopPopupHeight;
    if (singleRowFor(context)) return 48;
    final width = MediaQuery.sizeOf(context).width;
    final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
    if (width < 380 || scale > 1.5) return 160;
    if (width < 720 || scale > 1.2) return 112;
    return 64;
  }

  @override
  Widget build(BuildContext context) {
    if (isDesktopPopup(context) && desktopRows != null) {
      final colors = Theme.of(context).colorScheme;
      final dark = Theme.of(context).brightness == Brightness.dark;
      final surface = dark ? const Color(0xFF252525) : colors.surface;
      final border = dark
          ? const Color(0xFF383838)
          : colors.outlineVariant.withValues(alpha: 0.55);
      final rows = desktopRows!;
      assert(rows.length == 3, 'Desktop selection toolbar needs three rows.');
      return Material(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(11),
          side: BorderSide(color: border),
        ),
        child: SizedBox(
          width: desktopPopupWidth,
          height: desktopPopupHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  height: 32,
                  child: rows[0].single,
                ),
                Divider(
                  height: 1,
                  thickness: 1,
                  color: colors.outlineVariant.withValues(alpha: 0.45),
                ),
                SizedBox(
                  height: 32,
                  child: Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: rows[1],
                    ),
                  ),
                ),
                Divider(
                  height: 1,
                  thickness: 1,
                  color: colors.outlineVariant.withValues(alpha: 0.45),
                ),
                SizedBox(
                  height: 32,
                  child: Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: rows[2],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final singleRow = singleRowFor(context);
    return SizedBox(
      width: widthFor(context),
      height: singleRow ? 48 : null,
      child: singleRow
          ? SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: children),
            )
          : Wrap(alignment: WrapAlignment.center, children: children),
    );
  }
}
