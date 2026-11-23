import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/domain/notes/attachment.dart';
import 'package:note_ai_app/domain/notes/note.dart';
import 'package:note_ai_app/domain/notes/note_document.dart';

void main() {
  final now = DateTime.utc(2026, 10, 23, 9);

  Attachment attachment(String id) => Attachment(
    id: id,
    noteId: 'note',
    fileName: '$id.txt',
    mimeType: 'text/plain',
    sizeBytes: 1,
    storageObjectId: 'object-$id',
    objectVersion: 'version-1',
    sha256: List.filled(64, 'a').join(),
    addedAt: now,
  );

  DocumentBlock file(String blockId, String attachmentId) => DocumentBlock(
    id: blockId,
    kind: DocumentBlockKind.attachment,
    attachmentId: attachmentId,
  );

  test('removes every matching root and nested File reference only', () {
    final removed = attachment('attachment-remove');
    final kept = attachment('attachment-keep');
    final document = NoteDocument([
      DocumentBlock(
        id: 'callout',
        kind: DocumentBlockKind.callout,
        runs: [DocumentText('Callout text', marks: DocumentMarks(bold: true))],
        children: [
          file('nested-copy-1', removed.id),
          DocumentBlock(
            id: 'child-text',
            kind: DocumentBlockKind.paragraph,
            runs: [
              DocumentText('keep this', marks: DocumentMarks(italic: true)),
            ],
          ),
          file('nested-copy-2', removed.id),
          file('nested-other', kept.id),
        ],
      ),
      file('root-copy', removed.id),
      DocumentBlock(
        id: 'last',
        kind: DocumentBlockKind.paragraph,
        runs: [DocumentText('last block')],
      ),
    ], inlineAttachments: true);
    final expected = NoteDocument([
      DocumentBlock(
        id: 'callout',
        kind: DocumentBlockKind.callout,
        runs: [DocumentText('Callout text', marks: DocumentMarks(bold: true))],
        children: [
          DocumentBlock(
            id: 'child-text',
            kind: DocumentBlockKind.paragraph,
            runs: [
              DocumentText('keep this', marks: DocumentMarks(italic: true)),
            ],
          ),
          file('nested-other', kept.id),
        ],
      ),
      DocumentBlock(
        id: 'last',
        kind: DocumentBlockKind.paragraph,
        runs: [DocumentText('last block')],
      ),
    ], inlineAttachments: true);
    final note = Note.reconstitute(
      id: 'note',
      ownerId: 'owner',
      title: 'Attachment note',
      content: document.plainText,
      createdAt: now,
      updatedAt: now,
      attachments: [removed, kept],
      document: document,
    );

    expect(document.attachmentReferenceIds, {removed.id, kept.id});
    note.removeAttachment(removed.id, now.add(const Duration(minutes: 1)));

    expect(note.document, expected);
    expect(note.content, expected.plainText);
    expect(note.attachments, [kept]);
    expect(note.document!.attachmentReferenceIds, {kept.id});
    expect(note.updatedAt, now.add(const Duration(minutes: 1)));
    expect(note.document!.inlineAttachments, true);

    final updatedAt = note.updatedAt;
    note.removeAttachment(removed.id, now.add(const Duration(minutes: 2)));
    expect(note.updatedAt, updatedAt, reason: 'repeat removal is idempotent');
  });
}
