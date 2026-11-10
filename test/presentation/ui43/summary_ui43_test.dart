import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:note_ai_app/presentation/notes/note_detail_localizations.dart';
import 'package:note_ai_app/presentation/notes/note_summary_availability.dart';
import 'package:note_ai_app/presentation/notes/note_summary_content_motion.dart';
import 'package:note_ai_app/presentation/notes/note_summary_feedback.dart';
import 'package:note_ai_app/presentation/notes/notes_theme_tokens.dart';
import 'package:note_ai_app/presentation/notes/summary_consent_dialog.dart';

const Key _openConsentKey = ValueKey<String>('open-summary-consent');
const Key _summaryMotionKey = ValueKey<String>('summary-motion');

void main() {
  testWidgets(
    'summary feedback stays readable at narrow width, large text, and with IME inset',
    (WidgetTester tester) async {
      tester.view
        ..physicalSize = const Size(320, 500)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final NoteFlowUiTokens tokens = NoteFlowUiTokens.light();
      int cancelCount = 0;
      late NoteDetailCopy copy;

      await tester.pumpWidget(
        _testApp(
          textScale: 2,
          viewInsets: const EdgeInsets.only(bottom: 180),
          home: (BuildContext context) {
            copy = NoteDetailCopy.of(context);
            return Scaffold(
              body: SingleChildScrollView(
                child: SizedBox(
                  width: double.infinity,
                  child: NoteSummaryFeedback(
                    copy: copy,
                    availability: NoteSummaryAvailability.dirty,
                    cloud: false,
                    isRunning: true,
                    onCancel: () => cancelCount++,
                  ),
                ),
              ),
            );
          },
        ),
      );

      expect(find.byKey(NoteSummaryFeedback.progressKey), findsOneWidget);
      expect(find.byKey(NoteSummaryFeedback.cancelKey), findsOneWidget);
      expect(find.text(copy.summarySavedRequired), findsOneWidget);

      final Container notice = tester.widget<Container>(
        find.byKey(NoteSummaryFeedback.availabilityKey),
      );
      final BoxDecoration decoration = notice.decoration! as BoxDecoration;
      expect(decoration.color, isNull);
      expect(decoration.border, isA<Border>());
      expect((decoration.border! as Border).top.color, tokens.divider);

      final Text noticeText = tester.widget<Text>(
        find.text(copy.summarySavedRequired),
      );
      expect(noticeText.style?.color, tokens.textSecondary);
      expect(noticeText.style?.fontSize, greaterThanOrEqualTo(14));
      expect(tester.takeException(), isNull);

      await tester.ensureVisible(find.byKey(NoteSummaryFeedback.cancelKey));
      await tester.tap(find.byKey(NoteSummaryFeedback.cancelKey));
      expect(cancelCount, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'consent disclosure and actions remain reachable above the IME at 200% text',
    (WidgetTester tester) async {
      tester.view
        ..physicalSize = const Size(320, 500)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      late Future<bool> decision;
      await tester.pumpWidget(
        _testApp(
          textScale: 2,
          viewInsets: const EdgeInsets.only(bottom: 200),
          viewPadding: const EdgeInsets.only(top: 24, bottom: 24),
          home: (BuildContext context) => Scaffold(
            body: Center(
              child: TextButton(
                key: _openConsentKey,
                onPressed: () {
                  decision = showSummaryConsentDialog(context);
                },
                child: const Text('Open consent'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(_openConsentKey));
      await tester.pumpAndSettle();

      final Finder dialogFinder = find.byKey(
        const ValueKey<String>('summary-consent-dialog'),
      );
      final AlertDialog dialog = tester.widget<AlertDialog>(dialogFinder);
      expect(dialog.scrollable, isTrue);
      expect(
        find.descendant(
          of: dialogFinder,
          matching: find.byType(SingleChildScrollView),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: dialogFinder, matching: find.byType(Divider)),
        findsOneWidget,
      );

      final Finder dialogMaterial = find
          .descendant(of: dialogFinder, matching: find.byType(Material))
          .first;
      expect(tester.getRect(dialogMaterial).bottom, lessThanOrEqualTo(300));
      for (final Key key in <Key>[
        const ValueKey<String>('summary-consent-cancel'),
        const ValueKey<String>('summary-consent-allow'),
      ]) {
        expect(find.byKey(key), findsOneWidget);
        expect(tester.getRect(find.byKey(key)).bottom, lessThanOrEqualTo(300));
      }
      expect(tester.takeException(), isNull);

      await tester.tap(
        find.byKey(const ValueKey<String>('summary-consent-allow')),
      );
      await tester.pumpAndSettle();
      expect(await decision, isTrue);
    },
  );

  testWidgets('only explicit consent grants; cancel and barrier return false', (
    WidgetTester tester,
  ) async {
    tester.view
      ..physicalSize = const Size(360, 640)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    late Future<bool> decision;
    await tester.pumpWidget(
      _testApp(
        home: (BuildContext context) => Scaffold(
          body: Center(
            child: TextButton(
              key: _openConsentKey,
              onPressed: () {
                decision = showSummaryConsentDialog(context);
              },
              child: const Text('Open consent'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(_openConsentKey));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('summary-consent-cancel')),
    );
    await tester.pumpAndSettle();
    expect(await decision, isFalse);

    await tester.tap(find.byKey(_openConsentKey));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(await decision, isFalse);
  });

  testWidgets(
    'summary shimmer stops and resumes with platform reduced motion',
    (WidgetTester tester) async {
      final TextEditingController controller = TextEditingController(
        text: 'Summary text',
      );
      addTearDown(controller.dispose);

      Widget appWithMotionSetting(bool disableAnimations) {
        return _testApp(
          home: (BuildContext context) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(disableAnimations: disableAnimations),
            child: Scaffold(
              body: NoteSummaryContentMotion(
                key: _summaryMotionKey,
                active: true,
                controller: controller,
                textStyle: const TextStyle(color: Colors.black),
                child: const SizedBox(width: 200, height: 48),
              ),
            ),
          ),
        );
      }

      Finder animatedSummary() => find.descendant(
        of: find.byKey(_summaryMotionKey),
        matching: find.byType(AnimatedBuilder),
      );

      await tester.pumpWidget(appWithMotionSetting(true));
      expect(animatedSummary(), findsNothing);

      await tester.pumpWidget(appWithMotionSetting(false));
      await tester.pump(const Duration(milliseconds: 40));
      expect(animatedSummary(), findsOneWidget);

      await tester.pumpWidget(appWithMotionSetting(true));
      await tester.pump(const Duration(milliseconds: 40));
      expect(animatedSummary(), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

Widget _testApp({
  required WidgetBuilder home,
  double textScale = 1,
  EdgeInsets viewInsets = EdgeInsets.zero,
  EdgeInsets? viewPadding,
}) {
  return MaterialApp(
    theme: ThemeData(
      platform: TargetPlatform.android,
    ).copyWith(extensions: <ThemeExtension<dynamic>>[NoteFlowUiTokens.light()]),
    localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
      NoteDetailCopy.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const <Locale>[Locale('en'), Locale('vi')],
    builder: (BuildContext context, Widget? child) {
      final MediaQueryData mediaQuery = MediaQuery.of(context);
      return MediaQuery(
        data: mediaQuery.copyWith(
          textScaler: TextScaler.linear(textScale),
          viewInsets: viewInsets,
          viewPadding: viewPadding ?? mediaQuery.viewPadding,
        ),
        child: child!,
      );
    },
    home: Builder(builder: home),
  );
}
