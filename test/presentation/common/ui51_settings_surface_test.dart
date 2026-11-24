import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/presentation/common/note_flow_settings.dart';
import 'package:note_ai_app/presentation/common/note_flow_web_settings.dart';
import 'package:note_ai_app/presentation/notes/notes_theme_tokens.dart';

void main() {
  testWidgets(
    'Web settings match reference frame and forward account actions',
    (tester) async {
      var profileCalls = 0;
      await _openSettings(
        tester,
        directWeb: true,
        profile: () => profileCalls++,
      );
      final frame = tester.getRect(
        find.byKey(const ValueKey('settings-web-frame')),
      );
      expect(frame, const Rect.fromLTWH(64, 50, 1152, 820));
      final title = tester.getRect(
        find.byKey(const ValueKey('settings-web-title')),
      );
      expect(title.left, closeTo(364, 1));
      expect(title.top, closeTo(86, 1));
      expect(title.height, closeTo(32, 1));
      expect(find.text('Profile'), findsOneWidget);
      await tester.tap(find.text('Profile'));
      await tester.pump();
      expect(profileCalls, 1);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('settings-web-frame')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('both Web settings panes scroll above IME at 200 percent', (
    tester,
  ) async {
    var logoutCalls = 0;
    await _openSettings(
      tester,
      directWeb: true,
      size: const Size(1280, 480),
      scale: 2,
      keyboard: 160,
      logout: () => logoutCalls++,
    );
    await tester.ensureVisible(find.text('Log out'));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.text('Log out')).bottom, lessThanOrEqualTo(270));
    await tester.tap(find.text('Log out'));
    await tester.pump();
    expect(logoutCalls, 1);
    await tester.ensureVisible(find.text('Final existing setting'));
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.text('Final existing setting')).bottom,
      lessThanOrEqualTo(270),
    );
    expect(tester.takeException(), isNull);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('compact settings retain 48dp account actions at scale$scale', (
      tester,
    ) async {
      var profileCalls = 0;
      final keyboard = scale > 1 ? 220.0 : 0.0;
      await _openSettings(
        tester,
        size: const Size(320, 640),
        scale: scale,
        keyboard: keyboard,
        profile: () => profileCalls++,
      );
      expect(find.byKey(const ValueKey('settings-web-frame')), findsNothing);
      expect(find.text('Settings'), findsOneWidget);
      await tester.ensureVisible(find.text('Profile'));
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.text('Profile')).bottom,
        lessThanOrEqualTo(640 - keyboard),
      );
      await tester.tap(find.text('Profile'));
      await tester.pump();
      expect(profileCalls, 1);
      expect(
        tester.getSize(find.widgetWithText(ListTile, 'Profile')).height,
        greaterThanOrEqualTo(48),
      );
      expect(
        tester.getSize(find.widgetWithText(ListTile, 'Log out')).height,
        greaterThanOrEqualTo(48),
      );
      expect(find.text('Change password'), findsOneWidget);
      expect(find.text('Log out'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Web settings resize to full compact page and back', (
    tester,
  ) async {
    var profileCalls = 0;
    await _openSettings(tester, profile: () => profileCalls++);
    expect(find.byKey(const ValueKey('settings-web-frame')), findsOneWidget);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('settings-web-title')))
          .data,
      'Appearance and language',
    );
    tester.view.physicalSize = const Size(1920, 1080);
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const ValueKey('settings-web-frame'))).width,
      closeTo(1512, 1),
    );
    final wideTitle = tester.getRect(
      find.byKey(const ValueKey('settings-web-title')),
    );
    expect(wideTitle.left, closeTo(672.4, 1));
    expect(wideTitle.width, closeTo(800, 1));
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('settings-web-frame')), findsNothing);
    expect(find.text('Settings'), findsOneWidget);
    await tester.ensureVisible(find.text('Profile'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Profile'));
    await tester.pump();
    expect(profileCalls, 1);
    tester.view.physicalSize = const Size(1280, 920);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('settings-web-frame')), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, skip: !kIsWeb);
  testWidgets('initial compact Web settings restore frame when widened', (
    tester,
  ) async {
    await _openSettings(tester, size: const Size(390, 844));
    expect(find.byKey(const ValueKey('settings-web-frame')), findsNothing);
    expect(find.text('Settings'), findsOneWidget);
    tester.view.physicalSize = const Size(1280, 920);
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.byKey(const ValueKey('settings-web-frame'))),
      const Rect.fromLTWH(64, 50, 1152, 820),
    );
    expect(tester.takeException(), isNull);
  }, skip: !kIsWeb);
}

Future<void> _openSettings(
  WidgetTester tester, {
  bool directWeb = false,
  Size size = const Size(1280, 920),
  double scale = 1,
  double keyboard = 0,
  VoidCallback? profile,
  VoidCallback? logout,
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        extensions: [NoteFlowUiTokens.light()],
        listTileTheme: const ListTileThemeData(minTileHeight: 44),
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale),
          viewInsets: EdgeInsets.only(bottom: keyboard),
          padding: const EdgeInsets.only(top: 24, bottom: 24),
        ),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () {
              Widget builder(BuildContext context) => directWeb
                  ? NoteFlowWebSettingsSurface(
                      subtitle:
                          'Choose the appearance and language on this device.',
                      accountActions: _actions(profile, logout),
                      children: _preferences(),
                    )
                  : NoteFlowSettingsSurface(
                      title: 'Appearance and language',
                      subtitle:
                          'Choose the appearance and language on this device.',
                      accountActions: _actions(profile, logout),
                      children: _preferences(),
                    );
              if (directWeb) {
                showNoteFlowWebSettings(context: context, builder: builder);
              } else {
                showNoteFlowSettings(context: context, builder: builder);
              }
            },
            child: const Text('Open settings'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open settings'));
  await tester.pumpAndSettle();
}

List<Widget> _preferences() => const [
  NoteFlowSettingsSectionTitle('Appearance'),
  Text('Existing Theme control'),
  SizedBox(height: 600),
  Text('Final existing setting'),
];

List<Widget> _actions(VoidCallback? profile, VoidCallback? logout) => [
  ListTile(title: const Text('Profile'), onTap: profile ?? () {}),
  ListTile(title: const Text('Change password'), onTap: () {}),
  ListTile(title: const Text('Log out'), onTap: logout ?? () {}),
];
