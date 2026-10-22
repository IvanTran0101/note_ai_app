import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:note_ai_app/presentation/workspace/compact_workspace_menu.dart';

final GlobalKey _avatarKey = GlobalKey();
const ValueKey<String> _homeItemKey = ValueKey<String>('compact-menu-home');
const ValueKey<String> _notesItemKey = ValueKey<String>('compact-menu-notes');
const ValueKey<String> _notesAliasKey = ValueKey<String>(
  'compact-menu-notes-alias',
);

const List<CompactWorkspaceMenuItem<String>> _standardItems =
    <CompactWorkspaceMenuItem<String>>[
      CompactWorkspaceMenuItem<String>(
        key: _homeItemKey,
        label: 'Home',
        icon: Icons.home_outlined,
        value: 'home',
      ),
      CompactWorkspaceMenuItem<String>(
        key: _notesItemKey,
        aliasKey: _notesAliasKey,
        label: 'Notes',
        icon: Icons.description_outlined,
        value: 'notes',
        selected: true,
      ),
    ];

void main() {
  testWidgets('returns the selected value and preserves the alias key', (
    WidgetTester tester,
  ) async {
    final _OpenedMenu opened = await _openMenu(tester);

    expect(find.byKey(_notesItemKey), findsOneWidget);
    expect(find.byKey(_notesAliasKey), findsOneWidget);
    await tester.tap(find.byKey(_notesAliasKey));
    await tester.pumpAndSettle();

    expect(await opened.result, 'notes');
    expect(find.byType(PopupMenuItem<String>), findsNothing);
  });

  testWidgets('closes on the platform back route and returns null', (
    WidgetTester tester,
  ) async {
    final _OpenedMenu opened = await _openMenu(tester);

    expect(await tester.binding.handlePopRoute(), isTrue);
    await tester.pumpAndSettle();

    expect(await opened.result, isNull);
  });

  testWidgets('closes after an outside tap and returns null', (
    WidgetTester tester,
  ) async {
    final _OpenedMenu opened = await _openMenu(tester);

    await tester.tapAt(const Offset(380, 820));
    await tester.pumpAndSettle();

    expect(await opened.result, isNull);
  });

  testWidgets('keeps a 48dp target under compact visual density', (
    WidgetTester tester,
  ) async {
    final _OpenedMenu opened = await _openMenu(
      tester,
      theme: ThemeData(visualDensity: VisualDensity.compact),
    );

    expect(
      tester.getSize(find.byKey(_notesItemKey)).height,
      greaterThanOrEqualTo(48),
    );
    expect(
      tester.getSize(find.byKey(_notesItemKey)).width,
      lessThanOrEqualTo(288),
    );

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(await opened.result, isNull);
  });

  testWidgets('dismisses its own route when the viewport changes', (
    WidgetTester tester,
  ) async {
    final opened = await _openMenu(tester);
    tester.view.physicalSize = const Size(844, 390);
    await tester.pumpAndSettle();
    expect(await opened.result, isNull);
    expect(find.byType(PopupMenuItem<String>), findsNothing);
    expect(find.byKey(_avatarKey), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dismisses its own route when keyboard insets change', (
    WidgetTester tester,
  ) async {
    final opened = await _openMenu(tester);
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    await tester.pumpAndSettle();
    expect(await opened.result, isNull);
    expect(find.byType(PopupMenuItem<String>), findsNothing);
    expect(find.byKey(_avatarKey), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('converts the global anchor through a root overlay offset', (
    WidgetTester tester,
  ) async {
    final _OpenedMenu opened = await _openMenu(
      tester,
      overlayOffset: const Offset(0, 60),
    );
    final Rect avatarRect = tester.getRect(find.byKey(_avatarKey));
    final Rect itemRect = tester.getRect(find.byKey(_homeItemKey));

    expect(opened.overlayOrigin.dy, 60);
    expect(itemRect.top, closeTo(avatarRect.bottom - 4, 1));
    expect(itemRect.left, closeTo(avatarRect.left + 4, 1));

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(await opened.result, isNull);
  });

  testWidgets(
    'fits narrow, large-text and short safe viewports without overflow',
    (WidgetTester tester) async {
      const List<CompactWorkspaceMenuItem<String>> manyItems =
          <CompactWorkspaceMenuItem<String>>[
            CompactWorkspaceMenuItem<String>(
              key: _homeItemKey,
              label: 'Home',
              icon: Icons.home_outlined,
              value: 'home',
            ),
            CompactWorkspaceMenuItem<String>(
              label: 'Notes',
              icon: Icons.description_outlined,
              value: 'notes',
            ),
            CompactWorkspaceMenuItem<String>(
              label: 'Search',
              icon: Icons.search,
              value: 'search',
            ),
            CompactWorkspaceMenuItem<String>(
              label: 'New note',
              icon: Icons.add,
              value: 'new-note',
            ),
            CompactWorkspaceMenuItem<String>(
              label: 'Ask notes',
              icon: Icons.forum_outlined,
              value: 'ask-notes',
            ),
            CompactWorkspaceMenuItem<String>(
              label: 'Diagnostics',
              icon: Icons.bug_report_outlined,
              value: 'diagnostics',
              dividerBefore: true,
            ),
            CompactWorkspaceMenuItem<String>(
              label: 'Settings',
              icon: Icons.settings_outlined,
              value: 'settings',
            ),
          ];
      final _OpenedMenu opened = await _openMenu(
        tester,
        size: const Size(240, 240),
        textScale: 2,
        viewPadding: const EdgeInsets.fromLTRB(12, 24, 12, 24),
        viewInsets: const EdgeInsets.only(bottom: 40),
        items: manyItems,
      );
      final Rect itemRect = tester.getRect(find.byKey(_homeItemKey));
      final Rect popupRect = tester.getRect(
        find.byWidgetPredicate(
          (Widget widget) => widget is Material && widget.elevation == 2,
        ),
      );

      expect(itemRect.left, greaterThanOrEqualTo(20));
      expect(itemRect.right, lessThanOrEqualTo(220));
      expect(itemRect.top, greaterThanOrEqualTo(24));
      expect(itemRect.width, lessThanOrEqualTo(200));
      expect(popupRect.bottom, lessThanOrEqualTo(200));
      expect(tester.takeException(), isNull);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(await opened.result, isNull);
    },
  );
}

Future<_OpenedMenu> _openMenu(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  double textScale = 1,
  EdgeInsets viewPadding = EdgeInsets.zero,
  EdgeInsets viewInsets = EdgeInsets.zero,
  Offset overlayOffset = Offset.zero,
  ThemeData? theme,
  List<CompactWorkspaceMenuItem<String>> items = _standardItems,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.viewPadding = FakeViewPadding(
    left: viewPadding.left,
    top: viewPadding.top,
    right: viewPadding.right,
    bottom: viewPadding.bottom,
  );
  tester.view.viewInsets = FakeViewPadding(
    left: viewInsets.left,
    top: viewInsets.top,
    right: viewInsets.right,
    bottom: viewInsets.bottom,
  );
  // FakeFlutterView stores padding separately from viewPadding/viewInsets.
  // Reproduce the effective platform padding instead of leaving it at zero.
  tester.view.padding = FakeViewPadding(
    left: (viewPadding.left - viewInsets.left).clamp(0, double.infinity),
    top: (viewPadding.top - viewInsets.top).clamp(0, double.infinity),
    right: (viewPadding.right - viewInsets.right).clamp(0, double.infinity),
    bottom: (viewPadding.bottom - viewInsets.bottom).clamp(0, double.infinity),
  );
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetViewPadding);
  addTearDown(tester.view.resetViewInsets);
  addTearDown(tester.view.resetPadding);

  late Future<String?> selection;
  late Offset overlayOrigin;
  await tester.pumpWidget(
    _MenuHarness(
      theme: theme,
      textScale: textScale,
      overlayOffset: overlayOffset,
      items: items,
      onMenuOpened: (Future<String?> result, Offset rootOverlayOrigin) {
        selection = result;
        overlayOrigin = rootOverlayOrigin;
      },
    ),
  );
  await tester.tap(find.byKey(_avatarKey));
  await tester.pumpAndSettle();

  return _OpenedMenu(selection, overlayOrigin);
}

class _OpenedMenu {
  const _OpenedMenu(this.result, this.overlayOrigin);

  final Future<String?> result;
  final Offset overlayOrigin;
}

class _MenuHarness extends StatelessWidget {
  const _MenuHarness({
    required this.textScale,
    required this.overlayOffset,
    required this.items,
    required this.onMenuOpened,
    this.theme,
  });

  final double textScale;
  final Offset overlayOffset;
  final List<CompactWorkspaceMenuItem<String>> items;
  final void Function(Future<String?> result, Offset rootOverlayOrigin)
  onMenuOpened;
  final ThemeData? theme;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: theme,
      builder: (BuildContext context, Widget? child) {
        Widget content = child!;
        if (textScale != 1) {
          content = MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: content,
          );
        }
        return Transform.translate(offset: overlayOffset, child: content);
      },
      home: Scaffold(
        body: Builder(
          builder: (BuildContext context) {
            return Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 12, top: 12),
                child: IconButton(
                  key: _avatarKey,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 48,
                    height: 48,
                  ),
                  onPressed: () {
                    final RenderBox avatarBox =
                        _avatarKey.currentContext!.findRenderObject()!
                            as RenderBox;
                    final Rect anchor =
                        avatarBox.localToGlobal(Offset.zero) & avatarBox.size;
                    final RenderBox rootOverlayBox =
                        Overlay.of(
                              context,
                              rootOverlay: true,
                            ).context.findRenderObject()!
                            as RenderBox;
                    onMenuOpened(
                      showCompactWorkspaceMenu<String>(
                        context: context,
                        globalAnchor: anchor,
                        items: items,
                        semanticLabel: 'Workspace menu',
                      ),
                      rootOverlayBox.localToGlobal(Offset.zero),
                    );
                  },
                  icon: SizedBox(
                    width: 40,
                    height: 40,
                    child: const CircleAvatar(
                      backgroundColor: Color(0xFFE8E8E8),
                      child: Text('N'),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
