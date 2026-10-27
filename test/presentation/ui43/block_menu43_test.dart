import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/domain/notes/note_document.dart';
import 'package:note_ai_app/presentation/editor/basic_block_commands.dart';
import 'package:note_ai_app/presentation/editor/basic_block_menu.dart';
import 'package:note_ai_app/presentation/editor/rich_editor_adapter.dart';
import 'package:note_ai_app/presentation/editor/slash_command_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  RichEditorAdapter createAdapter() => RichEditorAdapter(
    document: NoteDocument(const []),
    legacyText: '',
    canEdit: () => true,
    isLive: () => true,
    accessGeneration: () => 1,
    onChanged: () {},
  );

  Widget sheetApp(SlashCommandController controller, {double textScale = 1}) =>
      MaterialApp(
        theme: ThemeData(visualDensity: VisualDensity.compact),
        home: Builder(
          builder: (context) {
            final media = MediaQuery.of(context);
            return MediaQuery(
              data: media.copyWith(textScaler: TextScaler.linear(textScale)),
              child: Scaffold(
                body: SafeArea(
                  top: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 48),
                      Flexible(
                        child: BasicBlockMenu(
                          controller: controller,
                          sheet: true,
                          toolbarOwnsClose: true,
                          onChoose: (_) {},
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      );

  testWidgets(
    'native grid scrolls and marks keyboard selection at 200% text with IME',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(640, 360);
      tester.view.viewInsets = const FakeViewPadding(bottom: 160);

      final adapter = createAdapter();
      final controller = SlashCommandController(adapter);
      addTearDown(() {
        controller.dispose();
        adapter.dispose();
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.view.resetViewInsets();
      });

      expect(BasicBlockMenu.desktopPopupWidth, 324);
      expect(BasicBlockMenu.desktopPopupHeight, 290);
      await tester.pumpWidget(sheetApp(controller, textScale: 2));
      expect(tester.takeException(), isNull);
      final initialTextInk = tester.widget<Ink>(
        find.ancestor(of: find.text('Text'), matching: find.byType(Ink)).first,
      );
      expect(
        (initialTextInk.decoration! as BoxDecoration).color,
        Colors.transparent,
      );
      expect(basicBlockChoices, hasLength(13));
      expect(controller.choices.map((choice) => choice.label), [
        ...basicBlockChoices.map((choice) => choice.label),
        'File',
      ]);
      expect(
        controller.choices.map((choice) => choice.label),
        isNot(contains('Page')),
      );
      expect(
        controller.choices.map((choice) => choice.label),
        isNot(contains('Link to page')),
      );
      final mediaHeader = tester.widget<DecoratedBox>(
        find
            .ancestor(
              of: find.text('Media'),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      expect(
        (mediaHeader.decoration as BoxDecoration).border!.top.width,
        greaterThan(0),
      );

      controller.move(12);
      await tester.pumpAndSettle();

      final divider = find.text('Divider');
      expect(divider, findsOneWidget);
      final dividerBounds = tester.getRect(divider);
      final viewportBounds = tester.getRect(
        find.byType(SingleChildScrollView).first,
      );
      expect(viewportBounds.contains(dividerBounds.topLeft), isTrue);
      expect(viewportBounds.contains(dividerBounds.bottomRight), isTrue);
      final selectedInk = tester.widget<Ink>(
        find.ancestor(of: divider, matching: find.byType(Ink)).first,
      );
      final selectedDecoration = selectedInk.decoration! as BoxDecoration;
      expect(
        selectedDecoration.color,
        Theme.of(tester.element(divider)).colorScheme.onSurface
            .withValues(alpha: 0.075),
      );
      expect(selectedDecoration.borderRadius, BorderRadius.circular(6));
      expect(adapter.plainText, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('native File selection scrolls into view on a short screen', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(640, 360);
    tester.view.viewInsets = const FakeViewPadding(bottom: 80);

    final adapter = createAdapter();
    final controller = SlashCommandController(adapter);
    addTearDown(() {
      controller.dispose();
      adapter.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.view.resetViewInsets();
    });

    await tester.pumpWidget(sheetApp(controller));
    controller.move(13);
    await tester.pumpAndSettle();

    final file = find.text('File');
    expect(file, findsOneWidget);
    final fileTarget = find.ancestor(of: file, matching: find.byType(ListTile));
    expect(tester.getSize(fileTarget).height, greaterThanOrEqualTo(48));
    final fileBounds = tester.getRect(file);
    final viewportBounds = tester.getRect(
      find.byType(SingleChildScrollView).first,
    );
    expect(viewportBounds.contains(fileBounds.topLeft), isTrue);
    expect(viewportBounds.contains(fileBounds.bottomRight), isTrue);
    expect(tester.takeException(), isNull);
  });
}
