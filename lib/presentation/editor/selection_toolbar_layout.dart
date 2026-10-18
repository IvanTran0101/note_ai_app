import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../notes/notes_theme_tokens.dart';

/// Existing formatting commands wrap on normal screens and scroll on a short
/// phone viewport, leaving room for the selected line above the keyboard.
final class SelectionToolbarLayout extends StatelessWidget {
  const SelectionToolbarLayout({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final short = NoteFlowLayout.isShortEditor(context);
    return SizedBox(
      width: math.min(MediaQuery.sizeOf(context).width - 40, 670),
      height: short ? 48 : null,
      child: short
          ? SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: children),
            )
          : Wrap(alignment: WrapAlignment.center, children: children),
    );
  }
}
