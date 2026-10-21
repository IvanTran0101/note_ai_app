import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/presentation/common/note_flow_settings_choices.dart';

void main() {
  for (final size in [const Size(412, 914), const Size(914, 412)]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('native choices $size scale$scale stay safe and dismiss', (
        tester,
      ) async {
        tester.view
          ..physicalSize = size
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final changes = <ThemeMode?>[];
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(scale),
                padding: const EdgeInsets.only(top: 32, bottom: 48),
              ),
              child: child!,
            ),
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 200,
                  child: NoteFlowNativeSettingsChoice<ThemeMode>(
                    label: 'Theme',
                    initialValue: ThemeMode.system,
                    items: const [
                      DropdownMenuItem(
                        value: ThemeMode.system,
                        child: Text('System'),
                      ),
                      DropdownMenuItem(
                        value: ThemeMode.light,
                        enabled: false,
                        child: Text('Light'),
                      ),
                      DropdownMenuItem(
                        value: ThemeMode.dark,
                        child: Text('Dark'),
                      ),
                    ],
                    onChanged: changes.add,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.byType(OutlinedButton));
        await tester.pumpAndSettle();
        expect(find.text('Theme'), findsOneWidget);
        expect(tester.takeException(), isNull);
        final done = find.widgetWithText(TextButton, 'Done');
        expect(
          tester.getBottomRight(done).dy,
          lessThanOrEqualTo(size.height - 48),
        );
        final light = tester.widget<TextButton>(
          find.widgetWithText(TextButton, 'Light'),
        );
        expect(light.onPressed, isNull);
        await tester.tap(done);
        await tester.pumpAndSettle();
        expect(changes, isEmpty);
        await tester.tap(find.byType(OutlinedButton));
        await tester.pumpAndSettle();
        final dark = find.widgetWithText(TextButton, 'Dark');
        await tester.ensureVisible(dark);
        await tester.tap(dark);
        await tester.pumpAndSettle();
        expect(changes, [ThemeMode.dark]);
        expect(find.text('Done'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
