import 'package:appflowy_editor/appflowy_editor.dart' as engine;
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/domain/notes/note_document.dart';
import 'package:note_ai_app/presentation/editor/basic_block_commands.dart';
import 'package:note_ai_app/presentation/editor/equation_commands.dart';
import 'package:note_ai_app/presentation/editor/rich_editor_adapter.dart';
import 'package:note_ai_app/presentation/editor/slash_command_controller.dart';
import 'package:note_ai_app/presentation/editor/table_commands.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  RichEditorAdapter create(
    String text, {
    NoteDocument? document,
    bool Function()? edit,
  }) {
    final adapter = RichEditorAdapter(
      document: document,
      legacyText: text,
      canEdit: edit ?? () => true,
      isLive: () => true,
      accessGeneration: () => 1,
      onChanged: () {},
    );
    addTearDown(adapter.dispose);
    return adapter;
  }

  void select(
    RichEditorAdapter adapter,
    List<int> path,
    int start, [
    int? end,
  ]) => adapter.editor.selection = engine.Selection.single(
    path: path,
    startOffset: start,
    endOffset: end ?? start,
  );

  test(
    '13 choices only; slash filtering, literal URLs and Esc preserve text',
    () async {
      expect(basicBlockChoices.length, 13);
      expect(
        basicBlockChoices.any((c) => c.label.toLowerCase().contains('page')),
        false,
      );
      final adapter = create('/h4'), slash = SlashCommandController(adapter);
      addTearDown(slash.dispose);
      select(adapter, [0], 3);
      expect(slash.choices.map((c) => c.label), ['Heading 4']);
      expect(slash.visible, true);
      slash.close(cancel: true);
      slash.refresh();
      expect(slash.visible, false);
      expect(adapter.plainText, '/h4');
      final url = create('https://example.com/a');
      final urlMenu = SlashCommandController(url);
      addTearDown(urlMenu.dispose);
      select(url, [0], url.plainText.length);
      expect(urlMenu.visible, false);
    },
  );
  test('slash replaces only query; conversion and undo keep block identity/content', () async {
    final adapter = create('Title /h4'),
        slash = SlashCommandController(adapter);
    addTearDown(slash.dispose);
    select(adapter, [0], 9);
    expect(await slash.choose(slash.choices.single), true);
    final block = adapter.document!.blocks.single;
    expect(block.level, 4);
    expect(block.plainText, 'Title ');
    expect(block.id, 'legacy-body');
    adapter.editor.undoManager.undo();
    expect(adapter.plainText, 'Title /h4');
    expect(adapter.document, null);
    adapter.editor.undoManager.redo();
    expect(adapter.document!.blocks.single, block);
  });
  test('all textual conversions preserve runs and children', () async {
    for (final choice in basicBlockChoices.take(11)) {
      final adapter = create(
        'text',
        document: NoteDocument([
          DocumentBlock(
            id: 'root',
            kind: DocumentBlockKind.paragraph,
            runs: const [DocumentText('text')],
            children: [
              DocumentBlock(
                id: 'child',
                kind: DocumentBlockKind.paragraph,
                runs: const [DocumentText('nested')],
              ),
            ],
          ),
        ]),
      );
      select(adapter, [0], 0);
      expect(
        await BasicBlockCommands(adapter)
            .choose(choice, adapter.capture(range: false)!),
        true,
      );
      expect(adapter.visibleDocument.blocks.first.id, 'root');
      expect(adapter.visibleDocument.blocks.first.children.single.id, 'child');
      expect(adapter.plainText, 'text\nnested');
    }
  });
  test('table insert/add/remove/header keeps identities; cell block insertion refused', () async {
    final adapter = create('/table');
    select(adapter, [0], 6);
    expect(
      await BasicBlockCommands(adapter).choose(
        basicBlockChoices[11],
        adapter.capture(range: false)!,
        slashStart: 0,
      ),
      true,
    );
    final original = adapter.visibleDocument.blocks.last;
    select(adapter, [1, 0, 0], 0);
    final commands = TableCommands(adapter);
    expect(
      await commands.change(TableChange.addRow, adapter.capture(range: false)!),
      true,
    );
    var table = adapter.visibleDocument.blocks.last;
    expect(table.rows.length, 3);
    expect(table.rows.first, original.rows.first);
    expect(table.rows.last, original.rows.last);
    expect(
      await BasicBlockCommands(adapter)
          .choose(basicBlockChoices[11], adapter.capture(range: false)!),
      false,
    );
    expect(
      await commands.change(
        TableChange.addColumn,
        adapter.capture(range: false)!,
      ),
      true,
    );
    table = adapter.visibleDocument.blocks.last;
    expect(table.rows.first.cells.length, 3);
    expect(table.rows.first.cells.first.id, original.rows.first.cells.first.id);
    expect(
      await commands.change(
        TableChange.headerRow,
        adapter.capture(range: false)!,
      ),
      true,
    );
    expect(adapter.visibleDocument.blocks.last.headerRow, true);
    expect(
      await commands.change(
        TableChange.removeColumn,
        adapter.capture(range: false)!,
      ),
      true,
    );
    expect(
      await commands.change(
        TableChange.removeRow,
        adapter.capture(range: false)!,
      ),
      true,
    );
    expect(adapter.visibleDocument.blocks.last.rows.length, 2);
  });
  test('equation replacement/undo/cancel and stale Viewer guard', () async {
    var edit = true;
    final adapter = create('a + b', edit: () => edit),
        commands = EquationCommands(adapter);
    select(adapter, [0], 0, 5);
    final snapshot = adapter.capture()!;
    expect(commands.initialExpression(snapshot), 'a + b');
    expect(await commands.replace(snapshot, r'\sqrt{x}'), true);
    expect(
      adapter.visibleDocument.blocks.single.runs.single,
      DocumentMath(r'\sqrt{x}'),
    );
    expect(adapter.plainText, r'\sqrt{x}');
    final equation = adapter.capture()!;
    expect(commands.initialExpression(equation), r'\sqrt{x}');
    edit = false;
    expect(await commands.replace(equation, 'x'), false);
    edit = true;
    adapter.editor.undoManager.undo();
    expect(adapter.plainText, 'a + b');
    expect(adapter.document, null);
  });
  test(
    'blank Enter retains two paragraphs in a previously empty document',
    () async {
      final adapter = create('', document: NoteDocument(const []));
      final transaction = adapter.editor.transaction
        ..insertNode([1], engine.paragraphNode());
      await adapter.editor.apply(transaction);
      expect(adapter.visibleDocument.blocks.length, 2);
      expect(adapter.plainText, '\n');
      expect(
        adapter.visibleDocument.blocks.first.id !=
            adapter.visibleDocument.blocks.last.id,
        true,
      );
      adapter.editor.undoManager.undo();
      expect(adapter.visibleDocument.blocks, isEmpty);
    },
  );
  test(
    'equation conversion retains supported range style and removes link/code',
    () async {
      final adapter = create(
        '',
        document: NoteDocument([
          DocumentBlock(
            id: 'p',
            kind: DocumentBlockKind.paragraph,
            runs: [
              DocumentText(
                'x',
                marks: DocumentMarks(
                  fontSize: 28,
                  bold: true,
                  link: 'https://example.invalid',
                ),
              ),
            ],
          ),
        ]),
      );
      select(adapter, [0], 0, 1);
      expect(
        await EquationCommands(adapter)
            .replace(adapter.capture()!, r'\sqrt{x}'),
        true,
      );
      final math =
          adapter.visibleDocument.blocks.single.runs.single as DocumentMath;
      expect(math.marks.fontSize, 28);
      expect(math.marks.bold, true);
      expect(math.marks.link, null);
      expect(math.marks.inlineCode, false);
    },
  );
  test('Viewer toggle expansion does not change document/revision', () {
    final adapter = create(
      '',
      edit: () => false,
      document: NoteDocument([
        DocumentBlock(
          id: 'toggle',
          kind: DocumentBlockKind.toggle,
          runs: const [DocumentText('Show')],
        ),
      ]),
    );
    final before = adapter.document;
    adapter.expand('toggle');
    expect(adapter.expandedToggles['toggle'], false);
    expect(adapter.document, before);
    expect(adapter.revision, 0);
  });
}
