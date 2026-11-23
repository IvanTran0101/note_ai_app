// Immutable canonical evidence; remove expansion before anchors when the budget is exceeded.
import {
  policy,
  RagFailure,
  type CanonicalNote,
  type Chunk,
  type Counter,
  type Evidence,
  type Source,
} from './types';
import { assertChunk, countTokens, isSafeInteger, SECTION_BODY } from './chunking';

export const EVIDENCE_MAX_TOKENS: number = policy.context.evidenceMaxTokens;
export const PREVIOUS_CHUNKS: number = policy.context.previousChunks;
export const NEXT_CHUNKS: number = policy.context.nextChunks;
export const CONTEXT_RECURSIVE: boolean = policy.context.recursive;
export const EVIDENCE_DEDUPE: string = policy.context.dedupe;
export const EVIDENCE_INCLUDES_TITLE_AND_LABELS: boolean = policy.context.includesTitleAndSourceLabels;
export const EVIDENCE_ANCHORS_FIRST: boolean = policy.context.anchorsFirst;
export const EVIDENCE_REMOVE_EXPANSION_FIRST: boolean = policy.context.removeExpansionFirst;
/** Serialized evidence shape: `[<sourceId>] <title>\n<quote>`, sources joined by a blank line. */
export const EVIDENCE_SERIALIZATION = 'label-title-newline-quote' as const;

const emptyEvidence = (): Evidence => Object.freeze({ sources: Object.freeze([] as Source[]), text: '' });

const assertNote = (note: CanonicalNote): void => {
  if (note === null || typeof note !== 'object') throw new RagFailure('INVALID_INPUT');
  if (typeof note.ownerId !== 'string' || note.ownerId.trim().length === 0) throw new RagFailure('INVALID_INPUT');
  if (typeof note.noteId !== 'string' || note.noteId.trim().length === 0) throw new RagFailure('INVALID_INPUT');
  if (!isSafeInteger(note.revision) || note.revision < 0) throw new RagFailure('INVALID_INPUT');
  if (typeof note.title !== 'string' || typeof note.content !== 'string') throw new RagFailure('INVALID_INPUT');
  if (
    typeof note.synced !== 'boolean' ||
    typeof note.protected !== 'boolean' ||
    typeof note.deleted !== 'boolean' ||
    typeof note.available !== 'boolean'
  ) {
    throw new RagFailure('INVALID_INPUT');
  }
  if (note.incomingShared !== undefined && typeof note.incomingShared !== 'boolean') {
    throw new RagFailure('INVALID_INPUT');
  }
};

/**
 * Canonical own-note validation for one chunk span. Never trusts the index artifact: the span
 * must still be the exact slice of the current canonical content.
 */
const resolveCanonical = (chunk: Chunk, notes: readonly CanonicalNote[]): CanonicalNote => {
  // Text-only notes have exactly one section; a chunk claiming another one cannot be validated.
  if (chunk.sectionId !== SECTION_BODY) throw new RagFailure('SOURCE_CHANGED');

  let canonical: CanonicalNote | undefined;
  let sameOwnerOtherRevision = false;
  for (const note of notes) {
    if (note.noteId !== chunk.noteId) continue;
    if (note.ownerId !== chunk.ownerId) continue; // foreign projection: resolved below
    if (note.revision !== chunk.revision) {
      sameOwnerOtherRevision = true;
      continue;
    }
    canonical = note;
    break;
  }
  if (canonical === undefined) {
    // Stale revision of our own note is a changed source; a foreign owner or a note outside the
    // canonical set hides existence behind SCOPE_DENIED.
    throw new RagFailure(sameOwnerOtherRevision ? 'SOURCE_CHANGED' : 'SCOPE_DENIED');
  }

  if (canonical.incomingShared === true) throw new RagFailure('SCOPE_DENIED');
  if (!canonical.synced || canonical.protected || canonical.deleted || !canonical.available) {
    throw new RagFailure('SOURCE_CHANGED');
  }
  if (canonical.title !== chunk.title) throw new RagFailure('SOURCE_CHANGED');
  if (chunk.endOffset > canonical.content.length) throw new RagFailure('SOURCE_CHANGED');
  if (canonical.content.slice(chunk.startOffset, chunk.endOffset) !== chunk.text) {
    throw new RagFailure('SOURCE_CHANGED');
  }
  return canonical;
};

type Admission = Readonly<{ chunk: Chunk; note: CanonicalNote; priority: number; expansion: boolean }>;

type Passage = {
  note: CanonicalNote;
  start: number;
  end: number;
  priority: number;
  expansion: boolean;
  tieKey: string;
};

const identityKeyOf = (chunk: Chunk): string =>
  JSON.stringify([chunk.ownerId, chunk.noteId, chunk.revision, chunk.sectionId, chunk.chunkId]);

const groupKeyOf = (chunk: Chunk): string =>
  JSON.stringify([chunk.ownerId, chunk.noteId, chunk.revision, chunk.sectionId]);

/** Same identity must also carry the same span/text/title/ordinal (no silent corruption). */
const sameChunkSpan = (left: Chunk, right: Chunk): boolean =>
  left.ordinal === right.ordinal &&
  left.title === right.title &&
  left.startOffset === right.startOffset &&
  left.endOffset === right.endOffset &&
  left.text === right.text;

const tieKeyOf = (chunk: Chunk, start: number, end: number): string =>
  JSON.stringify([chunk.ownerId, chunk.noteId, chunk.revision, chunk.sectionId, start, end]);

/** Merge overlapping/contiguous ranges of one source identity; keep distinct sources apart. */
const mergePassages = (admissions: readonly Admission[]): Passage[] => {
  const groups = new Map<string, Admission[]>();
  for (const admission of admissions) {
    const key = groupKeyOf(admission.chunk);
    const group = groups.get(key);
    if (group === undefined) groups.set(key, [admission]);
    else group.push(admission);
  }

  const passages: Passage[] = [];
  for (const group of groups.values()) {
    group.sort(
      (left, right) =>
        left.chunk.startOffset - right.chunk.startOffset || left.chunk.endOffset - right.chunk.endOffset,
    );
    let current: Passage | null = null;
    for (const admission of group) {
      const { chunk, note, priority, expansion } = admission;
      if (current !== null && chunk.startOffset <= current.end) {
        current.end = Math.max(current.end, chunk.endOffset);
        current.priority = Math.min(current.priority, priority);
        current.expansion = current.expansion && expansion;
        current.tieKey = tieKeyOf(chunk, current.start, current.end);
        continue;
      }
      current = {
        note,
        start: chunk.startOffset,
        end: chunk.endOffset,
        priority,
        expansion,
        tieKey: tieKeyOf(chunk, chunk.startOffset, chunk.endOffset),
      };
      passages.push(current);
    }
  }

  // Passage priority is the best contained anchor; expansions follow their parent anchor.
  passages.sort(
    (left, right) =>
      left.priority - right.priority ||
      Number(left.expansion) - Number(right.expansion) ||
      (left.tieKey < right.tieKey ? -1 : left.tieKey > right.tieKey ? 1 : 0),
  );
  return passages;
};

const renderEvidence = (passages: readonly Passage[]): Evidence => {
  const sources = passages.map((passage, index): Source => {
    const quote = passage.note.content.slice(passage.start, passage.end);
    return Object.freeze({
      sourceId: `S${index + 1}`,
      noteId: passage.note.noteId,
      revision: passage.note.revision,
      title: passage.note.title,
      startOffset: passage.start,
      endOffset: passage.end,
      quote,
    });
  });
  const text = sources.map((source) => `[${source.sourceId}] ${source.title}\n${source.quote}`).join('\n\n');
  return Object.freeze({ sources: Object.freeze(sources), text });
};

/**
 * Builds the immutable evidence bundle for the MMR anchors plus caller-fetched neighbors.
 * `counter` is the injected evidence token port (mock/preflight); invalid counter values fail
 * closed with EVIDENCE_VALIDATION_UNAVAILABLE.
 */
export function buildEvidence(
  anchors: readonly Chunk[],
  neighbors: readonly Chunk[],
  notes: readonly CanonicalNote[],
  counter: Counter,
): Evidence {
  if (!Array.isArray(anchors) || !Array.isArray(neighbors) || !Array.isArray(notes)) {
    throw new RagFailure('INVALID_INPUT');
  }
  for (const note of notes) assertNote(note);
  if (anchors.length === 0) return emptyEvidence();

  assertChunk(anchors[0]);
  // Anchors come from the already scoped retrieval result: they must all belong to one owner.
  const expectedOwner = anchors[0].ownerId;
  const anchorAdmissions: Admission[] = [];
  const anchorByKey = new Map<string, Admission>();
  for (const anchor of anchors) {
    assertChunk(anchor);
    if (anchor.ownerId !== expectedOwner) throw new RagFailure('SCOPE_DENIED');
    const note = resolveCanonical(anchor, notes);
    const key = identityKeyOf(anchor);
    const existing = anchorByKey.get(key);
    if (existing !== undefined) {
      // Exact duplicate of the same source: keep the higher-priority admission.
      if (!sameChunkSpan(existing.chunk, anchor)) throw new RagFailure('SOURCE_CHANGED');
      continue;
    }
    const admission: Admission = { chunk: anchor, note, priority: anchorAdmissions.length, expansion: false };
    anchorByKey.set(key, admission);
    anchorAdmissions.push(admission);
  }

  // Expansions: immediate +/-1 ordinal neighbor of an anchor, same owner/note/revision/section,
  // canonical and current. Never recursive, never taken from another anchor's chain.
  const expansionByKey = new Map<string, Admission>();
  for (const neighbor of neighbors) {
    assertChunk(neighbor);
    const key = identityKeyOf(neighbor);
    const anchor = anchorByKey.get(key);
    if (anchor) {
      if (!sameChunkSpan(anchor.chunk, neighbor)) throw new RagFailure('SOURCE_CHANGED');
      continue;
    }
    if (neighbor.ownerId !== expectedOwner) throw new RagFailure('SCOPE_DENIED');
    // Every supplied span is validated against the canonical note before anything else.
    const note = resolveCanonical(neighbor, notes);
    let parent = -1;
    for (const anchor of anchorAdmissions) {
      if (
        anchor.chunk.ownerId === neighbor.ownerId &&
        anchor.chunk.noteId === neighbor.noteId &&
        anchor.chunk.revision === neighbor.revision &&
        anchor.chunk.sectionId === neighbor.sectionId &&
        Math.abs(anchor.chunk.ordinal - neighbor.ordinal) === 1
      ) {
        parent = anchor.priority;
        break;
      }
    }
    if (parent < 0) {
      // Not an immediate neighbor of any anchor: the caller exceeded +/-1 or returned a stray.
      throw new RagFailure('INVALID_INPUT');
    }
    const existing = expansionByKey.get(key);
    if (existing !== undefined) {
      if (!sameChunkSpan(existing.chunk, neighbor)) throw new RagFailure('SOURCE_CHANGED');
      continue;
    }
    expansionByKey.set(key, { chunk: neighbor, note, priority: parent, expansion: true });
  }
  const expansions = [...expansionByKey.values()].sort(
    (left, right) =>
      left.priority - right.priority ||
      (tieKeyOf(left.chunk, left.chunk.startOffset, left.chunk.endOffset) <
      tieKeyOf(right.chunk, right.chunk.startOffset, right.chunk.endOffset)
        ? -1
        : 1),
  );

  let keptAnchors = anchorAdmissions.length;
  let keptExpansions = expansions.length;
  for (;;) {
    const kept = [
      ...anchorAdmissions.filter((entry) => entry.priority < keptAnchors),
      ...expansions.slice(0, keptExpansions),
    ];
    const evidence = renderEvidence(mergePassages(kept));
    if (countTokens(counter, evidence.text) <= EVIDENCE_MAX_TOKENS) return evidence;
    // Over budget: drop expansions first (lowest priority first), then the lowest anchor.
    if (keptExpansions > 0) {
      keptExpansions -= 1;
      continue;
    }
    if (keptAnchors > 0) {
      keptAnchors -= 1;
      continue;
    }
    // Even the empty serialization is over budget: the counter port is not trustworthy.
    throw new RagFailure('EVIDENCE_VALIDATION_UNAVAILABLE');
  }
}
