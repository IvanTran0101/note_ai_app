import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/domain/notes/note_document.dart';
import 'package:note_ai_app/presentation/editor/document_palette.dart';

void main() {
  for (final brightness in Brightness.values) {
    test(
      '$brightness colors remain readable across all semantic highlights',
      () {
        final bases = brightness == Brightness.light
            ? const [Color(0xffffffff), Color(0xfff4f6f4)]
            : const [Color(0xff191919), Color(0xff252525), Color(0xff2f2f2f)];
        for (final foreground in DocumentColor.values) {
          final text = DocumentPalette.text(foreground, brightness);
          for (final base in bases) {
            expect(_contrast(text, base), greaterThanOrEqualTo(4.5));
            for (final background in DocumentColor.values) {
              final fill = Color.alphaBlend(
                DocumentPalette.highlight(background, brightness),
                base,
              );
              expect(
                _contrast(text, fill),
                greaterThanOrEqualTo(4.5),
                reason: '$foreground on $background over $base',
              );
            }
          }
        }
      },
    );
  }
}

double _contrast(Color a, Color b) {
  final x = a.computeLuminance(), y = b.computeLuminance();
  return (math.max(x, y) + .05) / (math.min(x, y) + .05);
}
