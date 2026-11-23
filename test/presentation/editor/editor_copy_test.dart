import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/presentation/editor/editor_copy.dart';
import 'package:note_ai_app/presentation/editor/editor_value_dialog.dart';

void main() {
  for (final locale in ['en', 'vi']) {
    testWidgets('existing value dialog and validation copy: $locale', (
      tester,
    ) async {
      String? result;
      await tester.pumpWidget(
        MaterialApp(
          locale: Locale(locale),
          supportedLocales: const [Locale('en'), Locale('vi')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async => result = await editorValueDialog(
                  context,
                  title: 'Font size',
                  label: 'Size (12–48)',
                  initial: '16',
                  validate: validateEditorSize,
                ),
                child: Text(editorText(context, 'Font size')),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text(locale == 'vi' ? 'Cỡ chữ' : 'Font size'));
      await tester.pumpAndSettle();
      final field = find.byType(TextField);
      await tester.enterText(field, '49');
      await tester.pumpAndSettle();
      expect(
        find.text(
          locale == 'vi' ? 'Nhập giá trị hợp lệ.' : 'Enter a valid value.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text(locale == 'vi' ? 'Áp dụng' : 'Apply'));
      await tester.pumpAndSettle();
      expect(result, null);
      await tester.enterText(field, '28');
      await tester.tap(find.text(locale == 'vi' ? 'Áp dụng' : 'Apply'));
      await tester.pumpAndSettle();
      expect(result, '28');
      expect(tester.takeException(), null);
    });
  }
}
