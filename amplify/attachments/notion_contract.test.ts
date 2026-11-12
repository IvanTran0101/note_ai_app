import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {test} from 'node:test';
import {validateBytes} from './byte_validation';
import {AttachmentError, fileMetadata, TYPES} from './models';

const digest = (bytes: Uint8Array) => createHash('sha256').update(bytes).digest('hex');

test('ATT-FR-03: backend enforces each declared type and inclusive size limit', () => {
  for (const [extension, [mimeType, limitMiB]] of Object.entries(TYPES)) {
    const metadata = {fileName: `file.${extension}`, mimeType, sizeBytes: limitMiB * 1024 * 1024, sha256: 'a'.repeat(64)};
    assert.deepEqual(fileMetadata(metadata), metadata);
    assert.throws(() => fileMetadata({...metadata, sizeBytes: metadata.sizeBytes + 1}), AttachmentError);
    assert.throws(() => fileMetadata({...metadata, mimeType: 'application/octet-stream'}), AttachmentError);
  }
  assert.throws(() => fileMetadata({fileName: '../file.txt', mimeType: 'text/plain', sizeBytes: 1, sha256: 'a'.repeat(64)}), AttachmentError);
});

test('ATT-FR-03: correct checksum cannot make disguised PNG bytes valid', async () => {
  const bytes = Buffer.from('not really a PNG');
  const metadata = {fileName: 'image.png', mimeType: 'image/png', sizeBytes: bytes.length, sha256: digest(bytes)};
  const read = async function* (start: number, end: number) { yield bytes.subarray(start, end); };
  await assert.rejects(validateBytes(metadata, read), AttachmentError);
});
