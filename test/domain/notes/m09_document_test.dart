import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/domain/notes/note_document.dart';

import 'm09_document_fixtures.dart';

void main() {
  test(
    'all13 choices have typed blocks and deterministic Unicode projection',
    () {
      final blocks = <DocumentBlock>[
        block('p', text: 'Tiếng Việt 📝\n exact '),
        for (var level = 1; level <= 4; level++)
          DocumentBlock(
            id: 'h$level',
            kind: DocumentBlockKind.heading,
            level: level,
            runs: [DocumentText('H$level')],
          ),
        for (final kind in [
          DocumentBlockKind.bulletedList,
          DocumentBlockKind.numberedList,
          DocumentBlockKind.todo,
          DocumentBlockKind.toggle,
          DocumentBlockKind.callout,
          DocumentBlockKind.quote,
        ])
          DocumentBlock(
            id: kind.name,
            kind: kind,
            checked: kind == DocumentBlockKind.todo ? false : null,
            runs: [DocumentText(kind.name)],
            children: [block('${kind.name}_child', text: 'nested')],
          ),
        table('table'),
        DocumentBlock(id: 'divider', kind: DocumentBlockKind.divider),
      ];
      final document = NoteDocument(blocks);
      expect(document.blocks.length, 13);
      expect(
        document.plainText,
        startsWith('Tiếng Việt 📝\n exact \nH1\nH2\nH3\nH4'),
      );
      expect(document.plainText, endsWith('quote\nnested\nA\tB\nC\tD\n'));
      expect(document.toString(), isNot(contains('Tiếng')));
    },
  );

  test(
    'normalizing adjacent text keeps Unicode and treats math as an atom',
    () {
      final runs = <DocumentInline>[
        const DocumentText('a'),
        const DocumentText(' 📝'),
        DocumentMath(r'\sqrt{x}', marks: DocumentMarks(fontSize: 24)),
        const DocumentText('b'),
      ];
      final first = NoteDocument([
        DocumentBlock(id: 'p', kind: DocumentBlockKind.paragraph, runs: runs),
      ]);
      final second = NoteDocument([
        DocumentBlock(
          id: 'p',
          kind: DocumentBlockKind.paragraph,
          runs: [const DocumentText('a 📝'), runs[2], const DocumentText('b')],
        ),
      ]);
      expect(first, second);
      expect(first.hashCode, second.hashCode);
      expect(first.blocks.single.runs.length, 3);
      expect(first.plainText, r'a 📝\sqrt{x}b');
      runs.clear();
      expect(first.blocks.single.runs.length, 3);
      expect(() => first.blocks.clear(), throwsUnsupportedError);
      expect(() => first.blocks.single.runs.clear(), throwsUnsupportedError);
    },
  );

  test('table row/cell collections are frozen', () {
    final cells = [
      DocumentCell(id: 'c', runs: [const DocumentText('one')]),
    ];
    final row = DocumentRow(id: 'r', cells: cells);
    cells.clear();
    expect(row.cells.single.plainText, 'one');
    expect(() => row.cells.clear(), throwsUnsupportedError);
  });

  test('duplicate identity is refused across blocks, rows and cells', () {
    expect(
      () => NoteDocument([block('same'), block('same')]),
      throwsArgumentError,
    );
    expect(
      () => NoteDocument([block('t_r0'), table('t')]),
      throwsArgumentError,
    );
    expect(() => block('invalid id'), throwsArgumentError);
  });

  test('block-specific attributes and grids are validated', () {
    for (final level in [0, 5]) {
      expect(
        () => DocumentBlock(
          id: 'h',
          kind: DocumentBlockKind.heading,
          level: level,
        ),
        throwsArgumentError,
      );
    }
    expect(
      () => DocumentBlock(
        id: 'p',
        kind: DocumentBlockKind.paragraph,
        checked: false,
      ),
      throwsArgumentError,
    );
    expect(
      () => DocumentBlock(id: 'todo', kind: DocumentBlockKind.todo),
      throwsArgumentError,
    );
    expect(
      () => DocumentBlock(
        id: 'd',
        kind: DocumentBlockKind.divider,
        children: [block('p')],
      ),
      throwsArgumentError,
    );
    expect(
      () => DocumentBlock(id: 't', kind: DocumentBlockKind.table, rows: []),
      throwsArgumentError,
    );
    expect(
      () => DocumentBlock(
        id: 't',
        kind: DocumentBlockKind.table,
        rows: [
          DocumentRow(
            id: 'r0',
            cells: [DocumentCell(id: 'c0', runs: [])],
          ),
          DocumentRow(id: 'r1', cells: []),
        ],
      ),
      throwsArgumentError,
    );
  });

  test('new document limits are bounded by depth, blocks, cells and UTF8', () {
    expect(
      () => NoteDocument([for (var i = 0; i < 513; i++) block('b$i')]),
      throwsArgumentError,
    );
    var nested = block('leaf');
    for (var i = 0; i < 8; i++) {
      nested = block('depth$i', children: [nested]);
    }
    expect(() => NoteDocument([nested]), throwsArgumentError);
    expect(
      () => NoteDocument([
        table('a', rows: 32, columns: 12),
        table('b', rows: 32, columns: 12),
      ]),
      throwsArgumentError,
    );
    expect(
      () => NoteDocument([block('big', text: List.filled(33334, 'ệ').join())]),
      throwsArgumentError,
    );
    final runs = [
      for (var i = 0; i < 4097; i++)
        DocumentText('x', marks: DocumentMarks(bold: i.isEven)),
    ];
    expect(
      () => NoteDocument([
        DocumentBlock(
          id: 'many',
          kind: DocumentBlockKind.paragraph,
          runs: runs,
        ),
      ]),
      throwsArgumentError,
    );
  });

  test('marks preserve semantic palette and bounded size', () {
    for (final size in [12.0, 14.0, 16.0, 18.0, 24.0, 32.0, 48.0]) {
      final marks = DocumentMarks(
        fontSize: size,
        color: DocumentColor.blue,
        highlight: DocumentColor.yellow,
      );
      expect(marks.fontSize, size);
    }
    for (final size in [11.0, 49.0, double.nan, double.infinity]) {
      expect(() => DocumentMarks(fontSize: size), throwsArgumentError);
    }
  });

  test('link schemes/control characters/UTF8 bytes are checked without logging value', () {
    for (final link in [
      'https://example.invalid/a',
      'http://example.invalid',
      'mailto:qa@example.invalid',
    ]) {
      expect(DocumentMarks(link: link).link, link);
    }
    for (final link in [
      'javascript:private-sentinel',
      'file:///x',
      'data:x',
      '/relative',
      'https://',
      'https://example.invalid/\nprivate-sentinel',
      'https://example.invalid/${List.filled(1000, 'ệ').join()}',
    ]) {
      try {
        DocumentMarks(link: link);
        fail('Must reject invalid link');
      } on ArgumentError catch (error) {
        expect(error.toString(), isNot(contains('private-sentinel')));
      }
    }
  });

  test(
    'offline equations permit bounded math and refuse external commands',
    () {
      expect(
        DocumentMath(r'\frac{x}{2}+\sqrt{y}').plainText,
        r'\frac{x}{2}+\sqrt{y}',
      );
      for (final expression in [
        '',
        '{x',
        'x}',
        r'\href{https://example.invalid}{x}',
        r'\includegraphics{x}',
        List.filled(513, 'x').join(),
        '{{{{{{{{{x}}}}}}}}}',
      ]) {
        expect(() => DocumentMath(expression), throwsArgumentError);
      }
      expect(
        () => DocumentMath('x', marks: DocumentMarks(inlineCode: true)),
        throwsArgumentError,
      );
    },
  );
}
