import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/presentation/editor/native_android_clipboard_menu.dart';

void main() {
  testWidgets(
    'shows touch-sized cut, copy, and paste actions above selection',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await _showMenu(
        tester,
        overlayTopInset: 60,
        anchors: const TextSelectionToolbarAnchors(
          primaryAnchor: Offset(100, 260),
          secondaryAnchor: Offset(180, 274),
        ),
      );

      expect(find.text('Cut'), findsOneWidget);
      expect(find.text('Copy'), findsOneWidget);
      expect(find.text('Paste'), findsOneWidget);
      final buttons = find.byType(TextButton);
      expect(buttons, findsNWidgets(3));
      for (var index = 0; index < 3; index++) {
        final size = tester.getSize(buttons.at(index));
        expect(size.width, greaterThanOrEqualTo(48));
        expect(size.height, greaterThanOrEqualTo(48));
      }

      final menu = find.byKey(const ValueKey('native-android-clipboard-menu'));
      expect(tester.getBottomLeft(menu).dy, 60 + 260 - 8);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('flips below a top selection and stays above the keyboard', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await _showMenu(
      tester,
      bottomInset: 180,
      bottomPadding: 24,
      anchors: const TextSelectionToolbarAnchors(
        primaryAnchor: Offset(160, 42),
        secondaryAnchor: Offset(188, 54),
      ),
    );

    final menu = find.byKey(const ValueKey('native-android-clipboard-menu'));
    final menuTop = tester.getTopLeft(menu).dy;
    final menuBottom = tester.getBottomRight(menu).dy;
    expect(menuTop, greaterThanOrEqualTo(54));
    expect(menuBottom, lessThanOrEqualTo(480 - 180 - 24 - 12));
    expect(tester.takeException(), isNull);
  });

  testWidgets('reflows at double text scale in a narrow viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(180, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await _showMenu(
      tester,
      textScale: 2,
      anchors: const TextSelectionToolbarAnchors(
        primaryAnchor: Offset(168, 300),
        secondaryAnchor: Offset(172, 312),
      ),
    );

    final menu = find.byKey(const ValueKey('native-android-clipboard-menu'));
    expect(tester.getTopLeft(menu).dx, greaterThanOrEqualTo(16));
    expect(tester.getBottomRight(menu).dx, lessThanOrEqualTo(180 - 16));
    final buttons = find.byType(TextButton);
    expect(buttons, findsNWidgets(3));
    final buttonRows = {
      for (var index = 0; index < 3; index++)
        tester.getTopLeft(buttons.at(index)).dy,
    };
    expect(buttonRows.length, greaterThan(1));
    for (var index = 0; index < 3; index++) {
      final size = tester.getSize(buttons.at(index));
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
    }
    expect(tester.takeException(), isNull);
  });
}

Future<void> _showMenu(
  WidgetTester tester, {
  required TextSelectionToolbarAnchors anchors,
  double overlayTopInset = 0,
  double bottomInset = 0,
  double bottomPadding = 0,
  double textScale = 1,
}) async {
  late OverlayState overlay;
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        useMaterial3: true,
        visualDensity: VisualDensity.compact,
      ),
      builder: (context, child) {
        final media = MediaQuery.of(context);
        final adjustedChild = MediaQuery(
          data: media.copyWith(
            padding: EdgeInsets.only(bottom: bottomPadding),
            viewInsets: EdgeInsets.only(bottom: bottomInset),
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        );
        return overlayTopInset == 0
            ? adjustedChild
            : Column(
                children: [
                  SizedBox(height: overlayTopInset),
                  Expanded(child: adjustedChild),
                ],
              );
      },
      home: Builder(
        builder: (context) {
          overlay = Overlay.of(context, rootOverlay: true);
          return const Scaffold(body: SizedBox.expand());
        },
      ),
    ),
  );

  final entry = OverlayEntry(
    builder: (context) => NativeAndroidClipboardMenu(
      anchors: anchors,
      buttonItems: [
        ContextMenuButtonItem(
          type: ContextMenuButtonType.cut,
          onPressed: () {},
        ),
        ContextMenuButtonItem(
          type: ContextMenuButtonType.copy,
          onPressed: () {},
        ),
        ContextMenuButtonItem(
          type: ContextMenuButtonType.paste,
          onPressed: () {},
        ),
      ],
    ),
  );
  overlay.insert(entry);
  addTearDown(() {
    entry.remove();
    entry.dispose();
  });
  await tester.pumpAndSettle();
}
