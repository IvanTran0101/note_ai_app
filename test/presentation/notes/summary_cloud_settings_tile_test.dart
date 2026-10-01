import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:note_ai_app/application/auth/current_user_session.dart';
import 'package:note_ai_app/application/note_intelligence/summary_cloud_consent.dart';
import 'package:note_ai_app/application/note_intelligence/summary_consent_app_service.dart';
import 'package:note_ai_app/application/note_intelligence/summary_run_context.dart';
import 'package:note_ai_app/domain/auth/auth_identity.dart';
import 'package:note_ai_app/presentation/notes/note_detail_localizations.dart';
import 'package:note_ai_app/presentation/notes/summary_cloud_settings_tile.dart';

const ValueKey<String> _switchKey = ValueKey<String>(
  'summary-cloud-consent-switch',
);
const ValueKey<String> _dialogKey = ValueKey<String>('summary-consent-dialog');
const ValueKey<String> _cancelKey = ValueKey<String>('summary-consent-cancel');
const ValueKey<String> _allowKey = ValueKey<String>('summary-consent-allow');
const ValueKey<String> _errorKey = ValueKey<String>(
  'summary-cloud-consent-error',
);

AuthIdentity _identity(String userId) {
  return AuthIdentity(
    userId: userId,
    email: '$userId@example.com',
    isEmailVerified: true,
  );
}

/// Real session, consent store, and service wired like the composition root.
final class _Harness {
  _Harness({this.requiresCloudConsent = true}) {
    consent = SummaryCloudConsent(session: session);
    service = SummaryConsentAppService(
      currentUser: session,
      session: session,
      consent: consent,
      isAvailable: () => available,
      cancelActiveRuns: () {
        cancelCalls++;
        onCancel?.call();
      },
      requiresCloudConsent: requiresCloudConsent,
    );
  }

  final bool requiresCloudConsent;
  final CurrentUserSession session = CurrentUserSession();
  late final SummaryCloudConsent consent;
  late final SummaryConsentAppService service;
  bool available = true;
  int cancelCalls = 0;
  void Function()? onCancel;

  void signIn(String userId) => session.setIdentity(_identity(userId));
  void signOut() => session.clear();

  SummaryCloudConsentSnapshot capture(String userId) {
    return consent.capture(
      accountUserId: userId,
      sessionGeneration: session.sessionGeneration,
    );
  }
}

Widget _app({
  required SummaryConsentAppService service,
  required ValueNotifier<Locale?> locale,
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
          body: SingleChildScrollView(
            child: SummaryCloudSettingsTile(service: service),
          ),
        ),
      );
    },
  );
}

ValueNotifier<Locale?> _locale(Locale? initial) {
  final ValueNotifier<Locale?> locale = ValueNotifier<Locale?>(initial);
  addTearDown(locale.dispose);
  return locale;
}

SwitchListTile _switch(WidgetTester tester) {
  return tester.widget<SwitchListTile>(find.byKey(_switchKey));
}

Future<void> _tapSwitch(WidgetTester tester) async {
  await tester.tap(find.byKey(_switchKey));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('hides itself when the composition does not require consent', (
    WidgetTester tester,
  ) async {
    final _Harness h = _Harness(requiresCloudConsent: false)..signIn('user-a');

    await tester.pumpWidget(
      _app(service: h.service, locale: _locale(const Locale('en'))),
    );

    expect(find.byKey(_switchKey), findsNothing);
    expect(find.text('Cloud summaries'), findsNothing);
    expect(find.byKey(_dialogKey), findsNothing);
  });

  testWidgets('disables the switch and shows the safe reason', (
    WidgetTester tester,
  ) async {
    final _Harness h = _Harness()..signIn('user-a');
    h.available = false;
    final ValueNotifier<Locale?> locale = _locale(const Locale('en'));

    await tester.pumpWidget(_app(service: h.service, locale: locale));

    expect(_switch(tester).value, isFalse);
    expect(_switch(tester).onChanged, isNull);
    expect(
      find.text('Summaries are not available in this setup.'),
      findsOneWidget,
    );

    final _Harness signedOut = _Harness();

    await tester.pumpWidget(_app(service: signedOut.service, locale: locale));

    expect(_switch(tester).onChanged, isNull);
    expect(find.text('Sign in again to summarize.'), findsOneWidget);
  });

  testWidgets('off to on asks for confirmation and Cancel grants nothing', (
    WidgetTester tester,
  ) async {
    final _Harness h = _Harness()..signIn('user-a');

    await tester.pumpWidget(
      _app(service: h.service, locale: _locale(const Locale('en'))),
    );
    await _tapSwitch(tester);

    expect(find.byKey(_dialogKey), findsOneWidget);
    expect(h.consent.generation, 0);

    await tester.tap(find.byKey(_cancelKey));
    await tester.pumpAndSettle();

    expect(h.service.state, SummaryConsentStatus.consentRequired);
    expect(h.capture('user-a').isGranted, isFalse);
    expect(h.consent.generation, 0);
    expect(_switch(tester).value, isFalse);
  });

  testWidgets('Allow grants the captured account and turns the switch on', (
    WidgetTester tester,
  ) async {
    final _Harness h = _Harness()..signIn('user-a');

    await tester.pumpWidget(
      _app(service: h.service, locale: _locale(const Locale('en'))),
    );
    await _tapSwitch(tester);
    await tester.tap(find.byKey(_allowKey));
    await tester.pumpAndSettle();

    expect(h.service.state, SummaryConsentStatus.granted);
    expect(h.capture('user-a').isGranted, isTrue);
    expect(h.consent.generation, 1);
    expect(_switch(tester).value, isTrue);
    expect(find.text('This session'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('turning a grant off revokes and cancels active runs at once', (
    WidgetTester tester,
  ) async {
    final _Harness h = _Harness()..signIn('user-a');
    h.service.grantConsent(h.service.beginConsent());
    final SummaryRunScope scope = SummaryRunScope();
    h.onCancel = () =>
        scope.cancel(reason: SummaryRunFailureCode.consentRequired);

    await tester.pumpWidget(
      _app(service: h.service, locale: _locale(const Locale('en'))),
    );
    expect(_switch(tester).value, isTrue);

    await _tapSwitch(tester);

    expect(find.byKey(_dialogKey), findsNothing);
    expect(h.cancelCalls, 1);
    expect(scope.isCancelled, isTrue);
    expect(scope.cancelReason, SummaryRunFailureCode.consentRequired);
    expect(h.service.state, SummaryConsentStatus.consentRequired);
    expect(_switch(tester).value, isFalse);
  });

  testWidgets('a session change while the dialog is open grants nothing', (
    WidgetTester tester,
  ) async {
    final _Harness h = _Harness()..signIn('user-a');

    await tester.pumpWidget(
      _app(service: h.service, locale: _locale(const Locale('en'))),
    );
    await _tapSwitch(tester);
    expect(find.byKey(_dialogKey), findsOneWidget);

    h.signIn('user-b');
    await tester.tap(find.byKey(_allowKey));
    await tester.pumpAndSettle();

    expect(find.byKey(_errorKey), findsOneWidget);
    expect(
      find.text('The account or session changed. Please try again.'),
      findsOneWidget,
    );
    expect(h.service.state, SummaryConsentStatus.consentRequired);
    expect(h.capture('user-b').isGranted, isFalse);
    expect(_switch(tester).value, isFalse);
  });

  testWidgets('a revoke while the dialog is open makes the request stale', (
    WidgetTester tester,
  ) async {
    final _Harness h = _Harness()..signIn('user-a');

    await tester.pumpWidget(
      _app(service: h.service, locale: _locale(const Locale('en'))),
    );
    await _tapSwitch(tester);

    h.service.revokeConsent();
    await tester.tap(find.byKey(_allowKey));
    await tester.pumpAndSettle();

    expect(find.byKey(_errorKey), findsOneWidget);
    expect(find.text('Cloud summary permission is required.'), findsOneWidget);
    expect(h.service.state, SummaryConsentStatus.consentRequired);
    expect(_switch(tester).value, isFalse);
  });

  testWidgets('a runtime that goes away while open reports unavailable', (
    WidgetTester tester,
  ) async {
    final _Harness h = _Harness()..signIn('user-a');

    await tester.pumpWidget(
      _app(service: h.service, locale: _locale(const Locale('en'))),
    );
    await _tapSwitch(tester);

    h.available = false;
    await tester.tap(find.byKey(_allowKey));
    await tester.pumpAndSettle();

    // The state line now carries the reason, so no duplicate error line.
    expect(find.byKey(_errorKey), findsNothing);
    expect(
      find.text('Summaries are not available in this setup.'),
      findsOneWidget,
    );
    expect(h.service.state, SummaryConsentStatus.unavailable);
    expect(_switch(tester).value, isFalse);
    expect(_switch(tester).onChanged, isNull);
  });

  testWidgets('a pending confirmation disables the switch against a second', (
    WidgetTester tester,
  ) async {
    final _Harness h = _Harness()..signIn('user-a');

    await tester.pumpWidget(
      _app(service: h.service, locale: _locale(const Locale('en'))),
    );
    await _tapSwitch(tester);

    expect(find.byKey(_dialogKey), findsOneWidget);
    expect(_switch(tester).onChanged, isNull);

    await tester.tap(find.byKey(_allowKey));
    await tester.pumpAndSettle();

    expect(find.byKey(_dialogKey), findsNothing);
    expect(h.consent.generation, 1, reason: 'exactly one grant');
  });

  testWidgets('locale changes retranslate the tile without losing consent', (
    WidgetTester tester,
  ) async {
    final _Harness h = _Harness()..signIn('user-a');
    final ValueNotifier<Locale?> locale = _locale(const Locale('vi'));

    await tester.pumpWidget(_app(service: h.service, locale: locale));
    expect(find.text('Tóm tắt trên đám mây'), findsOneWidget);

    await _tapSwitch(tester);
    expect(find.text('Cho phép'), findsOneWidget);
    await tester.tap(find.byKey(_allowKey));
    await tester.pumpAndSettle();
    expect(h.service.state, SummaryConsentStatus.granted);
    expect(find.text('Phiên hiện tại'), findsOneWidget);

    locale.value = const Locale('en');
    await tester.pumpAndSettle();

    expect(find.text('Cloud summaries'), findsOneWidget);
    expect(find.text('This session'), findsOneWidget);
    expect(h.service.state, SummaryConsentStatus.granted);
    expect(_switch(tester).value, isTrue);
  });

  testWidgets('keeps its disclosure reachable at 320dp with large text', (
    WidgetTester tester,
  ) async {
    tester.view
      ..physicalSize = const Size(320, 640)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final _Harness h = _Harness()..signIn('user-a');

    await tester.pumpWidget(
      _app(
        service: h.service,
        locale: _locale(const Locale('en')),
        textScale: 2,
      ),
    );
    await _tapSwitch(tester);

    expect(find.textContaining('DeepSeek'), findsOneWidget);
    expect(find.byKey(_allowKey), findsOneWidget);
    expect(find.byKey(_cancelKey), findsOneWidget);
    final Rect rect = tester.getRect(
      find
          .descendant(
            of: find.byKey(_dialogKey),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(rect.width, lessThanOrEqualTo(320));
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(320));
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(_allowKey));
    await tester.pumpAndSettle();
    expect(h.service.state, SummaryConsentStatus.granted);
  });
}
