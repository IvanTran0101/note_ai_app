import 'package:appflowy_editor/appflowy_editor.dart' as engine;
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/domain/notes/note_document.dart';
import 'package:note_ai_app/presentation/editor/rich_editor_adapter.dart';
import 'package:note_ai_app/presentation/editor/selection_formatting_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  RichEditorAdapter create({
    NoteDocument? document,
    String text = 'AABB',
    bool Function()? edit,
    int Function()? generation,
    void Function()? changed,
  }) {
    final adapter = RichEditorAdapter(
      document: document,
      legacyText: text,
      canEdit: edit ?? () => true,
      isLive: () => true,
      accessGeneration: generation ?? () => 1,
      onChanged: changed ?? () {},
    );
    addTearDown(adapter.dispose);
    return adapter;
  }

  void select(RichEditorAdapter adapter, int start, int end) {
    adapter.editor.selection = engine.Selection(
      start: engine.Position(path: [0], offset: start),
      end: engine.Position(path: [0], offset: end),
    );
  }

  test('combined inline marks and palette preserve Unicode through undo', () async {
    const text = 'Local first tiếng Việt 😀';
    final adapter = create(text: text);
    final formatter = SelectionFormattingController(adapter);
    select(adapter, 0, text.length);
    for (final mark in ['bold', 'italic', 'underline', 'strikethrough', 'code']) {
      expect(await formatter.toggle(adapter.capture()!, mark), true);
      expect(adapter.plainText, text);
    }
    final marked = adapter.document;
    expect(await formatter.color(adapter.capture()!, DocumentColor.blue), true);
    expect(adapter.plainText, text);
    adapter.editor.undoManager.undo();
    expect(adapter.document, marked);
    expect(adapter.plainText, text);
  });

  test('open/selection does not inflate legacy; font size touches only selected text', () async {
    var edits = 0;
    final adapter = create(changed: () => edits++),
        formatter = SelectionFormattingController(adapter);
    expect(adapter.document, null);
    select(adapter, 2, 4);
    expect(adapter.document, null);
    expect(edits, 0);
    expect(await formatter.size(adapter.capture()!, 24), true);
    final runs = adapter.document!.blocks.single.runs;
    expect(runs.first, const DocumentText('AA'));
    expect(runs.last, DocumentText('BB', marks: DocumentMarks(fontSize: 24)));
    expect(adapter.plainText, 'AABB');
    expect(edits, 1);
    adapter.editor.undoManager.undo();
    expect(adapter.document, null);
    expect(adapter.plainText, 'AABB');
  });
  test(
    'stale range/document/access and Viewer refuse without a mutation',
    () async {
      var epoch = 1, allowed = true;
      final adapter = create(edit: () => allowed, generation: () => epoch);
      final formatter = SelectionFormattingController(adapter);
      select(adapter, 0, 2);
      final old = adapter.capture()!;
      select(adapter, 2, 4);
      expect(await formatter.size(old, 24), false);
      final selected = adapter.capture()!;
      epoch++;
      expect(await formatter.size(selected, 24), false);
      expect(adapter.document, null);
      allowed = false;
      expect(adapter.capture(), null);
      expect(await formatter.size(selected, 24), false);
    },
  );
  test(
    'grapheme boundaries keep emoji and combining characters intact',
    () async {
      final adapter = create(text: 'A📝e\u0301B');
      final formatter = SelectionFormattingController(adapter);
      select(
        adapter,
        2,
        4,
      ); // Inside surrogate pair through inside combining grapheme.
      expect(await formatter.size(adapter.capture()!, 32), true);
      final runs = adapter.document!.blocks.single.runs;
      expect(runs.first, const DocumentText('A'));
      expect(
        runs[1],
        DocumentText('📝e\u0301', marks: DocumentMarks(fontSize: 32)),
      );
      expect(runs.last, const DocumentText('B'));
    },
  );
  test('mixed/clear includes semantic palette/size while math identity is retained', () async {
    final marks = DocumentMarks(
      bold: true,
      fontSize: 24,
      color: DocumentColor.red,
    );
    final doc = NoteDocument([
      DocumentBlock(
        id: 'p',
        kind: DocumentBlockKind.paragraph,
        runs: [
          DocumentText('A', marks: marks),
          const DocumentText('B'),
          DocumentMath('x', marks: marks),
        ],
      ),
    ]);
    final adapter = create(document: doc),
        formatter = SelectionFormattingController(adapter);
    select(adapter, 0, 3);
    final selected = adapter.capture()!;
    expect(formatter.state(selected, 'bold').mixed, true);
    expect(formatter.containsMath(selected), true);
    expect(await formatter.link(selected, 'https://example.invalid'), false);
    expect(await formatter.toggle(selected, 'code'), false);
    expect(await formatter.clear(selected), true);
    expect(adapter.document!.blocks.single.runs, [
      const DocumentText('AB'),
      DocumentMath('x'),
    ]);
  });
  test(
    'invalid size/link refuses without changing the existing draft',
    () async {
      final adapter = create(),
          formatter = SelectionFormattingController(adapter);
      select(adapter, 0, 2);
      final selected = adapter.capture()!;
      expect(() => formatter.size(selected, 49), throwsArgumentError);
      expect(
        () => formatter.link(selected, 'javascript:alert(1)'),
        throwsArgumentError,
      );
      expect(adapter.document, null);
    },
  );
}
