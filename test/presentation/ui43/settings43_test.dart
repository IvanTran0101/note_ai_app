import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/presentation/common/note_flow_settings.dart';
import 'package:note_ai_app/presentation/common/note_flow_settings_choices.dart';

void main() {
  testWidgets('compact settings remain readable and scroll above the IME', (
    tester,
  ) async {
    const Size viewport = Size(320, 640);
    tester.view
      ..physicalSize = viewport
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            padding: const EdgeInsets.only(top: 24, bottom: 24),
            viewPadding: const EdgeInsets.only(top: 24, bottom: 24),
            viewInsets: const EdgeInsets.only(bottom: 220),
            textScaler: const TextScaler.linear(2),
          ),
          child: child!,
        ),
        home: const Scaffold(
          body: NoteFlowSettingsSurface(
            title: 'Appearance and language preferences',
            subtitle: 'Choose how the app looks and which language it uses.',
            children: [
              Text('Existing settings'),
              SizedBox(height: 480),
              Text('Final setting'),
            ],
          ),
        ),
      ),
    );

    final header = tester.getRect(find.text('Settings'));
    final back = tester.getRect(find.byIcon(Icons.arrow_back_ios_new));
    expect(header.top, greaterThanOrEqualTo(24));
    expect(header.left, greaterThanOrEqualTo(back.right));
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.text('Final setting'));
    expect(
      tester.getRect(find.text('Final setting')).bottom,
      lessThanOrEqualTo(viewport.height - 220),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('native choice sheet wraps a long title at 200% with IME', (
    tester,
  ) async {
    const Size viewport = Size(320, 640);
    const String longLabel =
        'Appearance and language preferences for this device';
    tester.view
      ..physicalSize = viewport
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            padding: const EdgeInsets.only(top: 24, bottom: 24),
            viewPadding: const EdgeInsets.only(top: 24, bottom: 24),
            viewInsets: const EdgeInsets.only(bottom: 220),
            textScaler: const TextScaler.linear(2),
          ),
          child: child!,
        ),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 260,
              child: NoteFlowNativeSettingsChoice<int>(
                label: longLabel,
                initialValue: 0,
                items: const [
                  DropdownMenuItem(value: 0, child: Text('Default')),
                  DropdownMenuItem(value: 1, child: Text('Alternative')),
                ],
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(OutlinedButton));
    await tester.pumpAndSettle();

    final title = find.text(longLabel);
    final done = find.widgetWithText(TextButton, 'Done');
    expect(title, findsOneWidget);
    expect(tester.getSize(title).height, greaterThan(48));
    expect(tester.getSize(done).height, greaterThanOrEqualTo(48));
    expect(
      tester.getRect(done).bottom,
      lessThanOrEqualTo(viewport.height - 220),
    );
    expect(tester.takeException(), isNull);
  });
}
