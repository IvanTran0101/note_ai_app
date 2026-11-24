/** Attachment metadata/attempt contract. No SDK, credentials, URLs or bytes in Note. */
export const CHUNK_BYTES = 256 * 1024;
export const MAX_CACHE_BYTES = 250 * 1024 * 1024;
export const TYPES: Readonly<Record<string, readonly [string, number]>> = {
  jpg: ['image/jpeg', 10], jpeg: ['image/jpeg', 10], png: ['image/png', 10],
  webp: ['image/webp', 10], mp4: ['video/mp4', 50], pdf: ['application/pdf', 20],
  txt: ['text/plain', 20], csv: ['text/csv', 20],
};
export class AttachmentError extends Error {
  constructor(readonly code: 'invalid' | 'denied' | 'stale' | 'cancelled' | 'quota' | 'unavailable') {
    super(`AttachmentError:${code}`); this.name = 'AttachmentError';
  }
}
export type FileMetadata = Readonly<{ fileName: string; mimeType: string; sizeBytes: number; sha256: string }>;
export type AttachmentDescriptor = FileMetadata & Readonly<{
  id: string; noteId: string; storageObjectId: string; objectVersion: string; addedAt: string;
}>;
export type Attempt = FileMetadata & Readonly<{
  id: string; actorId: string; ownerId: string; targetNoteId: string;
  protectionRevision: number; protected: boolean;
  phase: 'uploading' | 'verifying' | 'verified' | 'linked' | 'unlinked' | 'cancelled';
  generation: number; finalKey: string; createdAt: string;
  chunks: readonly Readonly<{version: string; sha256: string; sizeBytes: number}>[];
  descriptor?: AttachmentDescriptor;
}>;
const identity = (v: unknown): v is string => typeof v === 'string' && !!v.trim() &&
  v.length <= 128 && !/[\x00-\x1f\x7f]/.test(v) && !v.includes('://');
export function attemptId(v: unknown): string {
  if (typeof v !== 'string' || !/^[a-f0-9]{64}$/.test(v)) throw new AttachmentError('invalid');
  return v;
}
export function fileMetadata(v: unknown): FileMetadata {
  if (!v || typeof v !== 'object' || Array.isArray(v)) throw new AttachmentError('invalid');
  const b = v as FileMetadata;
  if (typeof b.fileName !== 'string' || !b.fileName || b.fileName.length > 255 ||
      /[/\\\x00-\x1f\x7f]/.test(b.fileName)) throw new AttachmentError('invalid');
  const type = TYPES[b.fileName.split('.').at(-1)?.toLowerCase() ?? ''];
  if (!type || b.mimeType !== type[0] || !Number.isSafeInteger(b.sizeBytes) ||
      b.sizeBytes <= 0 || b.sizeBytes > type[1] * 1024 * 1024 ||
      typeof b.sha256 !== 'string' || !/^[a-f0-9]{64}$/.test(b.sha256)) throw new AttachmentError('invalid');
  return {fileName: b.fileName, mimeType: b.mimeType, sizeBytes: b.sizeBytes, sha256: b.sha256};
}
export function descriptor(v: unknown, noteId?: string): AttachmentDescriptor {
  const m = fileMetadata(v); const b = v as AttachmentDescriptor;
  if (Object.keys(b).length !== 9 || ![b.id, b.noteId, b.storageObjectId, b.objectVersion].every(identity) ||
      noteId !== undefined && b.noteId !== noteId || typeof b.addedAt !== 'string' ||
      !b.addedAt.endsWith('Z') || !Number.isFinite(Date.parse(b.addedAt))) throw new AttachmentError('invalid');
  return {id: b.id, noteId: b.noteId, ...m, storageObjectId: b.storageObjectId,
    objectVersion: b.objectVersion, addedAt: b.addedAt};
}
export function manifest(v: unknown, noteId?: string): readonly AttachmentDescriptor[] {
  if (!Array.isArray(v) || v.length > 10) throw new AttachmentError('invalid');
  const result = v.map(x => descriptor(x, noteId));
  if (new Set(result.map(x => x.id)).size !== result.length ||
      result.reduce((n, x) => n + x.sizeBytes, 0) > 100 * 1024 * 1024) throw new AttachmentError('quota');
  return result;
}
export const sameDescriptor = (a: AttachmentDescriptor, b: AttachmentDescriptor) =>
  JSON.stringify(descriptor(a)) === JSON.stringify(descriptor(b));
export const chunkCount = (a: FileMetadata) => Math.ceil(a.sizeBytes / CHUNK_BYTES);
export const chunkSize = (a: FileMetadata, index: number) => {
  if (!Number.isSafeInteger(index) || index < 0 || index >= chunkCount(a)) throw new AttachmentError('invalid');
  return Math.min(CHUNK_BYTES, a.sizeBytes - index * CHUNK_BYTES);
};
