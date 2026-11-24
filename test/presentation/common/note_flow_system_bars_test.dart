import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/presentation/common/note_flow_system_bars.dart';

void main() {
  testWidgets('system bars track theme without adding safe-area padding', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(412, 914)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final mode = ValueNotifier(ThemeMode.light);
    addTearDown(mode.dispose);
    const contentKey = ValueKey('content');
    await tester.pumpWidget(
      ValueListenableBuilder<ThemeMode>(
        valueListenable: mode,
        builder: (context, themeMode, _) => MaterialApp(
          theme: ThemeData.light(),
          darkTheme: ThemeData.dark(),
          themeMode: themeMode,
          builder: (context, child) => NoteFlowSystemBars(child: child!),
          home: const SizedBox.expand(key: contentKey),
        ),
      ),
    );

    SystemUiOverlayStyle currentStyle() => tester
        .widget<AnnotatedRegion<SystemUiOverlayStyle>>(
          find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
        )
        .value;
    expect(currentStyle().systemNavigationBarIconBrightness, Brightness.dark);
    expect(currentStyle().statusBarBrightness, Brightness.light);
    expect(currentStyle().systemNavigationBarContrastEnforced, isFalse);
    final originalRect = tester.getRect(find.byKey(contentKey));

    mode.value = ThemeMode.dark;
    await tester.pumpAndSettle();
    expect(currentStyle().systemNavigationBarIconBrightness, Brightness.light);
    expect(currentStyle().statusBarIconBrightness, Brightness.light);
    expect(currentStyle().statusBarBrightness, Brightness.dark);
    expect(
      currentStyle().systemNavigationBarColor,
      ThemeData.dark().colorScheme.surface,
    );
    expect(tester.getRect(find.byKey(contentKey)), originalRect);
    expect(tester.takeException(), isNull);
  });
}
