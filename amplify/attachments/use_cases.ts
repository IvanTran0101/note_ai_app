import { createHash, randomUUID } from 'node:crypto';
import { NoteSecurityError } from '../protection/protection_store';
import type { NoteOperation, NoteSecurityAuthority } from '../protection/protection_store';
import { AttachmentAttemptStore } from './attempt_store';
import { AttachmentError, attemptId, chunkCount, chunkSize, CHUNK_BYTES, fileMetadata, sameDescriptor } from './models';
import type { Attempt, AttachmentDescriptor } from './models';
import type { AttachmentObjectStore } from './object_store';
import { validateBytes } from './byte_validation';
export const stagingPrefix = (a: Attempt) => `staging/${createHash('sha256').update(JSON.stringify([a.ownerId, a.targetNoteId, a.id])).digest('hex')}/`;
export const stagingKey = (a: Attempt, index: number) => `${stagingPrefix(a)}${index}`;

/** Durable server attempts. Fresh authority around every storage await and response. */
export class AttachmentUseCases {
  constructor(readonly attempts: AttachmentAttemptStore, readonly objects: AttachmentObjectStore,
    readonly security: NoteSecurityAuthority) {}
  async authority(actor: string, owner: string, note: string, op: NoteOperation, grant?: string) {
    if (op !== 'attachmentRead' && actor !== owner) throw new NoteSecurityError('denied');
    const a = await this.security.authorize(actor, owner, note, op, grant);
    const n = await this.attempts.feed.note(owner, note);
    if (!n || n.deletedAt !== null) throw new NoteSecurityError('denied');
    return {a, n};
  }
  private async bound(actor: string, owner: string, note: string, id: string, grant?: string, currentEpoch = true) {
    const {a, n} = await this.authority(actor, owner, note, 'attachmentWrite', grant);
    const attempt = await this.attempts.read(owner, note, attemptId(id));
    if (!attempt || attempt.actorId !== actor || attempt.ownerId !== owner || attempt.targetNoteId !== note) throw new AttachmentError('denied');
    if (currentEpoch && (attempt.protectionRevision !== a.revision || attempt.protected !== a.enabled)) throw new AttachmentError('stale');
    return {a, n, attempt};
  }
  async begin(actor: string, owner: string, note: string, input: unknown, grant?: string) {
    const m = fileMetadata(input), id = attemptId((input as {id: unknown}).id);
    const {a, n} = await this.authority(actor, owner, note, 'attachmentWrite', grant);
    const old = await this.attempts.read(owner, note, id);
    if (old) {
      if (old.actorId !== actor || JSON.stringify(fileMetadata(old)) !== JSON.stringify(m)) throw new AttachmentError('invalid');
      // Owner's fresh authority can continue the same immutable payload after
      // password administration. Linked/unlinked objects are never rebound.
      if (['uploading', 'verifying', 'verified'].includes(old.phase) && !n.attachments?.some(x => x.id === id)) {
        let next = old;
        if (old.protectionRevision !== a.revision || old.protected !== a.enabled) {
          next = {...next, protected: a.enabled, protectionRevision: a.revision,
            phase: old.phase === 'verifying' ? 'uploading' : old.phase};
        }
        // A staging lifecycle expiry cannot strand a durable local draft.
        // Inspect pinned versions in bounded batches; transient storage failure
        // keeps the existing ACKs, while proven absence restarts the same payload.
        if (next.phase === 'uploading' || next.phase === 'verifying') {
          for (let offset = 0; offset < next.chunks.length; offset += 10) {
            const exists = await Promise.all(next.chunks.slice(offset, offset + 10).map((chunk, i) =>
              this.objects.hasVersion(stagingKey(next, offset + i), chunk.version)));
            await this.authority(actor, owner, note, 'attachmentWrite', grant);
            if (exists.some(x => !x)) {next = {...next, phase: 'uploading', chunks: []}; break;}
          }
        }
        if (next !== old) await this.attempts.save(old, {...next, generation: old.generation + 1}, a, n.revision);
      }
      return this.status(actor, owner, note, id, grant);
    }
    const next: Attempt = {...m, id, actorId: actor, ownerId: owner, targetNoteId: note,
      protectionRevision: a.revision, protected: a.enabled, phase: 'uploading', generation: 1,
      finalKey: `final/${randomUUID()}`, createdAt: new Date().toISOString(), chunks: []};
    await this.attempts.save(null, next, a, n.revision);
    return this.status(actor, owner, note, id, grant);
  }
  async status(actor: string, owner: string, note: string, id: string, grant?: string) {
    const {attempt} = await this.bound(actor, owner, note, id, grant, false);
    return {id: attempt.id, phase: attempt.phase, chunkCount: chunkCount(attempt),
      completedChunks: attempt.chunks.length, ...(attempt.descriptor ? {attachment: attempt.descriptor} : {})};
  }
  async uploadUrl(actor: string, owner: string, note: string, id: string, index: number, sha256: string, grant?: string) {
    const {attempt} = await this.bound(actor, owner, note, id, grant);
    if (attempt.phase !== 'uploading' || index !== attempt.chunks.length || !/^[a-f0-9]{64}$/.test(sha256)) throw new AttachmentError('stale');
    const result = await this.objects.uploadUrl(stagingKey(attempt, index), chunkSize(attempt, index), sha256);
    await this.bound(actor, owner, note, id, grant); return result;
  }
  async confirmChunk(actor: string, owner: string, note: string, id: string, index: number, sha256: string, grant?: string) {
    let {a, n, attempt} = await this.bound(actor, owner, note, id, grant);
    if (attempt.phase !== 'uploading' || !/^[a-f0-9]{64}$/.test(sha256)) throw new AttachmentError('stale');
    if (index < attempt.chunks.length) {
      if (attempt.chunks[index].sha256 !== sha256) throw new AttachmentError('invalid');
      return this.status(actor, owner, note, id, grant);
    }
    if (index !== attempt.chunks.length) throw new AttachmentError('invalid');
    const chunk = await this.objects.pin(stagingKey(attempt, index), chunkSize(attempt, index), sha256);
    const live = await this.bound(actor, owner, note, id, grant); a = live.a; n = live.n;
    if (live.attempt.generation !== attempt.generation) throw new AttachmentError('stale');
    await this.attempts.save(attempt, {...attempt, chunks: [...attempt.chunks, chunk], generation: attempt.generation + 1}, a, n.revision);
    return this.status(actor, owner, note, id, grant);
  }
  private stagedRead(a: Attempt, start: number, end: number): AsyncIterable<Uint8Array> {
    const objects = this.objects;
    return (async function* () {
      for (let i = Math.floor(start / CHUNK_BYTES); i * CHUNK_BYTES < end; i++) {
        const base = i * CHUNK_BYTES, chunk = a.chunks[i]; if (!chunk) throw new AttachmentError('invalid');
        yield* objects.read(stagingKey(a, i), chunk.version, Math.max(0, start - base), Math.min(chunk.sizeBytes, end - base));
      }
    })();
  }
  async verify(actor: string, owner: string, note: string, id: string, grant?: string) {
    let {a, n, attempt} = await this.bound(actor, owner, note, id, grant);
    if (['verified', 'linked'].includes(attempt.phase)) return this.status(actor, owner, note, id, grant);
    if (attempt.phase === 'cancelled' || attempt.phase === 'unlinked') throw new AttachmentError('cancelled');
    if (attempt.chunks.length !== chunkCount(attempt)) throw new AttachmentError('invalid');
    if (attempt.phase === 'uploading') {
      const next: Attempt = {...attempt, phase: 'verifying', generation: attempt.generation + 1};
      await this.attempts.save(attempt, next, a, n.revision); attempt = next;
    }
    const guarded = (start: number, end: number) => {
      const self = this;
      return (async function* () {
        for await (const bytes of self.stagedRead(attempt, start, end)) {
          const current = await self.bound(actor, owner, note, id, grant);
          if (current.attempt.generation !== attempt.generation) throw new AttachmentError('stale');
          yield bytes;
        }
      })();
    };
    await validateBytes(attempt, guarded);
    const version = await this.objects.finalize(attempt.finalKey, attempt, guarded(0, attempt.sizeBytes));
    // Verify the pinned final version as well, including unknown completion recovery.
    await validateBytes(attempt, (s, e) => this.objects.read(attempt.finalKey, version, s, e));
    const live = await this.bound(actor, owner, note, id, grant); a = live.a; n = live.n;
    if (live.attempt.generation !== attempt.generation) throw new AttachmentError('stale');
    const attachment: AttachmentDescriptor = {id, noteId: note, ...fileMetadata(attempt),
      storageObjectId: attempt.finalKey, objectVersion: version, addedAt: attempt.createdAt};
    await this.attempts.save(attempt, {...attempt, phase: 'verified', descriptor: attachment,
      generation: attempt.generation + 1}, a, n.revision);
    return this.status(actor, owner, note, id, grant);
  }
  async cancel(actor: string, owner: string, note: string, id: string, grant?: string) {
    const {a, n} = await this.authority(actor, owner, note, 'attachmentWrite', grant);
    const attempt = await this.attempts.read(owner, note, attemptId(id));
    if (!attempt) {
      await this.attempts.cancelMissing(owner, note, id, a, n.revision);
      return {id, phase: 'cancelled'};
    }
    if (attempt.actorId !== actor || attempt.ownerId !== owner || attempt.targetNoteId !== note) throw new AttachmentError('denied');
    if (attempt.phase === 'linked' || n.attachments?.some(x => x.id === id)) throw new AttachmentError('stale');
    if (attempt.phase !== 'cancelled' && attempt.phase !== 'unlinked') {
      await this.attempts.save(attempt, {...attempt, phase: 'cancelled', generation: attempt.generation + 1}, a, n.revision);
    }
    // Only staging keys. Final deletion is never inferred from cancellation.
    await this.objects.removeStaging(stagingPrefix(attempt));
    return {id, phase: 'cancelled'};
  }
  async content(actor: string, owner: string, note: string, id: string, version: string,
    start: number, end: number, grant?: string, exportFile = false) {
    if (exportFile) await this.authority(actor, owner, note, 'export', grant);
    const {n} = await this.authority(actor, owner, note, 'attachmentRead', grant);
    const d = n.attachments?.find(x => x.id === id);
    if (!d || d.objectVersion !== version) throw new AttachmentError('denied');
    if (!Number.isSafeInteger(start) || !Number.isSafeInteger(end) || start < 0 || end <= start ||
        end > d.sizeBytes || end - start > CHUNK_BYTES) throw new AttachmentError('invalid');
    const data = Buffer.alloc(end - start); let count = 0;
    try {
      for await (const bytes of this.objects.read(d.storageObjectId, d.objectVersion, start, end)) {
        if (count + bytes.length > data.length) throw new AttachmentError('invalid');
        data.set(bytes, count); count += bytes.length;
      }
      const live = await this.authority(actor, owner, note, 'attachmentRead', grant);
      if (exportFile) await this.authority(actor, owner, note, 'export', grant);
      if (count !== data.length || !live.n.attachments?.some(x => sameDescriptor(x, d))) throw new AttachmentError('denied');
      return {bytes: data, descriptor: d};
    } catch (e) { data.fill(0); throw e; }
  }
}
