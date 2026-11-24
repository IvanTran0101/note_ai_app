import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/presentation/workspace/compact_workspace_menu.dart';

final GlobalKey _avatarKey = GlobalKey();

void main() {
  testWidgets(
    'compact avatar menu scrolls with large text and a short viewport',
    (WidgetTester tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 480);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      await _pumpMenuHarness(
        tester,
        alignment: Alignment.bottomLeft,
        textScale: 2,
        viewInsets: const EdgeInsets.only(bottom: 128),
        items: <CompactWorkspaceMenuItem<String>>[
          for (int index = 0; index < 7; index++)
            CompactWorkspaceMenuItem<String>(
              key: ValueKey<String>('avatar-item-$index'),
              label: index == 0
                  ? 'Workspace'
                  : 'Existing workspace action with a longer label',
              icon: Icons.circle_outlined,
              value: 'action-$index',
              dividerBefore: index == 1 || index == 4,
            ),
        ],
      );

      await tester.tap(find.byKey(_avatarKey));
      await tester.pumpAndSettle();

      expect(find.byType(PopupMenuDivider), findsNWidgets(2));
      expect(
        tester
            .getSize(find.byKey(const ValueKey<String>('avatar-item-0')))
            .height,
        greaterThanOrEqualTo(48),
      );
      expect(tester.takeException(), isNull);

      final Finder finalAction = find.byKey(
        const ValueKey<String>('avatar-item-6'),
      );
      await tester.ensureVisible(finalAction);
      expect(finalAction.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('compact avatar menu receives keyboard focus for selection', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 640);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    String? selected;
    await _pumpMenuHarness(
      tester,
      items: const <CompactWorkspaceMenuItem<String>>[
        CompactWorkspaceMenuItem<String>(
          key: ValueKey<String>('focus-item-0'),
          label: 'First existing action',
          icon: Icons.circle_outlined,
          value: 'action-0',
        ),
        CompactWorkspaceMenuItem<String>(
          key: ValueKey<String>('focus-item-1'),
          label: 'Second existing action',
          icon: Icons.circle_outlined,
          value: 'action-1',
        ),
      ],
      onSelected: (String? value) => selected = value,
    );

    await tester.tap(find.byKey(_avatarKey));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(selected, 'action-1');
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpMenuHarness(
  WidgetTester tester, {
  required List<CompactWorkspaceMenuItem<String>> items,
  Alignment alignment = Alignment.topLeft,
  double textScale = 1,
  EdgeInsets viewInsets = EdgeInsets.zero,
  ValueChanged<String?>? onSelected,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      builder: (BuildContext context, Widget? child) {
        final MediaQueryData data = MediaQuery.of(context);
        return MediaQuery(
          data: data.copyWith(
            textScaler: TextScaler.linear(textScale),
            viewInsets: viewInsets,
          ),
          child: child!,
        );
      },
      home: Scaffold(
        body: Align(
          alignment: alignment,
          child: SizedBox(
            key: _avatarKey,
            width: 48,
            height: 48,
            child: TextButton(
              onPressed: () {
                final BuildContext anchorContext = _avatarKey.currentContext!;
                final RenderBox anchor =
                    anchorContext.findRenderObject()! as RenderBox;
                unawaited(
                  showCompactWorkspaceMenu<String>(
                    context: anchorContext,
                    globalAnchor:
                        anchor.localToGlobal(Offset.zero) & anchor.size,
                    items: items,
                    semanticLabel: 'Workspace menu',
                  ).then(onSelected ?? (_) {}),
                );
              },
              child: const Icon(Icons.person_outline),
            ),
          ),
        ),
      ),
    ),
  );
}
