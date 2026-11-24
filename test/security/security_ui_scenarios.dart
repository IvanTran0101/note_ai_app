import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/notes/note_access.dart';
import 'package:note_ai_app/application/notes/note_application.dart';
import 'package:note_ai_app/application/notes/note_security_service.dart';
import 'package:note_ai_app/domain/note_intelligence/summary.dart';
import 'package:note_ai_app/application/note_intelligence/summary_run_context.dart';
import 'package:note_ai_app/domain/notes/note_protection.dart';
import 'package:note_ai_app/presentation/notes/note_detail_page.dart';

import 'security_fixtures.dart';
import 'local_first_scenarios.dart';
import 'security_harness.dart';
import '../presentation/editor/rich_editor_test_support.dart';

Future<void> _settleUntil(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 1200; i++) {
    await tester.pump(const Duration(milliseconds: 20));
    if (ready()) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
  }
  fail('security UI did not reach expected state');
}

Future<void> _idle(WidgetTester tester) async {
  await _settleUntil(
    tester,
    () =>
        find.byType(CircularProgressIndicator).evaluate().isEmpty &&
        find.byType(LinearProgressIndicator).evaluate().isEmpty,
  );
  await tester.pump(const Duration(milliseconds: 350));
}

Future<void> _show(
  WidgetTester tester,
  SecurityHarness h, {
  double textScale = 1,
}) async {
  // enterText synthesizes platform messages. A live browser keyboard can echo
  // its previous DOM value on blur and overwrite that synthetic input. Register
  // the test keyboard for this integration case; storage plugins remain real.
  if (kIsWeb && !tester.testTextInput.isRegistered) {
    tester.testTextInput.register();
    addTearDown(tester.testTextInput.unregister);
  }
  final note = await tester.runAsync(() => h.app.readNote('alpha'));
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('en'), Locale('vi')],
      home: NoteDetailPage(notesController: h.controller, note: note),
    ),
  );
  await _idle(tester);
}

Future<void> _securityAction(WidgetTester tester, String action) async {
  final button = find.byKey(ValueKey('note-security-$action'));
  if (button.evaluate().isEmpty) {
    final menu = find.byKey(const ValueKey('note-security-menu'));
    await _settleUntil(tester, () => menu.evaluate().isNotEmpty);
    await tester.tap(menu);
    await tester.pump(const Duration(milliseconds: 350));
  }
  await _settleUntil(tester, () {
    if (button.evaluate().isEmpty) return false;
    final widget = tester.widget(button);
    return widget is TextButton
        ? widget.onPressed != null
        : (widget as PopupMenuItem).enabled;
  });
  await tester.ensureVisible(button);
  await tester.pump(const Duration(milliseconds: 350));
  await tester.tap(button);
  await tester.pump(const Duration(milliseconds: 350));
}

Future<void> _dialog(WidgetTester tester, String action) async {
  await _securityAction(tester, action);
  await _settleUntil(
    tester,
    () => find.byType(AlertDialog).evaluate().isNotEmpty,
  );
  await tester.pump(const Duration(milliseconds: 350));
  expect(find.byType(AlertDialog), findsOneWidget);
}

Future<void> _passwords(WidgetTester tester, List<String> values) async {
  final fields = find.descendant(
    of: find.byType(AlertDialog),
    matching: find.byType(TextFormField),
  );
  for (var i = 0; i < values.length; i++) {
    await tester.ensureVisible(fields.at(i));
    await tester.enterText(fields.at(i), values[i]);
  }
}

Future<void> _confirm(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
  await tester.pump();
}

void registerSecurityUiScenarios({bool includeLocalFirst = false}) {
  if (includeLocalFirst) {
    testWidgets(
      'local-first UI enables, changes and disables offline without server availability',
      (tester) async {
        final h = SecurityHarness(
          'local-ui-${DateTime.now().microsecondsSinceEpoch}',
          localFirst: true,
          serverAvailable: false,
        );
        addTearDown(h.dispose);
        await tester.runAsync(h.initialize);
        await tester.runAsync(() => h.store.replace(unsynced(h.account)));
        await _show(tester, h);
        await _dialog(tester, 'enable');
        await _passwords(tester, [securityPassword, securityPassword]);
        await _confirm(tester);
        await _settleUntil(
          tester,
          () => find.byType(AlertDialog).evaluate().isEmpty,
        );
        await _idle(tester);
        expect(h.gateway.enableCalls, 0);
        expect(
          find.text(
            'Protection changes saved on this device, awaiting cloud sync.',
          ),
          findsOneWidget,
        );
        await _dialog(tester, 'change');
        await _passwords(tester, [
          securityPassword,
          'offline-ui-password',
          'offline-ui-password',
        ]);
        await _confirm(tester);
        await _settleUntil(
          tester,
          () => find.byType(AlertDialog).evaluate().isEmpty,
        );
        await _idle(tester);
        await _dialog(tester, 'disable');
        await _passwords(tester, ['offline-ui-password']);
        await _confirm(tester);
        await _settleUntil(
          tester,
          () => find.byType(AlertDialog).evaluate().isEmpty,
        );
        await _idle(tester);
        final note = await tester.runAsync(() => h.app.readNote('alpha'));
        expect(note!.isProtected, false);
        expect(note.content, privateBody);
        expect(h.gateway.enableCalls, 0);
        await tester.pumpWidget(const SizedBox.shrink());
      },
      timeout: const Timeout(Duration(minutes: 6)),
    );
  }
  testWidgets(
    'enable confirmation, wrong password, online unlock and lock scrub private editor',
    (tester) async {
      final h = SecurityHarness('security-ui');
      addTearDown(h.dispose);
      await tester.runAsync(h.initialize);
      await _show(tester, h);
      await _dialog(tester, 'enable');
      final fields = tester.widgetList<EditableText>(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(EditableText),
        ),
      );
      expect(fields.every((f) => f.obscureText), true);
      await _passwords(tester, [securityPassword, 'mismatch-password']);
      await _confirm(tester);
      expect(find.text('The passwords do not match.'), findsOneWidget);
      expect(h.gateway.enableCalls, 0);
      await _passwords(tester, [securityPassword, securityPassword]);
      await _confirm(tester);
      await _settleUntil(
        tester,
        () => find.byType(AlertDialog).evaluate().isEmpty,
      );
      await _idle(tester);
      await _securityAction(tester, 'lock');
      await _idle(tester);
      expect(find.byKey(NoteDetailPage.contentFieldKey), findsNothing);
      expect(find.text(privateTitle), findsNothing);
      expect(find.text(privateBody), findsNothing);
      await _dialog(tester, 'unlock');
      await _passwords(tester, ['wrong-password']);
      await _confirm(tester);
      await _settleUntil(
        tester,
        () => find.text('Incorrect password.').evaluate().isNotEmpty,
      );
      expect(find.byKey(NoteDetailPage.contentFieldKey), findsNothing);
      await _passwords(tester, [securityPassword]);
      await _confirm(tester);
      await _settleUntil(
        tester,
        () => find.byType(AlertDialog).evaluate().isEmpty,
      );
      await _settleUntil(
        tester,
        () => find.byKey(NoteDetailPage.contentFieldKey).evaluate().isNotEmpty,
      );
      expect(visibleRichEditor(tester).plainText, privateBody);
      h.session.clear();
      h.security.lock(null);
      await _idle(tester);
      expect(find.text(privateBody), findsNothing);
      expect(find.byKey(NoteDetailPage.contentFieldKey), findsNothing);
      h.security.lock(null);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  testWidgets(
    'security forms fit narrow viewport with keyboard and large text',
    (tester) async {
      final h = SecurityHarness('security-layout');
      addTearDown(h.dispose);
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(h.initialize);
      await _show(tester, h, textScale: 1.6);
      await _dialog(tester, 'enable');
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      addTearDown(tester.view.resetViewInsets);
      await tester.pump(const Duration(milliseconds: 350));
      await _passwords(tester, [securityPassword, securityPassword]);
      expect(tester.takeException(), isNull);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await _idle(tester);
      expect(tester.takeException(), isNull);
      h.security.lock(null);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('change, disable and OTP reset preserve security boundaries', (
    tester,
  ) async {
    final h = SecurityHarness('security-management');
    addTearDown(h.dispose);
    h.gateway.now = DateTime.now().toUtc();
    await tester.runAsync(() async {
      await h.initialize();
      await h.security.enable('alpha', securityPassword, securityPassword);
    });
    await _show(tester, h);
    await _dialog(tester, 'change');
    await _passwords(tester, [
      'wrong-password',
      'replacement-password',
      'replacement-password',
    ]);
    await _confirm(tester);
    await _settleUntil(
      tester,
      () => find.text('Incorrect password.').evaluate().isNotEmpty,
    );
    expect(h.gateway.password, securityPassword);
    await _passwords(tester, [
      securityPassword,
      'replacement-password',
      'replacement-password',
    ]);
    await _confirm(tester);
    await _settleUntil(
      tester,
      () => find.byType(AlertDialog).evaluate().isEmpty,
    );
    await _idle(tester);
    expect(h.gateway.password, 'replacement-password');
    await _dialog(tester, 'disable');
    await _passwords(tester, [securityPassword]);
    await _confirm(tester);
    await _settleUntil(
      tester,
      () => find.text('Incorrect password.').evaluate().isNotEmpty,
    );
    expect(h.gateway.protection.enabled, true);
    await _passwords(tester, ['replacement-password']);
    await _confirm(tester);
    await _settleUntil(
      tester,
      () => find.byType(AlertDialog).evaluate().isEmpty,
    );
    await _idle(tester);
    expect(h.gateway.protection.enabled, false);
    expect(visibleRichEditor(tester).plainText, privateBody);
    await _dialog(tester, 'enable');
    await _passwords(tester, [securityPassword, securityPassword]);
    await _confirm(tester);
    await _settleUntil(
      tester,
      () => find.byType(AlertDialog).evaluate().isEmpty,
    );
    await _idle(tester);
    await tester.runAsync(
      () => h.app.replaceContent(
        noteId: 'alpha',
        content: 'synthetic unsynced edit',
      ),
    );
    await _securityAction(tester, 'lock');
    await _idle(tester);
    await _dialog(tester, 'recover');
    await _settleUntil(
      tester,
      () =>
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Confirm'),
              )
              .onPressed !=
          null,
    );
    await _passwords(tester, [
      '000000',
      'recovered-password',
      'recovered-password',
    ]);
    await _confirm(tester);
    await _settleUntil(
      tester,
      () => find
          .text('The OTP is incorrect, expired or used. Request a new code.')
          .evaluate()
          .isNotEmpty,
    );
    expect(find.byKey(NoteDetailPage.contentFieldKey), findsNothing);
    await _passwords(tester, [
      '123456',
      'recovered-password',
      'recovered-password',
    ]);
    await _confirm(tester);
    await _settleUntil(
      tester,
      () => find.byType(AlertDialog).evaluate().isEmpty,
    );
    await _idle(tester);
    expect(h.gateway.password, 'recovered-password');
    expect(h.security.retainedPending('alpha'), true);
    h.security.lock(null);
    await tester.pumpWidget(const SizedBox.shrink());
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('locked operations and late Summary fail closed; offline lease lacks server authority', () async {
    final h = SecurityHarness('security-summary');
    addTearDown(h.dispose);
    await h.initialize();
    await h.security.enable('alpha', securityPassword, securityPassword);
    h.delayedSummary = Completer<Summary>();
    final run = h.app.summarizeNote('alpha');
    // Attach rejection observer before invalidating the in-flight request.
    final result = expectLater(
      run,
      throwsA(
        isA<SummaryRunFailure>().having(
          (e) => e.code,
          'code',
          SummaryRunFailureCode.noteLocked,
        ),
      ),
    );
    while (h.summaryCalls == 0) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    h.security.lock('alpha');
    h.delayedSummary!.complete(const Summary('late private output'));
    await result;
    await expectLater(
      h.app.readNote('alpha'),
      throwsA(isA<NoteSecurityFailure>()),
    );
    await expectLater(
      h.app.replaceContent(noteId: 'alpha', content: 'bypass'),
      throwsA(isA<NoteSecurityFailure>()),
    );
    await expectLater(
      h.app.deleteNote('alpha'),
      throwsA(isA<NoteSecurityFailure>()),
    );
    await h.security.unlock('alpha', securityPassword, offline: true);
    expect(h.gateway.lease, isNull);
    expect(
      () => h.security.requireRemote(
        'alpha',
        h.gateway.protection,
        NoteOperation.summary,
      ),
      throwsA(isA<NoteSecurityFailure>()),
    );
    final unlocked = await h.app.readNote('alpha');
    expect(unlocked.content, privateBody);
    h.gateway.now = h.gateway.now.add(const Duration(minutes: 15));
    await expectLater(
      h.app.readNote('alpha'),
      throwsA(isA<NoteSecurityFailure>()),
    );
  }, timeout: const Timeout(Duration(minutes: 5)));
}
