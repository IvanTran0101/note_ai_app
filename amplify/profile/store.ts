/**
 * Profile/intent persistence on the single existing notes table.
 *
 * Same table and key shape as the sync/attachment rows - `ownerId` (verified
 * Cognito `sub`) + `noteId` - but these items are deliberately *not* part of the
 * note stream: no `changeOwnerId`/`changeSequence` (change-feed GSI) and no
 * `relayQueue`/`relayDueAt` (relay GSI). Profile state must never reach the
 * note feed, labels, cursor or relay projections, so nothing here emits them.
 *
 * Conditional expressions are production DynamoDB semantics (Compare-and-Swap on
 * `revision`, `attribute_not_exists` for first write); the test double in
 * `profile_http.test.ts` evaluates the same subset against real command inputs.
 */
import {
  GetCommand,
  PutCommand,
  TransactWriteCommand,
  type DynamoDBDocumentClient,
} from '@aws-sdk/lib-dynamodb';
import type { AvatarMime, ProfileDTO } from './contract';

export const PROFILE_SORT_KEY = 'PROFILE#SELF';
export const intentSortKey = (intentId: string) => `PROFILE_AVATAR_INTENT#${intentId}`;
export const requestSortKey = (requestId: string) => `PROFILE_REQUEST#${requestId}`;

export type AvatarRecord = Readonly<{
  avatarId: string; key: string; version: string; mime: AvatarMime; sizeBytes: number; sha256: string;
}>;

export type ProfileRow = Readonly<{
  ownerId: string; noteId: string; entityType: 'PROFILE';
  displayName: string; avatarReference: string | null; avatar: AvatarRecord | null;
  revision: number; updatedAt: string;
}>;

export type IntentRow = Readonly<{
  ownerId: string; noteId: string; entityType: 'PROFILE_AVATAR_INTENT';
  requestId: string; expectedProfileRevision: number; mime: AvatarMime; sizeBytes: number; sha256: string;
  stageKey: string; status: 'pending' | 'complete'; createdAt: string; ttl: number;
  avatar?: AvatarRecord; completedRevision?: number;
}>;

export type RequestRow = Readonly<{
  ownerId: string; noteId: string; entityType: 'PROFILE_REQUEST'; requestId: string;
  fingerprint: string; kind: 'profile' | 'intent'; intentId?: string; profile?: ProfileDTO; createdAt: string; ttl: number;
}>;

/** `complete` means a previous complete-intent attempt already committed. */
export type TransactOutcome = 'ok' | 'conflict' | 'retry' | 'complete';

const cancelledReasons = (error: unknown): readonly { Code?: string }[] => {
  const reasons = (error as { CancellationReasons?: { Code?: string }[] }).CancellationReasons;
  return Array.isArray(reasons) ? reasons : [];
};

export class ProfileStore {
  constructor(readonly tableName: string, readonly client: DynamoDBDocumentClient) {
    if (!tableName) throw new Error('ProfileStore requires a table name.');
  }

  async getProfile(ownerId: string): Promise<ProfileRow | undefined> {
    const result = await this.client.send(new GetCommand({
      TableName: this.tableName, Key: { ownerId, noteId: PROFILE_SORT_KEY }, ConsistentRead: true,
    }));
    return result.Item as ProfileRow | undefined;
  }

  async getIntent(ownerId: string, intentId: string): Promise<IntentRow | undefined> {
    const result = await this.client.send(new GetCommand({
      TableName: this.tableName, Key: { ownerId, noteId: intentSortKey(intentId) }, ConsistentRead: true,
    }));
    return result.Item as IntentRow | undefined;
  }

  async getRequest(ownerId: string, requestId: string): Promise<RequestRow | undefined> {
    const result = await this.client.send(new GetCommand({
      TableName: this.tableName, Key: { ownerId, noteId: requestSortKey(requestId) }, ConsistentRead: true,
    }));
    return result.Item as RequestRow | undefined;
  }

  /** One transaction: either the profile CAS *and* its request record commit, or neither. */
  async saveProfile(
    profile: ProfileRow, expected: number, request: RequestRow,
  ): Promise<TransactOutcome> {
    try {
      await this.client.send(new TransactWriteCommand({ TransactItems: [
        {
          Update: {
            TableName: this.tableName,
            Key: { ownerId: profile.ownerId, noteId: PROFILE_SORT_KEY },
            UpdateExpression: 'SET #displayName = :displayName, #avatarReference = :avatarReference, ' +
              '#avatar = :avatar, #revision = :revision, #updatedAt = :updatedAt, #entityType = :entityType',
            ConditionExpression: expected === 0 ? 'attribute_not_exists(#revision)' : '#revision = :expected',
            ExpressionAttributeNames: {
              '#displayName': 'displayName', '#avatarReference': 'avatarReference', '#avatar': 'avatar',
              '#revision': 'revision', '#updatedAt': 'updatedAt', '#entityType': 'entityType',
            },
            ExpressionAttributeValues: {
              ':displayName': profile.displayName, ':avatarReference': profile.avatarReference,
              ':avatar': profile.avatar, ':revision': profile.revision, ':updatedAt': profile.updatedAt,
              ':entityType': 'PROFILE', ...(expected === 0 ? {} : {':expected': expected}),
            },
          },
        },
        {
          Put: {
            TableName: this.tableName, Item: request,
            ConditionExpression: 'attribute_not_exists(#noteId)',
            ExpressionAttributeNames: { '#noteId': 'noteId' },
          },
        },
      ] }));
      return 'ok';
    } catch (error) {
      const reasons = cancelledReasons(error);
      if (reasons.length) return reasons[1]?.Code === 'ConditionalCheckFailed' ? 'retry' : 'conflict';
      throw error;
    }
  }

  async createIntent(intent: IntentRow, request: RequestRow, nowSeconds: number): Promise<TransactOutcome> {
    try {
      await this.client.send(new TransactWriteCommand({ TransactItems: [
        {
          Put: {
            TableName: this.tableName, Item: intent,
            ConditionExpression: 'attribute_not_exists(#noteId)',
            ExpressionAttributeNames: { '#noteId': 'noteId' },
          },
        },
        {
          Put: {
            TableName: this.tableName, Item: request,
            ConditionExpression: 'attribute_not_exists(#noteId) OR #ttl <= :now',
            ExpressionAttributeNames: { '#noteId': 'noteId', '#ttl': 'ttl' },
            ExpressionAttributeValues: { ':now': nowSeconds },
          },
        },
      ] }));
      return 'ok';
    } catch (error) {
      const reasons = cancelledReasons(error);
      if (reasons.length) return reasons[1]?.Code === 'ConditionalCheckFailed' ? 'retry' : 'conflict';
      throw error;
    }
  }

  /**
   * Associate a verified avatar and complete its intent atomically. The intent
   * condition makes the retry after a lost ACK observable instead of duplicating
   * the association: `complete` means a previous attempt already committed.
   */
  async completeIntent(
    profile: ProfileRow, expected: number, intent: IntentRow,
  ): Promise<TransactOutcome> {
    try {
      await this.client.send(new TransactWriteCommand({ TransactItems: [
        {
          Update: {
            TableName: this.tableName,
            Key: { ownerId: profile.ownerId, noteId: PROFILE_SORT_KEY },
            UpdateExpression: 'SET #avatarReference = :avatarReference, #avatar = :avatar, ' +
              '#revision = :revision, #updatedAt = :updatedAt, #entityType = :entityType',
            ConditionExpression: expected === 0 ? 'attribute_not_exists(#revision)' : '#revision = :expected',
            ExpressionAttributeNames: {
              '#avatarReference': 'avatarReference', '#avatar': 'avatar', '#revision': 'revision',
              '#updatedAt': 'updatedAt', '#entityType': 'entityType',
            },
            ExpressionAttributeValues: {
              ':avatarReference': profile.avatarReference, ':avatar': profile.avatar,
              ':revision': profile.revision, ':updatedAt': profile.updatedAt,
              ':entityType': 'PROFILE', ...(expected === 0 ? {} : {':expected': expected}),
            },
          },
        },
        {
          Update: {
            TableName: this.tableName,
            Key: { ownerId: intent.ownerId, noteId: intent.noteId },
            UpdateExpression: 'SET #status = :status, #avatar = :avatar, #completedRevision = :completedRevision',
            ConditionExpression: '#status = :pending',
            ExpressionAttributeNames: {
              '#status': 'status', '#avatar': 'avatar', '#completedRevision': 'completedRevision',
            },
            ExpressionAttributeValues: {
              ':status': 'complete', ':avatar': profile.avatar,
              ':completedRevision': profile.revision, ':pending': 'pending',
            },
          },
        },
      ] }));
      return 'ok';
    } catch (error) {
      const reasons = cancelledReasons(error);
      if (reasons.length) return reasons[0]?.Code === 'ConditionalCheckFailed' ? 'conflict' : 'complete';
      throw error;
    }
  }
}

/** `ttl` is the existing table TTL attribute; profiles themselves never expire. */
export const ttlFrom = (now: number, seconds: number) => Math.floor(now / 1000) + seconds;
