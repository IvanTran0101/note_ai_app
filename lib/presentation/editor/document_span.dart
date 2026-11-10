import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import 'document_palette.dart';
import 'rich_inline_codec.dart';

InlineSpan documentSpan(
  BuildContext context,
  Node node,
  int index,
  TextInsert text,
  TextSpan before,
  TextSpan after,
) {
  final brightness = Theme.of(context).brightness;
  final color = RichInlineCodec.color(text.attributes?['m09_color']);
  final highlight = RichInlineCodec.color(text.attributes?['m09_highlight']);
  final heading = node.type == 'heading';
  final checked =
      node.type == 'todo_list' && node.attributes['checked'] == true;
  final level = (node.attributes['level'] as int? ?? 1).clamp(1, 4);
  final style = (after.style ?? const TextStyle()).copyWith(
    // Block defaults (heading/todo) are applied by the public builder after
    // the inline style. Explicit range marks must retain their precedence.
    fontSize:
        (text.attributes?['font_size'] as num?)?.toDouble() ??
        (heading ? [30.0, 24.0, 20.0, 18.0][level - 1] : null),
    fontFamily: heading && kIsWeb ? 'NoteFlowHeading' : after.style?.fontFamily,
    height: heading && kIsWeb ? 1.3 : after.style?.height,
    letterSpacing: heading && kIsWeb && level == 1
        ? -.4
        : after.style?.letterSpacing,
    fontWeight: text.attributes?['bold'] == true
        ? FontWeight.w700
        : (heading ? (kIsWeb ? FontWeight.w500 : FontWeight.w600) : null),
    fontStyle: text.attributes?['italic'] == true ? FontStyle.italic : null,
    color: color != null
        ? DocumentPalette.text(color, brightness)
        : checked
        ? Theme.of(context).colorScheme.onSurfaceVariant
        : null,
    decoration: checked
        ? TextDecoration.combine([
            if (after.style?.decoration != null) after.style!.decoration!,
            TextDecoration.lineThrough,
          ])
        : null,
    backgroundColor: highlight == null
        ? null
        : DocumentPalette.highlight(highlight, brightness),
  );
  final expression = text.attributes?['m09_math'];
  if (expression is String && text.text.codeUnits.every((c) => c == 0xFFFC)) {
    return TextSpan(
      children: [
        for (var i = 0; i < text.text.length; i++)
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: Semantics(
              label: 'Equation $expression',
              child: Math.tex(
                expression,
                textStyle: style,
                onErrorFallback: (_) => Text(expression, style: style),
              ),
            ),
          ),
      ],
    );
  }
  return TextSpan(
    text: after.text,
    children: after.children,
    style: style,
    recognizer: after.recognizer,
    mouseCursor: after.mouseCursor,
    onEnter: after.onEnter,
    onExit: after.onExit,
    semanticsLabel: after.semanticsLabel,
    locale: after.locale,
    spellOut: after.spellOut,
  );
}
