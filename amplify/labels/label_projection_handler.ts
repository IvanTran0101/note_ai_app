import type { DynamoDBDocumentClient } from '@aws-sdk/lib-dynamodb';
import { GetCommand } from '@aws-sdk/lib-dynamodb';
import { DynamoNoteAcl } from '../sharing/dynamo_note_acl';
import { recipientProjection } from '../sharing/feed_projection';
import { itemKey, ownerKeyOf, toNoteSnapshot } from '../sync/sync_store_codec';
import { SyncInvalidMutationError } from '../sync/sync_store_models';
import { jsonResponse, noteBodyOf } from '../sync/sync_response';
import type { NoteSnapshot } from '../sync/sync_store_models';
import type { ProtectionMetadata } from '../protection/protection_store';
import type { NoteSecurityAuthority } from '../protection/protection_store';
import { NoteSecurityError } from '../protection/protection_store';
import { labelId } from './label_models';
import { projectNoteLabels } from './note_label_projection';

type ProjectionRef = Readonly<{ownerId: string; noteId: string; grant?: string}>;
type ProjectionContext = Readonly<{actor: string; table: string;
  db: DynamoDBDocumentClient; acl: DynamoNoteAcl; security: NoteSecurityAuthority}>;

function projectionRefs(raw: unknown): ProjectionRef[] {
  const body = raw as {wireVersion?: unknown; notes?: unknown};
  if (body?.wireVersion !== 2 || !Array.isArray(body.notes) || body.notes.length > 50) {
    throw new SyncInvalidMutationError('PAYLOAD_INVALID', 'Scoped projection request required.');
  }
  return body.notes.map(value => {
    const ref = value as {ownerId?: unknown; noteId?: unknown; grant?: unknown};
    if (ref?.grant !== undefined && (typeof ref.grant !== 'string' || ref.grant.length > 4096)) {
      throw new SyncInvalidMutationError('PAYLOAD_INVALID', 'Invalid read authority.');
    }
    return {ownerId: labelId(ref?.ownerId), noteId: labelId(ref?.noteId),
      ...(ref.grant === undefined ? {} : {grant: ref.grant as string})};
  });
}

/** Bounded scoped refresh; a rename never rewrites Note content or revision. */
export async function labelProjectionResponse(actor: string, raw: unknown,
    table: string, db: DynamoDBDocumentClient, security: NoteSecurityAuthority) {
  const context = {actor, table, db, security, acl: new DynamoNoteAcl(table, db)};
  const items = [];
  for (const ref of projectionRefs(raw)) {
    const note = await scopedProjection(context, ref);
    if (note) items.push({entityType: 'note', note});
  }
  return jsonResponse(200, {wireVersion: 2, items, hasMore: false});
}

async function scopedProjection(c: ProjectionContext, ref: ProjectionRef) {
  const {actor, db, table, acl, security} = c, owner = ref.ownerId, id = ref.noteId;
  const initialShare = actor === owner ? null : await acl.read(actor, owner, id);
  if (actor !== owner && !initialShare) throw new NoteSecurityError('denied');
  const result = await db.send(new GetCommand({TableName: table,
    Key: itemKey(ownerKeyOf(owner), `NOTE#${id}`), ConsistentRead: true}));
  if (!result.Item) return null;
  const canonical = toNoteSnapshot(result.Item);
  if (initialShare?.status === 'revoked') {
    return noteBodyOf({...canonical, ownerId: owner, share: initialShare,
      contentAvailable: false}, false, true);
  }
  const before = await security.metadata(actor, owner, id);
  let note = actor === owner ? canonical :
    await recipientProjection(actor, owner, canonical, acl, security);
  let readable = actor === owner ? !before.enabled : note.contentAvailable !== false;
  if (before.enabled && note.share?.status !== 'revoked') {
    try { await security.authorize(actor, owner, id, 'read', ref.grant); readable = true; }
    catch (error) {
      if (!(error instanceof NoteSecurityError)) throw error;
      readable = false;
    }
  }
  note = {...note, ...(readable ? {title: canonical.title, content: canonical.content,
    labelIds: canonical.labelIds} : {}),
    contentAvailable: readable};
  note = await projectNoteLabels(db, table, owner, note, actor !== owner);
  return finalProjection(c, ref, before, note, readable);
}

async function finalProjection(c: ProjectionContext, ref: ProjectionRef,
    before: ProtectionMetadata, note: NoteSnapshot, readable: boolean) {
  const {actor, acl, security} = c, owner = ref.ownerId, id = ref.noteId;
  let after: ProtectionMetadata;
  try { after = await security.metadata(actor, owner, id); }
  catch (error) {
    const live = actor === owner ? null : await acl.read(actor, owner, id);
    if (error instanceof NoteSecurityError && live?.status === 'revoked') {
      return noteBodyOf({...note, ownerId: owner, share: live,
        contentAvailable: false}, false, true);
    }
    throw error;
  }
  if (after.revision !== before.revision || after.enabled !== before.enabled) readable = false;
  if (actor !== owner) {
    const share = await acl.read(actor, owner, id);
    if (!share || share.status !== 'active' || share.accessRevision !== note.share?.accessRevision) readable = false;
    if (share) note = {...note, share};
  }
  if (readable && after.enabled) await security.authorize(actor, owner, id, 'read', ref.grant);
  return noteBodyOf({...note, protected: after.enabled, protectionRevision: after.revision,
    contentAvailable: readable}, readable, true);
}
