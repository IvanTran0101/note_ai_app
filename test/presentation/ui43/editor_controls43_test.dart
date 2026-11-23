import 'package:appflowy_editor/appflowy_editor.dart' as engine;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/domain/notes/note_document.dart';
import 'package:note_ai_app/presentation/editor/editor_controls.dart';
import 'package:note_ai_app/presentation/editor/native_editor_rail.dart';
import 'package:note_ai_app/presentation/editor/rich_editor_adapter.dart';
import 'package:note_ai_app/presentation/editor/slash_command_controller.dart';
import 'package:note_ai_app/presentation/editor/web_editor_controls.dart';

void main() {
  testWidgets('wide Web block control reveals on hover, then hides on exit', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1280, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final focus = FocusNode();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      focus.dispose();
    });

    const regionKey = ValueKey('editor-control-hover-region');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WebEditorControls(
            key: regionKey,
            focusNode: focus,
            child: SizedBox(
              key: const ValueKey('editor-control-hover-target'),
              width: 180,
              height: 48,
              child: TextButton(
                onPressed: () {},
                child: const Text('Add block'),
              ),
            ),
          ),
        ),
      ),
    );
    final semantics = tester.ensureSemantics();

    expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 0);
    expect(find.bySemanticsLabel('Add block'), findsNothing);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(1200, 700));
    await mouse.moveTo(
      tester.getCenter(
        find.byKey(const ValueKey('editor-control-hover-target')),
      ),
    );
    await tester.pump();
    expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 1);
    expect(find.bySemanticsLabel('Add block'), findsOneWidget);

    await mouse.moveTo(const Offset(1200, 700));
    await tester.pump();
    expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 0);
    await mouse.removePointer();
    semantics.dispose();
  });

  testWidgets('wide Web controls stay discoverable at enlarged text', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1280, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final focus = FocusNode();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      focus.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.5)),
            child: Scaffold(
              body: WebEditorControls(
                focusNode: focus,
                child: TextButton(
                  onPressed: () {},
                  child: const Text('Add block'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final semantics = tester.ensureSemantics();

    expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 1);
    expect(find.bySemanticsLabel('Add block'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets(
    'native Add, Redo and Undo stay accessible above the IME in rail order',
    (tester) async {
      tester.view
        ..physicalSize = const Size(400, 800)
        ..devicePixelRatio = 1
        ..viewInsets = const FakeViewPadding(bottom: 280);
      addTearDown(tester.view.reset);
      final focus = FocusNode();
      final adapter = _adapter();
      final slash = SlashCommandController(adapter);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        slash.dispose();
        adapter.dispose();
        focus.dispose();
      });

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            engine.AppFlowyEditorLocalizations.delegate,
          ],
          home: Scaffold(
            body: Focus(
              focusNode: focus,
              child: NativeEditorRail(
                adapter: adapter,
                focusNode: focus,
                controls: EditorControls(adapter: adapter, slash: slash),
              ),
            ),
          ),
        ),
      );
      focus.requestFocus();
      await tester.pumpAndSettle();

      final semantics = tester.ensureSemantics();
      final add = find.byTooltip('Add block');
      final redo = find.byTooltip('Redo');
      final undo = find.byTooltip('Undo');
      expect(add, findsOneWidget);
      expect(redo, findsOneWidget);
      expect(undo, findsOneWidget);
      expect(tester.getRect(add).left, lessThan(tester.getRect(redo).left));
      expect(tester.getRect(redo).left, lessThan(tester.getRect(undo).left));
      expect(tester.getRect(add).height, 48);
      expect(tester.getRect(undo).bottom, lessThanOrEqualTo(520));
      expect(find.bySemanticsLabel('Redo'), findsOneWidget);
      expect(find.bySemanticsLabel('Undo'), findsOneWidget);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
    skip: kIsWeb,
  );

  testWidgets(
    'wide Web controls use full targets with enlarged text or accessible navigation',
    (tester) async {
      tester.view
        ..physicalSize = const Size(1280, 800)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final adapter = _adapter();
      final slash = SlashCommandController(adapter);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        slash.dispose();
        adapter.dispose();
      });

      Widget host({double scale = 1, bool accessibleNavigation = false}) =>
          MaterialApp(
            localizationsDelegates: const [
              engine.AppFlowyEditorLocalizations.delegate,
            ],
            home: MediaQuery(
              data: MediaQueryData(
                size: const Size(1280, 800),
                textScaler: TextScaler.linear(scale),
                accessibleNavigation: accessibleNavigation,
              ),
              child: Scaffold(
                body: EditorControls(adapter: adapter, slash: slash),
              ),
            ),
          );

      await tester.pumpWidget(host());
      final add = find.widgetWithIcon(IconButton, Icons.add);
      expect(tester.widget<IconButton>(add).constraints?.minWidth, 28);

      await tester.pumpWidget(host(scale: 1.5));
      expect(tester.widget<IconButton>(add).constraints?.minWidth, 48);

      await tester.pumpWidget(host(accessibleNavigation: true));
      expect(tester.widget<IconButton>(add).constraints?.minWidth, 48);
    },
    skip: !kIsWeb,
  );
}

RichEditorAdapter _adapter() => RichEditorAdapter(
  document: NoteDocument([
    DocumentBlock(
      id: 'body',
      kind: DocumentBlockKind.paragraph,
      runs: const [DocumentText('body')],
    ),
  ]),
  legacyText: '',
  canEdit: () => true,
  isLive: () => true,
  accessGeneration: () => 1,
  onChanged: () {},
);
