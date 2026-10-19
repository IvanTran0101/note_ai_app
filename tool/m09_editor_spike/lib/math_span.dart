import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

InlineSpan mathSpan(
  BuildContext context,
  Node node,
  int index,
  TextInsert text,
  TextSpan before,
  TextSpan after,
) {
  final latex = text.attributes?['m09_math'];
  if (latex is! String || text.text != '\uFFFC') return after;
  return WidgetSpan(
    alignment: PlaceholderAlignment.baseline,
    baseline: TextBaseline.alphabetic,
    child: Semantics(
      label: 'Equation $latex',
      child: Math.tex(latex, textStyle: after.style),
    ),
  );
}
