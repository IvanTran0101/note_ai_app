import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/notes/note_dto.dart';
import 'package:note_ai_app/domain/notes/note.dart';
import 'package:note_ai_app/domain/notes/note_document.dart';
import 'package:note_ai_app/domain/notes/note_protection.dart';
import 'package:note_ai_app/domain/labels/label.dart';

import 'm09_document_fixtures.dart';

void main() {
  test('empty and divider-only rich content is valid; legacy rules remain', () {
    final empty = NoteDocument([]);
    final note = create(empty);
    expect(note.content, '');
    note.replaceText('Renamed', '', DateTime.utc(2026, 10, 15));
    expect(note.document, empty);
    expect(
      NoteDocument([DocumentBlock(id: 'line', kind: DocumentBlockKind.divider)])
          .plainText,
      '',
    );
    expect(
      () => Note.create(
        id: 'n',
        ownerId: 'owner',
        title: 'Title',
        content: '',
        now: at,
      ),
      throwsArgumentError,
    );
    expect(
      () => Note.create(
        id: 'n',
        ownerId: 'owner',
        title: ' ',
        content: '',
        document: empty,
        now: at,
      ),
      throwsArgumentError,
    );
    expect(
      Note.create(
        id: 'n',
        ownerId: 'owner',
        title: 'Title',
        content: 'legacy',
        now: at,
      ).document,
      isNull,
    );
  });

  test('format-only change advances time and retains pin/labels/security', () {
    final plain = NoteDocument([block('p', text: 'same')]);
    final note = create(plain)
      ..pin(at)
      ..attachLabel(
        Label.create(id: 'label-a', ownerId: 'owner', name: 'Label', now: at),
        at,
      );
    final protection = note.protection;
    final styled = NoteDocument([
      DocumentBlock(
        id: 'p',
        kind: DocumentBlockKind.paragraph,
        runs: [
          DocumentText('same', marks: DocumentMarks(bold: true, fontSize: 24)),
        ],
      ),
    ]);
    note.replaceDocument('Title', styled, at.add(const Duration(seconds: 1)));
    expect(note.content, 'same');
    expect(note.document, styled);
    expect(note.updatedAt, at.add(const Duration(seconds: 1)));
    expect(note.pinnedAt, at);
    expect(note.labelIds, ['label-a']);
    expect(note.protection, protection);
    note.replaceDocument('Title', styled, at.add(const Duration(seconds: 2)));
    expect(note.updatedAt, at.add(const Duration(seconds: 1)));
    expect(() => note.replaceContent('flattened', at), throwsArgumentError);
  });

  test('unavailable/metadata projections cannot expose a document', () {
    final document = NoteDocument([block('p', text: 'private-sentinel')]);
    expect(
      NoteDto.fromDomain(create(document)).metadataOnly().document,
      isNull,
    );
    expect(
      () => Note.reconstitute(
        id: 'n',
        ownerId: 'owner',
        title: '',
        content: '',
        createdAt: at,
        updatedAt: at,
        contentAvailable: false,
        document: document,
      ),
      throwsArgumentError,
    );
    final hidden = Note.reconstitute(
      id: 'n',
      ownerId: 'owner',
      title: '',
      content: '',
      createdAt: at,
      updatedAt: at,
      contentAvailable: false,
    );
    expect(() => hidden.document, throwsA(isA<NoteContentUnavailable>()));
    expect(NoteDto.fromDomain(hidden).document, isNull);
    expect(
      () => Note.reconstitute(
        id: 'n',
        ownerId: 'owner',
        title: 'Title',
        content: 'different',
        createdAt: at,
        updatedAt: at,
        document: document,
      ),
      throwsArgumentError,
    );
  });
}
