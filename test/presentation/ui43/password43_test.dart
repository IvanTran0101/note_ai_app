import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:note_ai_app/presentation/notes/note_security_dialog.dart';
import 'package:note_ai_app/presentation/notes/note_security_localizations.dart';
import 'package:note_ai_app/presentation/notes/note_security_panel.dart';

import '../../security/security_harness.dart';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  testWidgets(
    'password form scrolls above the keyboard and keeps labels and errors readable',
    (tester) async {
      final harness = SecurityHarness('password43-layout');
      addTearDown(harness.dispose);
      tester.view
        ..physicalSize = const Size(360, 740)
        ..devicePixelRatio = 1
        ..viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.reset);
      await tester.runAsync(harness.initialize);

      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(1.7)),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => unawaited(
                    showNoteSecurityDialog(
                      context: context,
                      service: harness.security,
                      noteId: 'alpha',
                      action: NoteSecurityAction.enable,
                      serverAvailable: true,
                      sessionEvents: harness.security.changes,
                      isCurrent: () => true,
                    ),
                  ),
                  child: const Text('Open password form'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open password form'));
      await tester.pumpAndSettle();

      final dialog = find.byType(AlertDialog);
      expect(dialog, findsOneWidget);
      expect(
        find.descendant(
          of: dialog,
          matching: find.byType(SingleChildScrollView),
        ),
        findsOneWidget,
      );
      final fields = find.descendant(
        of: dialog,
        matching: find.byType(TextFormField),
      );
      expect(fields, findsNWidgets(2));
      expect(
        tester
            .widgetList<EditableText>(
              find.descendant(of: dialog, matching: find.byType(EditableText)),
            )
            .every((field) => field.obscureText),
        isTrue,
      );
      expect(find.text('Use at least 8 characters.'), findsOneWidget);

      await tester.ensureVisible(fields.at(0));
      await tester.enterText(fields.at(0), 'short');
      await tester.ensureVisible(fields.at(1));
      await tester.enterText(fields.at(1), 'different');
      await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
      await tester.pumpAndSettle();

      expect(find.text('Use at least 8 characters.'), findsOneWidget);
      expect(find.text('The passwords do not match.'), findsOneWidget);
      final confirm = find.widgetWithText(FilledButton, 'Confirm');
      expect(
        tester.getRect(confirm).bottom,
        lessThanOrEqualTo(tester.view.physicalSize.height - 300),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('security panel keeps existing actions touch-sized', (
    tester,
  ) async {
    final harness = SecurityHarness('password43-panel');
    addTearDown(harness.dispose);
    tester.view
      ..physicalSize = const Size(360, 740)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(harness.initialize);
    final note = await tester.runAsync(() => harness.app.readNote('alpha'));
    final actions = <NoteSecurityAction>[];

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(1.7)),
          child: child!,
        ),
        home: Scaffold(
          body: NoteSecurityPanel(
            note: note!,
            locked: false,
            busy: false,
            serverAvailable: true,
            canManage: true,
            retained: false,
            onAction: actions.add,
          ),
        ),
      ),
    );

    final enable = find.byKey(const ValueKey('note-security-enable'));
    expect(enable, findsOneWidget);
    expect(tester.getSize(enable).height, greaterThanOrEqualTo(48));
    await tester.tap(enable);
    expect(actions, [NoteSecurityAction.enable]);
    expect(tester.takeException(), isNull);
  });
}
