import 'package:flutter/widgets.dart';

/// Space reserved for the shell's existing sidebar control in the page header.
/// Document geometry and editor state are independent of this header-only inset.
final class NoteFlowHeaderInset extends InheritedWidget {
  const NoteFlowHeaderInset({
    super.key,
    required this.leading,
    required super.child,
  });

  final double leading;

  static double of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<NoteFlowHeaderInset>()
          ?.leading ??
      0;

  @override
  bool updateShouldNotify(NoteFlowHeaderInset oldWidget) =>
      leading != oldWidget.leading;
}
