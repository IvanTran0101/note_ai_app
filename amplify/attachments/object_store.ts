import type { FileMetadata } from './models';
export type PinnedChunk = Readonly<{version: string; sha256: string; sizeBytes: number}>;
/** URLs are upload-only, transient, restricted to a fixed staging key. */
export interface AttachmentObjectStore {
  uploadUrl(key: string, size: number, sha256: string): Promise<Readonly<{url: string; headers: Record<string, string>}>>;
  pin(key: string, expectedSize: number, sha256: string): Promise<PinnedChunk>;
  read(key: string, version: string, start: number, end: number): AsyncIterable<Uint8Array>;
  finalize(key: string, metadata: FileMetadata, chunks: AsyncIterable<Uint8Array>): Promise<string>;
  removeStaging(prefix: string): Promise<void>;
}
