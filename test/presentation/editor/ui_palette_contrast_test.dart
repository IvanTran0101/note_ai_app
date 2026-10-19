import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/presentation/notes/notes_theme_tokens.dart';

void main() {
  for (final dark in [false, true]) {
    test('shared UI text and action colors meet AA dark=$dark', () {
      final tokens = dark ? NoteFlowUiTokens.dark() : NoteFlowUiTokens.light();
      for (final surface in [
        tokens.pageSurface,
        tokens.sidebarSurface,
        tokens.elevatedSurface,
        tokens.subtleSurface,
      ]) {
        for (final ink in [
          tokens.textPrimary,
          tokens.textSecondary,
          tokens.textMuted,
          tokens.link,
          tokens.error,
        ]) {
          expect(
            _contrast(ink, surface),
            greaterThanOrEqualTo(4.5),
            reason: '$ink on $surface',
          );
        }
      }
      expect(
        _contrast(tokens.link, dark ? const Color(0xFF102A43) : Colors.white),
        greaterThanOrEqualTo(4.5),
      );
    });
  }
}

double _contrast(Color a, Color b) {
  final x = a.computeLuminance(), y = b.computeLuminance();
  return (math.max(x, y) + .05) / (math.min(x, y) + .05);
}
