/**
 * Profile/avatar application service (M01.1 backend).
 *
 * Owns the state machine: canonical profile row, avatar intents (staging
 * capability -> verified bytes -> immutable final object -> transactional
 * association) and the idempotent retry records that make a lost ACK safe.
 * `store.ts` owns persistence, `avatar_objects.ts` owns S3, `contract.ts` owns
 * the wire shape; this file only sequences them.
 */
import { createHash, randomUUID } from 'node:crypto';
import type { DynamoDBDocumentClient } from '@aws-sdk/lib-dynamodb';
import { S3AvatarObjects, type AvatarObjects, type PinnedObject } from './avatar_objects';
import {
  avatarIntentOf,
  inspectImage,
  MAX_AVATAR_BYTES,
  ProfileError,
  profileWriteOf,
  type AvatarMime,
  type ProfileDTO,
} from './contract';
import {
  intentSortKey,
  PROFILE_SORT_KEY,
  ProfileStore,
  requestSortKey,
  ttlFrom,
  type AvatarRecord,
  type IntentRow,
  type ProfileRow,
  type RequestRow,
} from './store';

const INTENT_TTL_SECONDS = 3600;
const REQUEST_TTL_SECONDS = 24 * 3600;
const INTENT_ID = /^[a-f0-9]{32}$/;
const OWNER_ID = /^[A-Za-z0-9_-]{1,128}$/;

export type AvatarIntent = Readonly<{ intentId: string; uploadUrl: string; headers: Record<string, string> }>;
export type AvatarBinary = Readonly<{ bytes: Buffer; mime: AvatarMime; version: string }>;

export interface ProfileService {
  getProfile(actor: string): Promise<ProfileDTO>;
  writeProfile(actor: string, body: unknown): Promise<ProfileDTO>;
  createAvatarIntent(actor: string, body: unknown): Promise<AvatarIntent>;
  completeAvatarIntent(actor: string, intentId: string): Promise<ProfileDTO>;
  readAvatar(actor: string): Promise<AvatarBinary>;
}

const dtoOf = (row: ProfileRow): ProfileDTO => ({
  userId: row.ownerId,
  displayName: row.displayName,
  avatarReference: row.avatarReference,
  revision: row.revision,
  updatedAt: row.updatedAt,
});

const fingerprintOf = (value: unknown) => createHash('sha256').update(JSON.stringify(value)).digest('hex');

const referenceOf = (avatarId: string) => `av_${avatarId}`;

export class ProfileServiceImpl implements ProfileService {
  private readonly store: ProfileStore;

  constructor(
    readonly documentClient: DynamoDBDocumentClient,
    readonly tableName: string,
    readonly objects: AvatarObjects,
    readonly now: () => number = Date.now,
    readonly newId: () => string = () => randomUUID().replace(/-/g, ''),
  ) {
    this.store = new ProfileStore(tableName, documentClient);
  }

  async getProfile(actor: string): Promise<ProfileDTO> {
    const owner = this.owner(actor);
    const row = await this.store.getProfile(owner);
    if (!row) throw new ProfileError('PROFILE_MISSING');
    return dtoOf(row);
  }

  async writeProfile(actor: string, body: unknown): Promise<ProfileDTO> {
    const owner = this.owner(actor);
    const write = profileWriteOf(body, actor);
    // Same requestId means the same action: replay its outcome verbatim instead
    // of writing again, so a lost ACK never resets an existing profile/avatar.
    const fingerprint = fingerprintOf(write);
    const prior = await this.store.getRequest(owner, write.requestId);
    if (prior && prior.ttl * 1000 > this.now()) {
      if (prior.kind !== 'profile' || prior.fingerprint !== fingerprint || !prior.profile) throw new ProfileError('PROFILE_INVALID');
      return prior.profile;
    }
    const current = await this.store.getProfile(owner);
    const currentRevision = current?.revision ?? 0;
    if (write.expectedRevision !== currentRevision) throw new ProfileError('PROFILE_CONFLICT');
    const avatar = this.avatarForWrite(write.avatarReference, current);
    const revision = currentRevision + 1;
    const timestamp = new Date(this.now()).toISOString();
    const row: ProfileRow = {
      ownerId: owner, noteId: PROFILE_SORT_KEY, entityType: 'PROFILE',
      displayName: write.displayName,
      avatarReference: avatar ? referenceOf(avatar.avatarId) : null,
      avatar, revision, updatedAt: timestamp,
    };
    const request: RequestRow = {
      ownerId: owner, noteId: requestSortKey(write.requestId), entityType: 'PROFILE_REQUEST',
      requestId: write.requestId, fingerprint, kind: 'profile', profile: dtoOf(row),
      createdAt: timestamp, ttl: ttlFrom(this.now(), REQUEST_TTL_SECONDS),
    };
    const outcome = await this.store.saveProfile(row, write.expectedRevision, request);
    if (outcome === 'conflict') throw new ProfileError('PROFILE_CONFLICT');
    if (outcome === 'retry') {
      const raced = await this.store.getRequest(owner, write.requestId);
      if (raced?.kind === 'profile' && raced.fingerprint === fingerprint && raced.profile) return raced.profile;
      throw new ProfileError('PROFILE_UNAVAILABLE', true);
    }
    return dtoOf(row);
  }

  async createAvatarIntent(actor: string, body: unknown): Promise<AvatarIntent> {
    const owner = this.owner(actor);
    const request = avatarIntentOf(body);
    const fingerprint = fingerprintOf(request);
    const prior = await this.store.getRequest(owner, request.requestId);
    if (prior && prior.ttl * 1000 > this.now()) {
      if (prior.kind !== 'intent' || prior.fingerprint !== fingerprint || !prior.intentId) throw new ProfileError('PROFILE_INVALID');
      return this.intentResponse(owner, prior.intentId);
    }
    const profile = await this.store.getProfile(owner);
    if (!profile) throw new ProfileError('PROFILE_MISSING');
    if (profile.revision !== request.expectedProfileRevision) throw new ProfileError('PROFILE_CONFLICT');
    const intentId = this.newId();
    if (!INTENT_ID.test(intentId)) throw new ProfileError('PROFILE_UNAVAILABLE', true);
    const timestamp = new Date(this.now()).toISOString();
    const intent: IntentRow = {
      ownerId: owner, noteId: intentSortKey(intentId), entityType: 'PROFILE_AVATAR_INTENT',
      requestId: request.requestId, expectedProfileRevision: request.expectedProfileRevision,
      mime: request.mime, sizeBytes: request.sizeBytes, sha256: request.sha256,
      stageKey: `staging/profile/${owner}/${intentId}`, status: 'pending',
      createdAt: timestamp, ttl: ttlFrom(this.now(), INTENT_TTL_SECONDS),
    };
    const record: RequestRow = {
      ownerId: owner, noteId: requestSortKey(request.requestId), entityType: 'PROFILE_REQUEST',
      requestId: request.requestId, fingerprint, kind: 'intent', intentId, createdAt: timestamp,
      ttl: ttlFrom(this.now(), INTENT_TTL_SECONDS),
    };
    const outcome = await this.store.createIntent(intent, record, Math.floor(this.now() / 1000));
    if (outcome === 'conflict') throw new ProfileError('PROFILE_CONFLICT');
    if (outcome === 'retry') {
      const raced = await this.store.getRequest(owner, request.requestId);
      if (raced?.kind === 'intent' && raced.fingerprint === fingerprint && raced.intentId) return this.intentResponse(owner, raced.intentId);
      throw new ProfileError('PROFILE_UNAVAILABLE', true);
    }
    const capability = await this.objects.presignStagingPut(
      intent.stageKey, request.sizeBytes, request.sha256, request.mime,
    );
    return { intentId, uploadUrl: capability.url, headers: capability.headers };
  }

  async completeAvatarIntent(actor: string, intentId: string): Promise<ProfileDTO> {
    const owner = this.owner(actor);
    if (typeof intentId !== 'string' || !INTENT_ID.test(intentId)) throw new ProfileError('PROFILE_INVALID');
    const intent = await this.store.getIntent(owner, intentId);
    if (!intent) throw new ProfileError('PROFILE_MISSING');
    const current = await this.store.getProfile(owner);
    if (intent.status === 'complete') return this.completedProfile(current, intent);
    if (!current) throw new ProfileError('PROFILE_MISSING');
    if (intent.ttl * 1000 <= this.now()) throw new ProfileError('PROFILE_INVALID');
    if (current.revision !== intent.expectedProfileRevision) throw new ProfileError('PROFILE_CONFLICT');
    const pinned: PinnedObject = await this.objects.pin(intent.stageKey, {
      sizeBytes: intent.sizeBytes, sha256: intent.sha256,
    });
    if (pinned.mime !== intent.mime || pinned.sizeBytes > MAX_AVATAR_BYTES) throw new ProfileError('PROFILE_INVALID');
    const bytes = await this.objects.readPinned(intent.stageKey, pinned);
    try {
      inspectImage(bytes, intent.mime);
    } finally {
      bytes.fill(0);
    }
    const avatarId = intentId;
    if (!INTENT_ID.test(avatarId)) throw new ProfileError('PROFILE_UNAVAILABLE', true);
    const avatar: AvatarRecord = {
      avatarId, key: `final/profile/${owner}/${avatarId}`, version: pinned.version,
      mime: intent.mime, sizeBytes: pinned.sizeBytes, sha256: pinned.sha256,
    };
    const finalized = await this.objects.finalize(intent.stageKey, pinned, avatar.key);
    const row: ProfileRow = {
      ownerId: owner, noteId: PROFILE_SORT_KEY, entityType: 'PROFILE',
      displayName: current.displayName,
      avatarReference: referenceOf(avatarId),
      avatar: { ...avatar, version: finalized.version },
      revision: intent.expectedProfileRevision + 1,
      updatedAt: new Date(this.now()).toISOString(),
    };
    const outcome = await this.store.completeIntent(row, intent.expectedProfileRevision, intent);
    if (outcome !== 'ok') {
      const settled = await this.store.getIntent(owner, intentId);
      const profile = await this.store.getProfile(owner);
      if (settled?.status === 'complete') return this.completedProfile(profile, settled);
      throw new ProfileError('PROFILE_CONFLICT');
    }
    return dtoOf(row);
  }

  async readAvatar(actor: string): Promise<AvatarBinary> {
    const owner = this.owner(actor);
    const profile = await this.store.getProfile(owner);
    const avatar = profile?.avatar;
    if (!profile?.avatarReference || !avatar) throw new ProfileError('PROFILE_AVATAR_MISSING');
    const bytes = await this.objects.readPinned(avatar.key, {
      version: avatar.version, sizeBytes: avatar.sizeBytes, mime: avatar.mime, sha256: avatar.sha256,
    });
    return { bytes, mime: avatar.mime, version: avatar.version };
  }

  private async intentResponse(owner: string, intentId: string): Promise<AvatarIntent> {
    const intent = await this.store.getIntent(owner, intentId);
    if (!intent || intent.ttl * 1000 <= this.now()) throw new ProfileError('PROFILE_CONFLICT');
    const capability = await this.objects.presignStagingPut(
      intent.stageKey, intent.sizeBytes, intent.sha256, intent.mime,
    );
    return { intentId, uploadUrl: capability.url, headers: capability.headers };
  }

  /** Keep the current association or clear it - never an arbitrary reference. */
  private avatarForWrite(reference: string | null, current: ProfileRow | undefined): AvatarRecord | null {
    if (reference === null) return null;
    if (!reference.startsWith('av_')) throw new ProfileError('PROFILE_INVALID');
    if (!current?.avatarReference || !current.avatar || current.avatarReference !== reference) {
      throw new ProfileError('PROFILE_INVALID');
    }
    return current.avatar;
  }

  private completedProfile(current: ProfileRow | undefined, intent: IntentRow): ProfileDTO {
    const expected = intent.avatar ? referenceOf(intent.avatar.avatarId) : null;
    if (!current || !expected || current.avatarReference !== expected) throw new ProfileError('PROFILE_CONFLICT');
    return dtoOf(current);
  }

  private owner(actor: string): string {
    if (typeof actor !== 'string' || !OWNER_ID.test(actor)) throw new ProfileError('PROFILE_UNAUTHORIZED');
    return actor;
  }
}

/**
 * Stable backend entry point used by `amplify/sync/handler.ts`. `objects` is
 * injectable so tests run without credentials or network.
 */
export const createProfileService = (
  documentClient: DynamoDBDocumentClient,
  tableName: string,
  bucketName: string,
  objects: AvatarObjects = new S3AvatarObjects(bucketName),
): ProfileService => new ProfileServiceImpl(documentClient, tableName, objects);
