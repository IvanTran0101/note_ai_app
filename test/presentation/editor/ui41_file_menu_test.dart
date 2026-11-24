import 'package:appflowy_editor/appflowy_editor.dart' as engine;

import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/domain/notes/note_document.dart';
import 'package:note_ai_app/presentation/editor/basic_block_commands.dart';
import 'package:note_ai_app/presentation/editor/basic_block_menu.dart';
import 'package:note_ai_app/presentation/editor/rich_editor_adapter.dart';
import 'package:note_ai_app/presentation/editor/rich_note_editor.dart';
import 'package:note_ai_app/presentation/editor/slash_command_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  RichEditorAdapter createAdapter({
    required NoteDocument document,
    List<String> Function()? readLegacyAttachmentIds,
    ValueChanged<String>? onFileInserted,
  }) => RichEditorAdapter(
    document: document,
    legacyText: '',
    canEdit: () => true,
    isLive: () => true,
    accessGeneration: () => 1,
    onChanged: () {},
    readLegacyAttachmentIds: readLegacyAttachmentIds,
    onFileInserted: onFileInserted,
  );

  test('File is a separate Media choice; Basic blocks remain unchanged', () {
    final adapter = createAdapter(document: NoteDocument(const []));
    final slash = SlashCommandController(adapter);
    addTearDown(() {
      slash.dispose();
      adapter.dispose();
    });

    expect(basicBlockChoices, hasLength(13));
    expect(slash.choices.map((choice) => choice.label), [
      ...basicBlockChoices.map((choice) => choice.label),
      'File',
    ]);
    expect(mediaBlockChoices.single.kind, DocumentBlockKind.attachment);
  });

  test(
    'slash File splits text and migrates legacy refs in one undo step',
    () async {
      final insertedIds = <String>[];
      final adapter = createAdapter(
        document: NoteDocument([
          DocumentBlock(
            id: 'first',
            kind: DocumentBlockKind.paragraph,
            runs: const [DocumentText('before /file after')],
          ),
          DocumentBlock(
            id: 'last',
            kind: DocumentBlockKind.paragraph,
            runs: const [DocumentText('keep this block')],
          ),
        ]),
        readLegacyAttachmentIds: () => const [
          'legacy_1',
          'legacy_1',
          'legacy_2',
        ],
        onFileInserted: insertedIds.add,
      );
      addTearDown(adapter.dispose);
      adapter.editor.selection = engine.Selection.collapsed(
        engine.Position(path: [0], offset: 12),
      );
      final slash = SlashCommandController(adapter);
      addTearDown(slash.dispose);
      slash.refresh();

      expect(slash.visible, true);
      expect(slash.choices.map((choice) => choice.kind), [
        DocumentBlockKind.attachment,
      ]);
      expect(await slash.choose(slash.choices.single), true);

      final blocks = adapter.visibleDocument.blocks;
      expect(blocks.map((block) => block.kind), [
        DocumentBlockKind.paragraph,
        DocumentBlockKind.attachment,
        DocumentBlockKind.paragraph,
        DocumentBlockKind.paragraph,
        DocumentBlockKind.attachment,
        DocumentBlockKind.attachment,
      ]);
      expect(blocks[0].plainText, 'before ');
      expect(blocks[1].attachmentId, isNull);
      expect(blocks[2].plainText, ' after');
      expect(blocks[3].id, 'last');
      expect(blocks[4].attachmentId, 'legacy_1');
      expect(blocks[5].attachmentId, 'legacy_2');
      expect(adapter.visibleDocument.inlineAttachments, true);
      expect(insertedIds, [blocks[1].id]);

      adapter.editor.undoManager.undo();
      expect(adapter.visibleDocument.blocks.map((block) => block.id), [
        'first',
        'last',
      ]);
      expect(adapter.visibleDocument.inlineAttachments, false);
      expect(insertedIds, [blocks[1].id]);

      adapter.editor.undoManager.redo();
      expect(
        adapter.visibleDocument.blocks.map((block) => block.id),
        blocks.map((block) => block.id),
      );
      expect(
        adapter.visibleDocument.blocks.map((block) => block.kind),
        blocks.map((block) => block.kind),
      );
      expect(adapter.document!.inlineAttachments, true);
    },
  );

  test(
    'inline File deletion is not resurrected by later insertion or redo',
    () async {
      final adapter = createAdapter(
        document: NoteDocument([
          DocumentBlock(
            id: 'body',
            kind: DocumentBlockKind.paragraph,
            runs: const [DocumentText('/file')],
          ),
        ], inlineAttachments: true),
        // This is the legacy list left after a File block was deleted while
        // inline mode was active. It must not become visible again.
        readLegacyAttachmentIds: () => const ['deleted_attachment'],
      );
      addTearDown(adapter.dispose);
      adapter.editor.selection = engine.Selection.collapsed(
        engine.Position(path: [0], offset: 5),
      );
      final slash = SlashCommandController(adapter);
      addTearDown(slash.dispose);
      slash.refresh();

      expect(await slash.choose(slash.choices.single), true);
      expect(
        adapter.visibleDocument.blocks
            .where((block) => block.kind == DocumentBlockKind.attachment)
            .map((block) => block.attachmentId),
        [null],
      );

      adapter.editor.undoManager.undo();
      expect(adapter.visibleDocument.blocks.map((block) => block.id), ['body']);
      expect(adapter.visibleDocument.inlineAttachments, true);

      adapter.editor.undoManager.redo();
      expect(
        adapter.visibleDocument.blocks
            .where((block) => block.kind == DocumentBlockKind.attachment)
            .map((block) => block.attachmentId),
        [null],
      );
    },
  );

  testWidgets(
    'Add block File renders through the host file placeholder builder',
    (tester) async {
      final semantics = kIsWeb ? tester.ensureSemantics() : null;
      final adapter = createAdapter(
        document: NoteDocument([
          DocumentBlock(
            id: 'body',
            kind: DocumentBlockKind.paragraph,
            runs: const [DocumentText('Body')],
          ),
        ]),
      );
      final focus = FocusNode();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        adapter.dispose();
        focus.dispose();
      });

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            engine.AppFlowyEditorLocalizations.delegate,
          ],
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 24),
              child: RichNoteEditor(
                adapter: adapter,
                focusNode: focus,
                header: const SizedBox.shrink(),
                fileBlockBuilder: (blockId, attachmentId) => Text(
                  'File placeholder $blockId ${attachmentId ?? 'unbound'}',
                ),
              ),
            ),
          ),
        ),
      );
      if (!kIsWeb) {
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        addTearDown(tester.view.resetViewInsets);
        focus.requestFocus();
        await tester.pumpAndSettle();
      }
      adapter.editor.selection = engine.Selection.collapsed(
        engine.Position(path: [0], offset: 4),
      );
      await tester.pumpAndSettle();
      if (kIsWeb) {
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer();
        await mouse.moveTo(
          tester.getCenter(find.byKey(const ValueKey('block-add-body'))),
        );
        await tester.pump(const Duration(milliseconds: 800));
        expect(tester.takeException(), isNull);
        addTearDown(mouse.removePointer);
      }
      await tester.tap(
        kIsWeb
            ? find.byKey(const ValueKey('block-add-body'))
            : find.byTooltip('Add block'),
      );
      await tester.pumpAndSettle();

      // The touch menu is hosted in the root overlay; locate File through its
      // visible label to avoid depending on the menu's private state.
      final menu = find.byType(BasicBlockMenu);
      final fileChoice = find.descendant(of: menu, matching: find.text('File'));
      // Desktop rows are built lazily; scroll through the same continuous list
      // a user follows to reach Media beneath Basic blocks.
      await tester.scrollUntilVisible(
        fileChoice,
        150,
        scrollable: find
            .descendant(of: menu, matching: find.byType(Scrollable))
            .first,
      );
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: menu, matching: find.text('Media')),
        findsOneWidget,
      );
      expect(fileChoice, findsOneWidget);
      if (kIsWeb) {
        expect(adapter.menuOwnsInput.value, true);
        final editable = tester.widget<EditableText>(
          find.descendant(
            of: find.byKey(const ValueKey('block-insert-filter')),
            matching: find.byType(EditableText),
          ),
        );
        expect(editable.focusNode.hasPrimaryFocus, true);
        await tester.enterText(
          find.byKey(const ValueKey('block-insert-filter')),
          'file',
        );
        await tester.pumpAndSettle();
        expect(
          adapter.plainText.contains('file'),
          false,
          reason: 'The + palette query must never enter the document',
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'Document text block',
        );
        await tester.tap(find.byKey(const ValueKey('block-add-body')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('block-insert-filter')),
          'file',
        );
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      } else {
        await tester.ensureVisible(fileChoice);
        await tester.pumpAndSettle();
        await tester.tap(fileChoice);
      }
      await tester.pumpAndSettle();

      expect(
        adapter.visibleDocument.blocks[1].kind,
        DocumentBlockKind.attachment,
      );
      expect(adapter.menuOwnsInput.value, false);
      expect(find.textContaining('File placeholder '), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      semantics?.dispose();
    },
  );
}
