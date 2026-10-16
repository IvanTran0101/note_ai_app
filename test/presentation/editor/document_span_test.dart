import 'package:appflowy_editor/appflowy_editor.dart' as engine;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/presentation/editor/document_span.dart';
import 'package:note_ai_app/presentation/editor/editor_value_dialog.dart';

void main() {
  testWidgets(
    'explicit range size/bold override heading defaults in painted span',
    (tester) async {
      TextSpan? rendered;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              rendered = documentSpan(
                context,
                engine.headingNode(level: 4),
                0,
                engine.TextInsert(
                  'text',
                  attributes: {'font_size': 24.0, 'bold': true},
                ),
                const TextSpan(
                  text: 'text',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
                ),
                const TextSpan(
                  text: 'text',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
              ) as TextSpan;
              return RichText(text: rendered!);
            },
          ),
        ),
      );
      expect(rendered!.style!.fontSize, 24);
      expect(rendered!.style!.fontWeight, FontWeight.w700);
    },
  );
  test(
    'equation preview parser refuses incomplete syntax before committing',
    () {
      expect(() => validateEditorEquation(r'\frac{a}'), throwsArgumentError);
      expect(() => validateEditorEquation(r'\frac{a}{b}'), returnsNormally);
    },
  );
}
