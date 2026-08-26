import 'package:flutter_test/flutter_test.dart';

import 'package:note_ai_app/domain/note_intelligence/summary.dart';

void main() {
  group('Summary', () {
    test('stores the supplied text', () {
      const summary = Summary('A concise note summary.');

      expect(summary.text, 'A concise note summary.');
    });

    test('compares by value', () {
      const first = Summary('Same summary');
      const second = Summary('Same summary');
      const different = Summary('Different summary');

      expect(first, second);
      expect(first.hashCode, second.hashCode);
      expect(first, isNot(different));
    });

    test('preserves empty text because no validation rule is defined yet', () {
      const summary = Summary('');

      expect(summary.text, isEmpty);
    });

    test('has a readable string representation', () {
      const summary = Summary('A concise note summary.');

      expect(summary.toString(), "Summary('A concise note summary.')");
    });
  });
}
