import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/domain/note_intelligence/rag_models.dart';
import 'package:note_ai_app/presentation/rag/rag_copy.dart';

Future<RagCopy> _resolve(
  WidgetTester tester, {
  Locale? locale,
  Locale? systemLocale,
  bool withDelegate = true,
}) async {
  if (systemLocale != null) {
    tester.binding.platformDispatcher.localesTestValue = <Locale>[
      systemLocale,
    ];
    addTearDown(
      tester.binding.platformDispatcher.clearLocalesTestValue,
    );
  }
  late RagCopy copy;
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: <LocalizationsDelegate<dynamic>>[
        if (withDelegate) RagCopy.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const <Locale>[Locale('en'), Locale('vi')],
      home: Builder(
        builder: (BuildContext context) {
          copy = RagCopy.of(context);
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  return copy;
}

void main() {
  group('RagCopy.of', () {
    testWidgets('uses the delegate for en and vi', (
      WidgetTester tester,
    ) async {
      final RagCopy en = await _resolve(tester, locale: const Locale('en'));
      expect(en.pageTitle, 'Ask your notes');
      expect(en.ask, 'Ask');
      expect(en.consentDialogAllow, 'Allow');

      final RagCopy vi = await _resolve(tester, locale: const Locale('vi'));
      expect(vi.pageTitle, 'Hỏi ghi chú');
      expect(vi.ask, 'Hỏi');
      expect(vi.consentDialogAllow, 'Cho phép');
    });

    testWidgets('falls back to the resolved locale without a delegate', (
      WidgetTester tester,
    ) async {
      final RagCopy vi = await _resolve(
        tester,
        locale: const Locale('vi'),
        withDelegate: false,
      );
      expect(vi.ask, 'Hỏi');

      final RagCopy en = await _resolve(
        tester,
        locale: const Locale('en'),
        withDelegate: false,
      );
      expect(en.ask, 'Ask');
    });

    testWidgets('follows the system locale when no locale is pinned', (
      WidgetTester tester,
    ) async {
      final RagCopy vi = await _resolve(
        tester,
        systemLocale: const Locale('vi'),
        withDelegate: false,
      );
      expect(vi.ask, 'Hỏi');

      final RagCopy en = await _resolve(
        tester,
        systemLocale: const Locale('en'),
        withDelegate: false,
      );
      expect(en.ask, 'Ask');
    });
  });

  group('consent disclosure', () {
    testWidgets('names the processors, included scope, and exclusions', (
      WidgetTester tester,
    ) async {
      final RagCopy copy = await _resolve(tester, locale: const Locale('en'));
      final String disclosure = copy.consentDisclosure;
      expect(disclosure, contains('Cohere'));
      expect(disclosure, contains('AWS'));
      expect(disclosure, contains('TypeSafe JEV'));
      expect(disclosure, contains('DeepSeek'));
      expect(disclosure, contains('shared with you'));
      expect(disclosure, contains('attachments'));
      expect(disclosure, contains('local drafts'));
      expect(disclosure, contains('off by default'));
      expect(disclosure, contains('does not revoke'));
      expect(disclosure, contains('stops new requests'));
      expect(disclosure, contains('already-billed'));
    });

    testWidgets('has a Vietnamese disclosure that is not the English text', (
      WidgetTester tester,
    ) async {
      final RagCopy vi = await _resolve(tester, locale: const Locale('vi'));
      final RagCopy en = await _resolve(tester, locale: const Locale('en'));
      expect(vi.consentDisclosure, contains('Cohere'));
      expect(vi.consentDisclosure, contains('DeepSeek'));
      expect(vi.consentDisclosure, isNot(equals(en.consentDisclosure)));
    });
  });

  group('failure copy', () {
    testWidgets('is exhaustive, localized, and never leaks a raw code', (
      WidgetTester tester,
    ) async {
      final RagCopy en = await _resolve(tester, locale: const Locale('en'));
      final RagCopy vi = await _resolve(tester, locale: const Locale('vi'));
      for (final RagFailureCode code in RagFailureCode.values) {
        final String english = en.failureCodeMessage(code);
        final String vietnamese = vi.failureCodeMessage(code);
        expect(english.trim(), isNotEmpty, reason: code.name);
        expect(vietnamese.trim(), isNotEmpty, reason: code.name);
        expect(english, isNot(contains('RagFailureCode')));
        expect(english, isNot(equals(code.name)));
      }
      // Index-not-ready and quota must be distinct states, not one generic text.
      expect(
        en.failureCodeMessage(RagFailureCode.indexNotReady),
        isNot(equals(en.failureCodeMessage(RagFailureCode.rateLimited))),
      );
      expect(
        en.failureCodeMessage(RagFailureCode.rateLimited),
        isNot(equals(en.failureCodeMessage(RagFailureCode.unexpected))),
      );
    });

    testWidgets('appends only a bounded retry hint for rate limiting', (
      WidgetTester tester,
    ) async {
      final RagCopy en = await _resolve(tester, locale: const Locale('en'));
      final RagFailure hinted = const RagFailure(
        RagFailureCode.rateLimited,
        retryAfterSeconds: 7,
      );
      expect(en.failureMessage(hinted), contains('7'));
      final RagFailure unbounded = const RagFailure(
        RagFailureCode.rateLimited,
        retryAfterSeconds: 0,
      );
      expect(en.failureMessage(unbounded), isNot(contains('0')));
      final RagFailure other = const RagFailure(
        RagFailureCode.timeout,
        retryAfterSeconds: 9,
      );
      expect(en.failureMessage(other), isNot(contains('9')));
    });
  });
}
