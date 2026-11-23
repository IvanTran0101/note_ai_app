/// Widget-test harness for the RAG presentation slice.
///
/// The gateway is the shared synthetic [FakeRagGateway] from the Application
/// suite (no network, no provider), the service is a real [RagAppService], and
/// the identity is the real [CurrentUserSession], so the widget tests exercise
/// the same session/generation binding the app uses. All fixtures are
/// synthetic; nothing here opens a socket or a model.
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/auth/current_user_session.dart';
import 'package:note_ai_app/application/note_intelligence/rag_app_service.dart';
import 'package:note_ai_app/application/sync/local_note_state.dart';
import 'package:note_ai_app/application/sync/local_sync_state.dart';
import 'package:note_ai_app/domain/auth/auth_identity.dart';
import 'package:note_ai_app/domain/note_intelligence/rag_models.dart';
import 'package:note_ai_app/presentation/notes/notes_theme_tokens.dart';
import 'package:note_ai_app/presentation/rag/rag_consent_settings_tile.dart';
import 'package:note_ai_app/presentation/rag/rag_copy.dart';
import 'package:note_ai_app/presentation/rag/rag_page.dart';

import '../../application/note_intelligence/rag_test_support.dart';

export '../../application/note_intelligence/rag_test_support.dart';
export 'package:note_ai_app/application/sync/local_note_state.dart';

/// Locales the app supports for the RAG surface.
const List<Locale> ragTestLocales = <Locale>[Locale('en'), Locale('vi')];

/// App localization delegates used by the presentation tests.
const List<LocalizationsDelegate<dynamic>> ragTestDelegates =
    <LocalizationsDelegate<dynamic>>[
      RagCopy.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ];

/// The house theme with the Notion-inspired token extension.
ThemeData ragTestTheme() => ThemeData(
  extensions: <ThemeExtension<dynamic>>[NoteFlowUiTokens.light()],
);

/// One wired real service over a scripted fake gateway and a real session.
final class RagPresentationHarness {
  /// Creates the harness; the local state defaults to one eligible note.
  RagPresentationHarness({
    List<Object>? consentScript,
    List<Object>? writeScript,
    List<Object>? queryScript,
    LocalSyncState? local,
    String userId = 'user-1',
  }) : gateway = FakeRagGateway(
         consentScript: consentScript,
         writeScript: writeScript,
         queryScript: queryScript,
       ),
       local =
           local ??
           localState(notes: <LocalNoteState>[ownedNote(ownerId: userId)]) {
    session = CurrentUserSession()
      ..setIdentity(
        AuthIdentity(
          userId: userId,
          email: '$userId@example.test',
          isEmailVerified: true,
        ),
      );
    service = RagAppService(
      gateway: gateway,
      currentUser: session,
      session: session,
      readLocalState: (String actorId) async => this.local,
    );
  }

  /// The synthetic gateway every call is recorded on.
  final FakeRagGateway gateway;

  /// The mutable local sync state the service re-reads.
  LocalSyncState local;

  /// The real session identity and generation source.
  late final CurrentUserSession session;

  /// The wired real application service.
  late final RagAppService service;

  /// Grants the canonical consent and lets the service adopt it.
  Future<void> grant({int generation = 1}) async {
    gateway.consentScript
      ..clear()
      ..add(RagConsent(accepted: true, generation: generation));
    await service.refreshConsent();
  }
}

/// Pumps [RagPage] over [harness] inside the house app shell.
Future<void> pumpRagPage(
  WidgetTester tester,
  RagPresentationHarness harness, {
  RagScope? scope,
  Future<bool> Function(RagSource source)? onOpenSource,
  Locale? locale,
  TextScaler? textScaler,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: ragTestDelegates,
      supportedLocales: ragTestLocales,
      theme: ragTestTheme(),
      builder: (BuildContext context, Widget? child) {
        final MediaQueryData data = MediaQuery.of(context);
        return MediaQuery(
          data: textScaler == null
              ? data
              : data.copyWith(textScaler: textScaler),
          child: child!,
        );
      },
      home: RagPage(
        service: harness.service,
        initialScope: scope ?? const RagScope.account(),
        onOpenSource: onOpenSource ?? (RagSource _) async => true,
      ),
    ),
  );
}

/// Pumps the consent settings tile over [harness] inside a [Scaffold].
Future<void> pumpRagConsentTile(
  WidgetTester tester,
  RagPresentationHarness harness, {
  Locale? locale,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: ragTestDelegates,
      supportedLocales: ragTestLocales,
      theme: ragTestTheme(),
      home: Scaffold(
        body: RagConsentSettingsTile(service: harness.service),
      ),
    ),
  );
}

/// Reads the switch value of the consent tile.
bool ragConsentSwitchValue(WidgetTester tester) {
  return tester
      .widget<SwitchListTile>(find.byKey(RagConsentSettingsTile.switchKey))
      .value;
}

/// Taps the consent tile's switch.
Future<void> tapRagConsentSwitch(WidgetTester tester) async {
  await tester.tap(find.byKey(RagConsentSettingsTile.switchKey));
  await tester.pumpAndSettle();
}
