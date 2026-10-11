/**
 * RAG v1 canonical authority: the frozen per-request context and per-candidate chunk checks.
 *
 * Contract: docs/contracts/rag_api_v1.md §1/§5/§7. Policy: docs/rag/policy_v1.json
 * `approvedScope`, `safety`, `technicalDefaults.wire`.
 *
 * The canonical state is read only after the verified actor boundary and is cloned and frozen
 * before any provider sees it: a provider may never mutate the snapshot the verdict was based
 * on. `revalidate()` re-reads the store and blocks egress when consent, session generation,
 * index readiness or any snapshotted source note changed. Store failures surface as
 * PROVIDER_UNAVAILABLE; an aborted signal is always TIMEOUT. No note is ever written.
 */
import { RagFailure } from './types';
import type { AuthorityStore, CanonicalNote, CanonicalState, Chunk, RagRequest, RequestContext } from './types';
import { CONSENT_VERSION, isValidIdentifier, isValidUnicode, WIRE_VERSION } from './contract';
import { assertChunk, isSafeInteger, SECTION_BODY } from './chunking';

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === 'object' && value !== null && !Array.isArray(value);

const deepFreeze = <T>(value: T): T => {
  if (value !== null && typeof value === 'object' && !Object.isFrozen(value)) {
    Object.freeze(value);
    for (const key of Object.keys(value)) deepFreeze((value as Record<string, unknown>)[key]);
  }
  return value;
};

const assertLive = (signal: AbortSignal): void => {
  if (signal.aborted) throw new RagFailure('TIMEOUT');
};

const assertRequest = (request: RagRequest): void => {
  if (!isRecord(request) || request.wireVersion !== WIRE_VERSION) throw new RagFailure('INVALID_INPUT');
  if (typeof request.question !== 'string' || request.question.trim().length === 0) {
    throw new RagFailure('INVALID_INPUT');
  }
  const scope = request.scope;
  if (!isRecord(scope)) throw new RagFailure('INVALID_INPUT');
  const isNoteScope = scope.type === 'note' && isValidIdentifier(scope.noteId);
  if (scope.type !== 'account' && !isNoteScope) throw new RagFailure('INVALID_INPUT');
};

/** The approved scope: own, synced, available, unprotected and not an incoming shared copy. */
export const isEligibleNote = (note: unknown, actor: string): note is CanonicalNote =>
  isRecord(note) &&
  note.ownerId === actor &&
  note.synced === true &&
  note.protected === false &&
  note.deleted === false &&
  note.available === true &&
  note.incomingShared !== true &&
  isSafeInteger(note.revision) &&
  note.revision >= 1 &&
  isValidIdentifier(note.noteId) &&
  typeof note.title === 'string' &&
  isValidUnicode(note.title) &&
  typeof note.content === 'string' &&
  isValidUnicode(note.content);

/** Actor match first, then session, consent and index coherence before any note is trusted. */
const validateState = (value: unknown, actor: string): CanonicalState => {
  if (!isRecord(value)) throw new RagFailure('PROVIDER_UNAVAILABLE');
  if (!isValidIdentifier(value['actorId']) || value['actorId'] !== actor) throw new RagFailure('UNAUTHORIZED');
  if (!isSafeInteger(value['sessionGeneration']) || (value['sessionGeneration'] as number) < 0) {
    throw new RagFailure('SOURCE_CHANGED');
  }
  const consent = value['consent'];
  if (!isRecord(consent) || consent['accepted'] !== true) throw new RagFailure('CONSENT_REQUIRED');
  if (consent['version'] !== CONSENT_VERSION) throw new RagFailure('CONSENT_REQUIRED');
  if (!isSafeInteger(consent['generation']) || (consent['generation'] as number) < 0) {
    throw new RagFailure('CONSENT_REQUIRED');
  }
  if (value['indexReady'] !== true || !isValidIdentifier(value['manifestVersion'])) {
    throw new RagFailure('INDEX_NOT_READY');
  }
  if (!Array.isArray(value['notes'])) throw new RagFailure('PROVIDER_UNAVAILABLE');
  return value as unknown as CanonicalState;
};

const readState = async (store: AuthorityStore, actor: string, signal: AbortSignal): Promise<unknown> => {
  if (!isRecord(store) || typeof store.read !== 'function') throw new RagFailure('PROVIDER_UNAVAILABLE');
  let state: unknown;
  try {
    state = await store.read(actor, signal);
  } catch (error) {
    if (signal.aborted || (error instanceof RagFailure && error.code === 'TIMEOUT')) {
      throw new RagFailure('TIMEOUT');
    }
    throw new RagFailure('PROVIDER_UNAVAILABLE');
  }
  assertLive(signal);
  return state;
};

const freezeSnapshot = (state: CanonicalState): CanonicalState => {
  try {
    return deepFreeze(structuredClone(state));
  } catch {
    throw new RagFailure('PROVIDER_UNAVAILABLE');
  }
};

/** A direct caller must not be able to change the scope the context was authorized for. */
const freezeRequest = (request: RagRequest): RagRequest => {
  try {
    return deepFreeze(structuredClone(request));
  } catch {
    throw new RagFailure('INVALID_INPUT');
  }
};

const scopeNotes = (request: RagRequest, notes: readonly CanonicalNote[]): readonly CanonicalNote[] => {
  const scope = request.scope;
  if (scope.type === 'account') return Object.freeze([...notes]);
  const matching = notes.filter((note) => note.noteId === scope.noteId);
  if (matching.length === 0) throw new RagFailure('SCOPE_DENIED');
  return Object.freeze(matching);
};

const sameNote = (current: CanonicalNote, captured: CanonicalNote): boolean =>
  current.revision === captured.revision &&
  current.title === captured.title &&
  current.content === captured.content &&
  current.synced === captured.synced &&
  current.protected === captured.protected &&
  current.deleted === captured.deleted &&
  current.available === captured.available &&
  (current.incomingShared === true) === (captured.incomingShared === true);

/**
 * Authorizes the actor against the canonical store and freezes the scoped snapshot.
 * Note scope is refused when no eligible own note matches; account scope simply excludes
 * ineligible notes (foreign, unsynced, protected, deleted, unavailable, incoming shared).
 */
export async function beginContext(
  actor: string,
  request: RagRequest,
  store: AuthorityStore,
  signal: AbortSignal,
): Promise<RequestContext> {
  if (!isValidIdentifier(actor)) throw new RagFailure('UNAUTHORIZED');
  assertRequest(request);
  assertLive(signal);
  const boundRequest = freezeRequest(request);
  const snapshot = freezeSnapshot(validateState(await readState(store, actor, signal), actor));
  const notes = Object.freeze(snapshot.notes.filter((note) => isEligibleNote(note, actor)));
  const scoped = scopeNotes(boundRequest, notes);
  // The provider-facing snapshot carries only the authorized scoped notes.
  const state = deepFreeze({ ...snapshot, notes: scoped });

  const revalidate = async (): Promise<void> => {
    assertLive(signal);
    const latest = validateState(await readState(store, actor, signal), actor);
    if (latest.sessionGeneration !== snapshot.sessionGeneration) throw new RagFailure('SOURCE_CHANGED');
    if (
      latest.consent.accepted !== true ||
      latest.consent.version !== snapshot.consent.version ||
      latest.consent.generation !== snapshot.consent.generation
    ) {
      throw new RagFailure('CONSENT_REQUIRED');
    }
    if (latest.indexReady !== true || latest.manifestVersion !== snapshot.manifestVersion) {
      throw new RagFailure('INDEX_NOT_READY');
    }
    for (const captured of scoped) {
      const current = latest.notes.find(
        (note) => isRecord(note) && note.ownerId === actor && note.noteId === captured.noteId,
      );
      if (current === undefined || !sameNote(current as CanonicalNote, captured)) {
        throw new RagFailure('SOURCE_CHANGED');
      }
    }
  };

  return Object.freeze({ actor, request: boundRequest, state, notes: scoped, signal, revalidate });
}

const bisectsSurrogate = (text: string, offset: number): boolean =>
  offset > 0 &&
  offset < text.length &&
  /[\uD800-\uDBFF]/.test(text[offset - 1] as string) &&
  /[\uDC00-\uDFFF]/.test(text[offset] as string);

/**
 * Checks one candidate chunk against the frozen context: exact own note, request scope,
 * canonical revision/title and an exact non-empty, surrogate-safe span slice.
 */
export function assertChunkAuthority(chunk: Chunk, context: RequestContext): void {
  assertChunk(chunk);
  if (chunk.ownerId !== context.actor) throw new RagFailure('SCOPE_DENIED');
  if (context.request.scope.type === 'note' && chunk.noteId !== context.request.scope.noteId) {
    throw new RagFailure('SCOPE_DENIED');
  }
  const note = context.notes.find((candidate) => candidate.noteId === chunk.noteId);
  if (note === undefined) throw new RagFailure('SCOPE_DENIED');
  if (chunk.sectionId !== SECTION_BODY) throw new RagFailure('SOURCE_CHANGED');
  if (chunk.revision !== note.revision || chunk.title !== note.title) throw new RagFailure('SOURCE_CHANGED');
  // A span past the current content is a stale index artifact; an empty or malformed span is
  // already refused structurally by assertChunk.
  if (chunk.endOffset > note.content.length) throw new RagFailure('SOURCE_CHANGED');
  if (bisectsSurrogate(note.content, chunk.startOffset) || bisectsSurrogate(note.content, chunk.endOffset)) {
    throw new RagFailure('SOURCE_CHANGED');
  }
  if (note.content.slice(chunk.startOffset, chunk.endOffset) !== chunk.text) {
    throw new RagFailure('SOURCE_CHANGED');
  }
}
