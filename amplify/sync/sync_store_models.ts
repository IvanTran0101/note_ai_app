import type { DynamoDBDocumentClient } from '@aws-sdk/lib-dynamodb';
import type { NoteSecurityAuthority } from '../protection/protection_store';

export type NoteSnapshot = Readonly<{
  id: string;
  title: string;
  content: string;
  revision: number;
  createdAt: string;
  serverUpdatedAt: string;
  deletedAt: string | null;
  protected?: boolean;
  protectionRevision?: number;
  contentAvailable?: boolean;
}>;

export type ProtectionSyncChange = Readonly<{
  before: Readonly<{ enabled: boolean; revision: number }>;
  after: Readonly<{ enabled: boolean; revision: number }>;
  verifier: string | null;
}>;

export type SyncOperation = 'create' | 'update' | 'delete';

/** `create` and `update` require this; `delete` ignores it. */
export type MutationPayload = Readonly<{ title: string; content: string }>;

/** One client mutation, already stripped of transport concerns. */
export type SyncMutation = Readonly<{
  mutationId: string;
  noteId: string;
  operation: SyncOperation;
  baseRevision: number;
  payload?: MutationPayload;
  protectionChange?: ProtectionSyncChange;
}>;

export type AppliedMutation = Readonly<{
  status: 'applied';
  mutationId: string;
  note: NoteSnapshot;
  /** True when the stored result of an earlier identical mutation was replayed. */
  replayed: boolean;
}>;

export type ConflictedMutation = Readonly<{
  status: 'conflict';
  mutationId: string;
  /** The stored note at decision time, or `null` when the account has none. */
  remoteNote: NoteSnapshot | null;
}>;

export type ApplyMutationResult = AppliedMutation | ConflictedMutation;

export type ChangesPage = Readonly<{
  items: readonly NoteSnapshot[];
  /** Always minted: the caller stores it and sends it back on the next poll. */
  nextCursor: string;
  hasMore: boolean;
}>;

/** The port `handler.ts` codes against; nothing here knows about HTTP. */
export interface SyncStore {
  /**
   * Applies one mutation for `ownerId` (the verified JWT `sub`).
   *
   * @throws SyncInvalidMutationError when the request cannot be applied as sent.
   * @throws SyncStorageError when storage failed; `retryable` says whether the
   *         same request may be sent again.
   */
  applyMutation(ownerId: string, mutation: SyncMutation,
    authorization?: Readonly<{ actorId: string; grant?: string; inspectOnly?: boolean }>): Promise<ApplyMutationResult>;

  /**
   * Lists changes above `cursor` in ascending sequence order. A missing cursor
   * starts from the beginning; `limit` is clamped to 1..100 (default 50). The
   * cursor advances only across contiguous sequence numbers, so an eventually
   * consistent GSI gap is retried on a later poll instead of being skipped.
   *
   * @throws SyncInvalidCursorError when the cursor is not this account's.
   * @throws SyncStorageError when storage failed.
   */
  listChanges(ownerId: string, cursor?: string | null, limit?: number): Promise<ChangesPage>;
}

export type InvalidMutationReason =
  | 'MUTATION_ID_INVALID'
  | 'MUTATION_ID_REUSED'
  | 'NOTE_ID_INVALID'
  | 'OPERATION_UNSUPPORTED'
  | 'BASE_REVISION_INVALID'
  | 'PAYLOAD_REQUIRED'
  | 'PAYLOAD_INVALID'
  | 'PAYLOAD_TOO_LARGE';

/** The request is not applicable as sent; the handler maps this to a client error. */
export class SyncInvalidMutationError extends Error {
  readonly code = 'INVALID_MUTATION';
  readonly reason: InvalidMutationReason;

  constructor(reason: InvalidMutationReason, message: string) {
    super(message);
    this.name = 'SyncInvalidMutationError';
    this.reason = reason;
  }
}

/** Storage failed. `retryable` distinguishes "send it again" from "do not". */
export class SyncStorageError extends Error {
  readonly code = 'STORAGE_FAILURE';
  readonly retryable: boolean;

  /** `cause` carries the provider error for server-side logs only; never serialize it. */
  constructor(message: string, options?: Readonly<{ retryable?: boolean; cause?: unknown }>) {
    super(message, options?.cause === undefined ? undefined : { cause: options.cause });
    this.name = 'SyncStorageError';
    this.retryable = options?.retryable !== false;
  }
}

export type DynamoSyncStoreOptions = Readonly<{
  tableName: string;
  /** Defaults to the client's own chain, which resolves `AWS_REGION` in Lambda. */
  region?: string;
  /** Injection seam: a warmer path or a test can supply its own document client. */
  documentClient?: DynamoDBDocumentClient;
  security?: NoteSecurityAuthority;
}>;

export type NormalizedMutation = Readonly<{
  mutationId: string;
  noteId: string;
  operation: SyncOperation;
  baseRevision: number;
  payload: MutationPayload | null;
  protectionChange?: ProtectionSyncChange;
  fingerprint: string;
}>;

export type StoredMutation = Readonly<{ fingerprint: string; note: NoteSnapshot }>;

export type ConflictCheck =
  | Readonly<{ kind: 'apply' }>
  | Readonly<{ kind: 'conflict'; remoteNote: NoteSnapshot | null }>;

export type CommitOutcome = Readonly<{ kind: 'committed'; note: NoteSnapshot }> | Readonly<{ kind: 'retry' }>;
