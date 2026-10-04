import assert from 'node:assert/strict';
import { parseMutationBody } from './request_parser';
import { normalizePayload, toNoteSnapshot } from './sync_store_codec';
import { SyncInvalidMutationError } from './sync_store_models';

for (const attachments of [[], [{ id: 'unverified-client-object' }]]) {
  const payload = { title: 'Title', content: 'Body', attachments };
  const result = parseMutationBody(JSON.stringify({ mutationId: 'm', noteId: 'n', operation: 'update', baseRevision: 1, payload }));
  assert.deepEqual(result, { ok: false, problem: 'ATTACHMENTS_UNSUPPORTED' });
  assert.throws(() => normalizePayload('update', payload), (e: unknown) =>
    e instanceof SyncInvalidMutationError && e.reason === 'ATTACHMENTS_UNSUPPORTED');
}
assert.throws(() => toNoteSnapshot({ attachments: [{ id: 'keep-existing' }] }), (e: unknown) =>
  e instanceof SyncInvalidMutationError && e.reason === 'ATTACHMENTS_UNSUPPORTED');
console.log('Attachment compatibility: 5 checks passed');
