import 'package:appflowy_editor/appflowy_editor.dart' as engine;
import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:note_ai_app/presentation/editor/editor_renderers.dart';

void main() {
  testWidgets(
    'mobile target restores native handles while Web keeps desktop style',
    (tester) async {
      final (style, colors) = await _readStyle(tester, TargetPlatform.android);

      expect(
        style.dragHandleColor,
        kIsWeb ? Colors.transparent : colors.primary,
      );
      expect(
        style.mobileDragHandleBallSize,
        kIsWeb ? Size.zero : const Size(8, 8),
      );
      expect(style.mobileDragHandleWidth, kIsWeb ? 0 : 2);
      expect(
        style.autoDismissCollapsedHandleDuration,
        kIsWeb ? Duration.zero : const Duration(seconds: 3),
      );
      if (!kIsWeb) {
        expect(style.magnifierSize, const Size(72, 48));
        expect(style.enableHapticFeedbackOnAndroid, isTrue);
      }

      // The native handle fix must retain the current phone document styling.
      expect(style.padding, EdgeInsets.symmetric(vertical: kIsWeb ? 8 : 4));
      expect(style.cursorColor, colors.onSurface);
      expect(style.selectionColor, colors.primary.withValues(alpha: .22));
      expect(style.textStyleConfiguration.text.fontSize, kIsWeb ? 16 : 17);
      expect(style.textStyleConfiguration.text.height, 1.5);
    },
  );

  testWidgets('native desktop retains the desktop selection style', (
    tester,
  ) async {
    final (style, _) = await _readStyle(tester, TargetPlatform.windows);

    expect(style.dragHandleColor, Colors.transparent);
    expect(style.mobileDragHandleBallSize, Size.zero);
    expect(style.mobileDragHandleWidth, 0);
    expect(style.autoDismissCollapsedHandleDuration, Duration.zero);
    expect(style.textStyleConfiguration.text.fontSize, 16);
  });
}

Future<(engine.EditorStyle, ColorScheme)> _readStyle(
  WidgetTester tester,
  TargetPlatform platform,
) async {
  final previousPlatform = debugDefaultTargetPlatformOverride;
  debugDefaultTargetPlatformOverride = platform;
  try {
    late engine.EditorStyle style;
    late ColorScheme colors;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(390, 844)),
          child: Builder(
            builder: (context) {
              style = documentEditorStyle(context);
              colors = Theme.of(context).colorScheme;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    return (style, colors);
  } finally {
    debugDefaultTargetPlatformOverride = previousPlatform;
  }
}
