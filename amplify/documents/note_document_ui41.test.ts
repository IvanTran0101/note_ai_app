import test from 'node:test';
import assert from 'node:assert/strict';

import {parseNoteDocument, projectDocument} from './note_document';
import {InvalidDocumentError} from './document_models';

test('File blocks parse as positional structure and never project attachment metadata', () => {
  const input = {
    version: 1,
    inlineAttachments: true,
    blocks: [
      {id: 'before', type: 'paragraph', runs: [{type: 'text', text: 'Before'}]},
      {id: 'empty-file', type: 'attachment'},
      {id: 'file', type: 'attachment', attachmentId: 'draft_cache-7'},
      {id: 'after', type: 'paragraph', runs: [{type: 'text', text: 'After'}]},
    ],
  };
  const document = parseNoteDocument(input);
  assert.deepEqual(document, input);
  assert.equal(projectDocument(document), 'Before\n\n\nAfter');
  assert.equal(JSON.stringify(projectDocument(document)).includes('draft_cache-7'), false);
});

test('old documents omit inline file metadata and malformed file blocks refuse', () => {
  const old = {version: 1, blocks: [{id: 'p', type: 'paragraph', runs: []}]};
  assert.deepEqual(parseNoteDocument(old), old);

  const invalid: unknown[] = [
    {version: 1, blocks: [{id: 'file', type: 'attachment'}]},
    {version: 1, inlineAttachments: true, blocks: [{id: 'file', type: 'attachment', runs: []}]},
    {version: 1, inlineAttachments: true, blocks: [{id: 'file', type: 'attachment', attachmentId: 'unsafe/id'}]},
    {version: 1, inlineAttachments: true, blocks: [{id: 'file', type: 'attachment', children: []}]},
    {version: 1, inlineAttachments: 'true', blocks: []},
  ];
  for (const value of invalid) {
    assert.throws(() => parseNoteDocument(value), InvalidDocumentError);
  }
});
