// Verifies the conditional persistence facade without importing dart:io.

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:note_ai_app/infrastructure/notes/database_context.dart';

void main() {
  test('Web facade exposes an unavailable file context', () {
    if (!kIsWeb) {
      return;
    }

    final FileDatabaseContext context = FileDatabaseContext();

    expect(() => context.readNotes(), throwsUnsupportedError);
    expect(() => context.writeNotes(const []), throwsUnsupportedError);
  });
}
