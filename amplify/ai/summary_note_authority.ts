import { randomUUID } from 'node:crypto';
import { stableDigest } from '../sync/cursor';
import { aclCondition } from '../sharing/dynamo_note_acl';
import { GetCommand, PutCommand, TransactWriteCommand, type DynamoDBDocumentClient,
  type TransactWriteCommandInput } from '@aws-sdk/lib-dynamodb';
import { SummaryFailure, type SummaryRequest } from './summary_contract';
import type { SummaryNoteContext } from './summary_note_context';
import { NoteSecurityError } from '../protection/protection_store';
import type { NoteSecurityAuthority, ProtectionStore, SecurityAuthorization } from '../protection/protection_store';

type Run = {
  actor: string; context: SummaryNoteContext; version: number; sourceEnd: number;
  outputs: string[]; expiresAt: number; working: boolean; done: boolean; nonce: string;
};
export type SummaryStageAuthority = Readonly<{
  revalidate(): Promise<void>;
  complete(output: string): Promise<void>;
}>;
export interface SummaryNoteAuthority {
  begin(request: SummaryRequest, actor: string, grant?: string): Promise<SummaryStageAuthority>;
}
const changed = (): never => { throw new SummaryFailure('noteChanged', 'Note lineage changed'); };
const key = (owner: string, sort: string) => ({ ownerId: `OWNER#${owner}`, noteId: sort });
const options = () => ({ abortSignal: AbortSignal.timeout(3000) });
const sameContext = (a: SummaryNoteContext, b: SummaryNoteContext) =>
  a.ownerId === b.ownerId && a.noteId === b.noteId && a.runId === b.runId &&
  a.contentRevision === b.contentRevision && a.protectionRevision === b.protectionRevision && a.accessRevision === b.accessRevision;
const runKey = (c: SummaryNoteContext, actor: string) => key(actor === c.ownerId ? c.ownerId : actor,
  `SUMMARY#${actor === c.ownerId ? c.runId : stableDigest(JSON.stringify([c.ownerId, c.noteId, c.runId]))}`);

/** Canonical input, contiguous section lineage and current authority on every stage. */
export class DynamoSummaryNoteAuthority implements SummaryNoteAuthority {
  constructor(private readonly table: string, private readonly db: DynamoDBDocumentClient,
    private readonly store: ProtectionStore, private readonly security: NoteSecurityAuthority,
    private readonly now: () => number = Date.now) {}

  private async canonical(context: SummaryNoteContext, actor: string, grant?: string) {
    try {
      const authority = await this.security.authorize(actor, context.ownerId,
        context.noteId, 'summary', grant);
      if (actor !== context.ownerId && authority.access?.accessRevision !== context.accessRevision) return changed();
      const note = await this.store.readNote(context.ownerId, context.noteId);
      if (!note || note.deletedAt || note.revision !== context.contentRevision ||
          authority.revision !== context.protectionRevision ||
          (note.protected ?? false) !== authority.enabled ||
          (note.protectionRevision ?? 0) !== authority.revision) return changed();
      return { text: note.content.trim(), authority };
    } catch (error) {
      if (error instanceof SummaryFailure) throw error;
      if (error instanceof NoteSecurityError && error.code !== 'unavailable') {
        throw new SummaryFailure(error.code === 'staleRevision' ? 'noteChanged' : 'noteLocked',
          'Note authorization refused');
      }
      throw new SummaryFailure('unexpected', 'Note authority unavailable');
    }
  }

  async begin(request: SummaryRequest, actor: string, grant?: string): Promise<SummaryStageAuthority> {
    const context = request.note;
    if (!context) throw new SummaryFailure('invalidInput', 'Note context required');
    const canonical = await this.canonical(context, actor, grant);
    const rowKey = runKey(context, actor);
    const stored = (await this.db.send(new GetCommand({ TableName: this.table,
      Key: rowKey, ConsistentRead: true }), options())).Item;
    const previous = stored as Run | undefined;
    const run: Run = previous ?? { actor, context, version: 0, sourceEnd: 0,
      outputs: [], expiresAt: this.now() + 180_000, working: false, done: false, nonce: '' };
    this.requireRun(run, context, actor);
    const sourceEnd = this.requireInput(request, canonical.text, run);
    const reserved = { ...run, working: true, nonce: randomUUID(), sourceEnd };
    try {
      await this.db.send(new PutCommand({ TableName: this.table,
        Item: { ...rowKey, ...reserved, ttl: Math.floor(run.expiresAt / 1000) },
        ConditionExpression: previous ? 'version = :v AND working = :f AND done = :f AND expiresAt > :now'
          : 'attribute_not_exists(noteId)',
        ...(previous ? { ExpressionAttributeValues: { ':v': run.version, ':f': false, ':now': this.now() } } : {}) }), options());
    } catch { return changed(); }
    const revalidate = async () => {
      if (reserved.expiresAt <= this.now()) return changed();
      await this.canonical(context, actor, grant);
    };
    return { revalidate, complete: async (output) => {
      if (reserved.expiresAt <= this.now()) return changed();
      const current = await this.canonical(context, actor, grant);
      await this.complete(request, reserved, current.authority, output);
    } };
  }

  private requireRun(run: Run, context: SummaryNoteContext, actor: string) {
    if (run.actor !== actor || !sameContext(run.context, context) ||
        !Number.isSafeInteger(run.version) || run.version !== context.sectionIndex ||
        !Number.isSafeInteger(run.sourceEnd) || !Array.isArray(run.outputs) ||
        run.outputs.length !== run.version || run.outputs.some(o => typeof o !== 'string') ||
        run.working || run.done || run.expiresAt <= this.now()) return changed();
  }

  private requireInput(request: SummaryRequest, text: string, run: Run): number {
    const context = request.note!;
    if (request.stage === 'direct') {
      if (run.version !== 0 || context.sourceStart !== null || context.sourceEnd !== null ||
          request.inputs[0] !== text) return changed();
      return text.length;
    }
    if (request.stage === 'merge') {
      if (context.sourceStart !== null || context.sourceEnd !== null || run.outputs.length < 2 ||
          run.outputs.length > 4 || text.slice(run.sourceEnd).trim() ||
          request.inputs.length !== run.outputs.length ||
          request.inputs.some((v, i) => v !== run.outputs[i])) return changed();
      return run.sourceEnd;
    }
    const { sourceStart: start, sourceEnd: end } = context;
    if (run.version >= 4 || start === null || end === null || start < run.sourceEnd ||
        end <= start || end > text.length || text.slice(run.sourceEnd, start).trim() ||
        text.slice(start, end).trim() !== request.inputs[0]) return changed();
    // UTF-16 offsets must never bisect a surrogate pair.
    for (const offset of [start, end]) {
      if (offset > 0 && offset < text.length && /[\uD800-\uDBFF]/.test(text[offset - 1]) &&
          /[\uDC00-\uDFFF]/.test(text[offset])) return changed();
    }
    return end;
  }

  private async complete(request: SummaryRequest, run: Run, authority: SecurityAuthorization, output: string) {
    const c = request.note!;
    const next = { ...run, working: false, done: request.stage !== 'section',
      version: run.version + 1, outputs: request.stage === 'section' ? [...run.outputs, output.trim()] : run.outputs };
    const writes: TransactWriteCommandInput['TransactItems'] = [
      { Put: { TableName: this.table, Item: { ...runKey(c, authority.actorId), ...next,
        ttl: Math.floor(run.expiresAt / 1000) }, ConditionExpression: 'nonce = :nonce AND working = :t AND expiresAt > :now',
        ExpressionAttributeValues: { ':nonce': run.nonce, ':t': true, ':now': this.now() } } },
      { ConditionCheck: { TableName: this.table, Key: key(c.ownerId, `NOTE#${c.noteId}`),
        ConditionExpression: 'revision = :r AND deletedAt = :nil',
        ExpressionAttributeValues: { ':r': c.contentRevision, ':nil': null } } },
      { ConditionCheck: { TableName: this.table, Key: key(c.ownerId, `PROTECTION#${c.noteId}`),
        ConditionExpression: c.protectionRevision === 0 ? 'attribute_not_exists(noteId)' : 'revision = :r AND enabled = :enabled',
        ...(c.protectionRevision === 0 ? {} : { ExpressionAttributeValues: { ':r': c.protectionRevision, ':enabled': authority.enabled } }) } },
    ];
    writes.push(...aclCondition(this.table, authority));
    if (authority.enabled) writes.push({ ConditionCheck: { TableName: this.table,
      Key: key(c.ownerId, `GRANT#${authority.grantHash}`),
      ConditionExpression: 'expiresAt > :now AND actorId = :a AND revision = :r AND targetNoteId = :n AND contains(operations, :op)',
      ExpressionAttributeValues: { ':now': this.now(), ':a': authority.actorId,
        ':r': c.protectionRevision, ':n': c.noteId, ':op': 'summary' } } });
    try { await this.db.send(new TransactWriteCommand({ TransactItems: writes }), options()); }
    catch { return changed(); }
  }
}
