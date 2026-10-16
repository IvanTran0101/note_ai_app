import 'package:appflowy_editor/appflowy_editor.dart' as engine;
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/domain/notes/note_document.dart';
import 'package:note_ai_app/presentation/editor/basic_block_commands.dart';
import 'package:note_ai_app/presentation/editor/callout_commands.dart';
import 'package:note_ai_app/presentation/editor/divider_controls.dart';
import 'package:note_ai_app/presentation/editor/equation_commands.dart';
import 'package:note_ai_app/presentation/editor/rich_editor_adapter.dart';
import 'package:note_ai_app/presentation/editor/slash_command_controller.dart';
import 'package:note_ai_app/presentation/editor/table_commands.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  RichEditorAdapter create({NoteDocument? document, String text = ''}) {
    final adapter = RichEditorAdapter(
      document: document,
      legacyText: text,
      canEdit: () => true,
      isLive: () => true,
      accessGeneration: () => 1,
      onChanged: () {},
    );
    addTearDown(adapter.dispose);
    return adapter;
  }

  void select(RichEditorAdapter adapter, List<int> path, int end) =>
      adapter.editor.selection = engine.Selection.single(
        path: path,
        startOffset: 0,
        endOffset: end,
      );

  test(
    'Vietnamese accented, unaccented, uppercase and decomposed slash aliases',
    () {
      for (final query in [
        'TIÊU ĐỀ 4',
        'tieu de 4',
        'tie\u0302u đe\u0302\u0300 4',
      ]) {
        final adapter = create(text: '/$query'),
            slash = SlashCommandController(adapter);
        addTearDown(slash.dispose);
        adapter.editor.selection = engine.Selection.collapsed(
          engine.Position(path: [0], offset: query.length + 1),
        );
        expect(slash.visible, true);
        expect(slash.choices.single.label, 'Heading 4');
      }
    },
  );
  test(
    'callout metadata is durable/undoable, stale and Viewer cannot apply',
    () async {
      final doc = NoteDocument([
        DocumentBlock(
          id: 'callout',
          kind: DocumentBlockKind.callout,
          runs: const [DocumentText('keep')],
          icon: '💡',
          tone: DocumentColor.gray,
        ),
      ]);
      final adapter = create(document: doc), command = CalloutCommands(adapter);
      final node = adapter.editor.document.root.children.first;
      final snapshot = command.capture(node)!;
      expect(
        await command.change(
          node,
          snapshot,
          icon: '🎯',
          tone: DocumentColor.blue,
        ),
        true,
      );
      expect(adapter.document!.blocks.single.icon, '🎯');
      expect(adapter.document!.blocks.single.tone, DocumentColor.blue);
      expect(adapter.plainText, 'keep');
      expect(
        await command.change(
          node,
          snapshot,
          icon: '⭐',
          tone: DocumentColor.red,
        ),
        false,
      );
      adapter.editor.undoManager.undo();
      expect(adapter.document, doc);
      adapter.editor.undoManager.redo();
      expect(adapter.document!.blocks.single.icon, '🎯');
    },
  );
  test(
    'touch divider deletion leaves a caret target and undo restores identity',
    () async {
      final doc = NoteDocument([
        DocumentBlock(id: 'line', kind: DocumentBlockKind.divider),
      ]);
      final adapter = create(document: doc);
      expect(
        await deleteDivider(
          adapter,
          adapter.editor.document.root.children.single,
        ),
        true,
      );
      expect(adapter.document!.blocks.single.kind, DocumentBlockKind.paragraph);
      expect(adapter.editor.selection!.start.path, [0]);
      adapter.editor.undoManager.undo();
      expect(adapter.document, doc);
    },
  );
  test('convert adjacent equations to expression preserves separate marks and undo', () async {
    final doc = NoteDocument([
      DocumentBlock(
        id: 'p',
        kind: DocumentBlockKind.paragraph,
        runs: [
          DocumentMath(r'\sqrt{x}', marks: DocumentMarks(fontSize: 28)),
          DocumentMath('y', marks: DocumentMarks(bold: true)),
        ],
      ),
    ]);
    final adapter = create(document: doc);
    select(adapter, [0], 2);
    expect(
      await EquationCommands(adapter).convertToText(adapter.capture()!),
      true,
    );
    expect(adapter.document!.blocks.single.runs, [
      DocumentText(r'\sqrt{x}', marks: DocumentMarks(fontSize: 28)),
      DocumentText('y', marks: DocumentMarks(bold: true)),
    ]);
    expect(adapter.plainText, r'\sqrt{x}y');
    adapter.editor.undoManager.undo();
    expect(adapter.document, doc);
  });
  test(
    'table can be exited to editable text without changing its cells',
    () async {
      final adapter = create(text: '/table');
      adapter.editor.selection = engine.Selection.collapsed(
        engine.Position(path: [0], offset: 6),
      );
      await BasicBlockCommands(adapter).choose(
        basicBlockChoices[11],
        adapter.capture(range: false)!,
        slashStart: 0,
      );
      final table = adapter.visibleDocument.blocks.last;
      expect(
        await TableCommands(adapter)
            .change(TableChange.paragraphAfter, adapter.capture(range: false)!),
        true,
      );
      expect(adapter.document!.blocks[1], table);
      expect(adapter.document!.blocks.last.kind, DocumentBlockKind.paragraph);
      expect(adapter.editor.selection!.start.path, [2]);
      adapter.editor.undoManager.undo();
      expect(adapter.document!.blocks.last, table);
    },
  );
}
