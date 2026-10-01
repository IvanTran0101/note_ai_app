import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:note_ai_app/presentation/notes/note_detail_localizations.dart';
import 'package:note_ai_app/presentation/notes/summary_consent_dialog.dart';

const ValueKey<String> _triggerKey = ValueKey<String>('open-consent');
const ValueKey<String> _dialogKey = ValueKey<String>('summary-consent-dialog');
const ValueKey<String> _cancelKey = ValueKey<String>('summary-consent-cancel');
const ValueKey<String> _allowKey = ValueKey<String>('summary-consent-allow');

/// Hosts the helper behind one trigger and records every decision it returns.
Widget _host({
  required ValueNotifier<Locale?> locale,
  required List<bool> results,
  double textScale = 1,
}) {
  return ValueListenableBuilder<Locale?>(
    valueListenable: locale,
    builder: (BuildContext context, Locale? value, Widget? child) {
      return MaterialApp(
        locale: value,
        supportedLocales: const <Locale>[Locale('en'), Locale('vi')],
        localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
          NoteDetailCopy.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (BuildContext context, Widget? child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: Center(
            child: Builder(
              builder: (BuildContext context) => TextButton(
                key: _triggerKey,
                onPressed: () async {
                  results.add(await showSummaryConsentDialog(context));
                },
                child: const Text('Open consent dialog'),
              ),
            ),
          ),
        ),
      );
    },
  );
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.byKey(_triggerKey));
  await tester.pumpAndSettle();
}

Rect _dialogSurfaceRect(WidgetTester tester) {
  return tester.getRect(
    find
        .descendant(of: find.byKey(_dialogKey), matching: find.byType(Material))
        .first,
  );
}

void _expectDialogFitsViewport(WidgetTester tester) {
  final Rect rect = _dialogSurfaceRect(tester);
  final Size viewport = tester.view.physicalSize / tester.view.devicePixelRatio;
  expect(rect.width, lessThanOrEqualTo(320));
  expect(rect.left, greaterThanOrEqualTo(0));
  expect(rect.top, greaterThanOrEqualTo(0));
  expect(rect.right, lessThanOrEqualTo(viewport.width));
  expect(rect.bottom, lessThanOrEqualTo(viewport.height));
}

ValueNotifier<Locale?> _locale(Locale? initial) {
  final ValueNotifier<Locale?> locale = ValueNotifier<Locale?>(initial);
  addTearDown(locale.dispose);
  return locale;
}

void main() {
  testWidgets('shows the truthful disclosure, scope, and frozen keys', (
    WidgetTester tester,
  ) async {
    final List<bool> results = <bool>[];

    await tester.pumpWidget(
      _host(locale: _locale(const Locale('en')), results: results),
    );
    await _open(tester);

    expect(find.byKey(_dialogKey), findsOneWidget);
    expect(find.byKey(_cancelKey), findsOneWidget);
    expect(find.byKey(_allowKey), findsOneWidget);
    expect(find.text('Cloud summaries'), findsOneWidget);
    expect(find.text('This session'), findsOneWidget);
    expect(find.textContaining('DeepSeek'), findsOneWidget);
    expect(find.textContaining('does not retract'), findsOneWidget);
    expect(find.textContaining('zero retention'), findsOneWidget);
    expect(find.textContaining('RAG'), findsOneWidget);
    _expectDialogFitsViewport(tester);
    expect(results, isEmpty, reason: 'opening a dialog is not a decision');
    expect(tester.takeException(), isNull);
  });

  testWidgets('returns true only for Allow and false for Cancel', (
    WidgetTester tester,
  ) async {
    final List<bool> results = <bool>[];

    await tester.pumpWidget(
      _host(locale: _locale(const Locale('en')), results: results),
    );

    await _open(tester);
    await tester.tap(find.byKey(_allowKey));
    await tester.pumpAndSettle();
    expect(results, <bool>[true]);
    expect(find.byKey(_dialogKey), findsNothing);

    await _open(tester);
    await tester.tap(find.byKey(_cancelKey));
    await tester.pumpAndSettle();
    expect(results, <bool>[true, false]);
    expect(find.byKey(_dialogKey), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('barrier tap, Escape, and system back all resolve to false', (
    WidgetTester tester,
  ) async {
    final List<bool> results = <bool>[];

    await tester.pumpWidget(
      _host(locale: _locale(const Locale('en')), results: results),
    );

    await _open(tester);
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(results, <bool>[false]);

    await _open(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(results, <bool>[false, false]);

    await _open(tester);
    final ByteData message = const JSONMethodCodec().encodeMethodCall(
      const MethodCall('popRoute'),
    );
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      SystemChannels.navigation.name,
      message,
      (_) {},
    );
    await tester.pumpAndSettle();
    expect(results, <bool>[false, false, false]);
    expect(find.byKey(_dialogKey), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a Vietnamese device locale renders Vietnamese copy', (
    WidgetTester tester,
  ) async {
    tester.platformDispatcher.localeTestValue = const Locale('vi');
    tester.platformDispatcher.localesTestValue = const <Locale>[Locale('vi')];
    addTearDown(tester.platformDispatcher.clearLocaleTestValue);
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    final List<bool> results = <bool>[];

    await tester.pumpWidget(_host(locale: _locale(null), results: results));
    await _open(tester);

    expect(find.text('Tóm tắt trên đám mây'), findsOneWidget);
    expect(find.text('Cho phép'), findsOneWidget);
    expect(find.text('Phiên hiện tại'), findsOneWidget);
    expect(find.text('Allow'), findsNothing);
  });

  testWidgets('an unsupported device locale falls back to English', (
    WidgetTester tester,
  ) async {
    tester.platformDispatcher.localeTestValue = const Locale('fr');
    tester.platformDispatcher.localesTestValue = const <Locale>[Locale('fr')];
    addTearDown(tester.platformDispatcher.clearLocaleTestValue);
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    final List<bool> results = <bool>[];

    await tester.pumpWidget(_host(locale: _locale(null), results: results));
    await _open(tester);

    expect(find.text('Cloud summaries'), findsOneWidget);
    expect(find.text('Allow'), findsOneWidget);
  });

  testWidgets('an explicit app locale overrides the device locale', (
    WidgetTester tester,
  ) async {
    tester.platformDispatcher.localeTestValue = const Locale('vi');
    tester.platformDispatcher.localesTestValue = const <Locale>[Locale('vi')];
    addTearDown(tester.platformDispatcher.clearLocaleTestValue);
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    final List<bool> results = <bool>[];

    await tester.pumpWidget(
      _host(locale: _locale(const Locale('en')), results: results),
    );
    await _open(tester);

    expect(find.text('Cloud summaries'), findsOneWidget);
    expect(find.text('Allow'), findsOneWidget);
    expect(find.text('Cho phép'), findsNothing);
  });

  testWidgets('a locale change while open retranslates the same dialog', (
    WidgetTester tester,
  ) async {
    final ValueNotifier<Locale?> locale = _locale(const Locale('en'));
    final List<bool> results = <bool>[];

    await tester.pumpWidget(_host(locale: locale, results: results));
    await _open(tester);
    expect(find.text('Allow'), findsOneWidget);

    locale.value = const Locale('vi');
    await tester.pumpAndSettle();

    expect(find.byKey(_dialogKey), findsOneWidget);
    expect(find.text('Cho phép'), findsOneWidget);
    expect(find.text('Allow'), findsNothing);
    expect(results, isEmpty, reason: 'a language change is not a decision');

    await tester.tap(find.byKey(_allowKey));
    await tester.pumpAndSettle();
    expect(results, <bool>[true]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('stays within 320dp on a wide viewport', (
    WidgetTester tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1200, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final List<bool> results = <bool>[];

    await tester.pumpWidget(
      _host(locale: _locale(const Locale('en')), results: results),
    );
    await _open(tester);

    final Rect rect = _dialogSurfaceRect(tester);
    expect(rect.width, lessThanOrEqualTo(320));
    expect(rect.width, greaterThanOrEqualTo(240));
    expect(tester.takeException(), isNull);
  });

  testWidgets('fits a narrow phone and scrolls at large text scale', (
    WidgetTester tester,
  ) async {
    tester.view
      ..physicalSize = const Size(320, 640)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final List<bool> results = <bool>[];

    await tester.pumpWidget(
      _host(
        locale: _locale(const Locale('en')),
        results: results,
        textScale: 2,
      ),
    );
    await _open(tester);

    expect(
      find.descendant(
        of: find.byKey(_dialogKey),
        matching: find.byType(SingleChildScrollView),
      ),
      findsOneWidget,
    );
    expect(find.byKey(_allowKey), findsOneWidget);
    expect(find.byKey(_cancelKey), findsOneWidget);
    _expectDialogFitsViewport(tester);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(_allowKey));
    await tester.pumpAndSettle();
    expect(results, <bool>[true]);
  });

  testWidgets('exposes both actions as enabled buttons with one intent', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    final List<bool> results = <bool>[];

    await tester.pumpWidget(
      _host(locale: _locale(const Locale('en')), results: results),
    );
    await _open(tester);

    expect(find.bySemanticsLabel('Allow'), findsOneWidget);
    expect(find.bySemanticsLabel('Cancel'), findsOneWidget);
    final SemanticsNode allowNode = tester.getSemantics(find.byKey(_allowKey));
    expect(allowNode.flagsCollection.isButton, isTrue);
    expect(
      tester.widget<FilledButton>(find.byKey(_allowKey)).onPressed,
      isNotNull,
    );
    expect(
      tester.widget<TextButton>(find.byKey(_cancelKey)).onPressed,
      isNotNull,
    );
    expect(find.byKey(_dialogKey), findsOneWidget);

    await tester.tap(find.byKey(_allowKey));
    await tester.pumpAndSettle();
    semantics.dispose();
    expect(results, <bool>[true], reason: 'exactly one decision per dialog');
    expect(find.byKey(_dialogKey), findsNothing);
  });
}
