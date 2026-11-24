# NoteFlow Remote Sync API Contract (M1.0)

This document freezes the provider-neutral HTTP contract for note
synchronization. M1.0 does not implement the API, Lambda, DynamoDB, or the
Flutter HTTP adapter.

## Trust boundary

```text
Flutter
  -> Authorization: Bearer <Cognito access token>
  -> API Gateway HTTP API (JWT authorizer)
  -> Lambda
  -> DynamoDB
```

Lambda derives the account namespace from the authenticated Cognito `sub`.
The request body must not be treated as authoritative for `ownerId`.

## Routes

### POST /sync/mutations

Request body:

```json
{
  "mutationId": "mutation-123",
  "noteId": "note-123",
  "operation": "create",
  "baseRevision": 0,
  "payload": {
    "title": "Title",
    "content": "Content",
    "pinnedAt": null
  }
}
```

`create` and `update` require `payload`. `delete` may omit it. The client
supplies `baseRevision`; the server assigns the next revision and timestamps.
Pin mutations send `pinnedAt` as `null` or a UTC ISO-8601 timestamp. Text-only
payloads may omit it; omission preserves the server's current pin state and
legacy attempted-request fingerprints.
Titles and content must contain non-whitespace text, but the server preserves
their original formatting.

Applied response:

```json
{
  "status": "applied",
  "mutationId": "mutation-123",
  "note": {
    "id": "note-123",
    "title": "Title",
    "content": "Content",
    "pinnedAt": null,
    "revision": 1,
    "deletedAt": null
  }
}
```

Conflict response (`409`):

```json
{
  "code": "REVISION_CONFLICT",
  "retryable": false,
  "mutationId": "mutation-123",
  "remoteNote": null
}
```

The same `mutationId` is idempotent. A retry returns the original result and
does not apply the mutation twice. The fingerprint for an old payload that
omits `pinnedAt` keeps the old shape, so retrying an already-attempted
mutation remains idempotent.

## Module 02 pin and layout semantics

Pin state belongs to the note owner. A recipient can read the status but cannot
change it. A payload containing `pinnedAt` requires the owner's `manage`
capability; protected notes also require a current matching scoped grant.
Recipient text updates omit `pinnedAt`; the shared route rejects that field.
Shared-note access, pin status, and cache behavior follow the
Modules 05–06 contract; this API does not add a separate shared-note pin path.
Pinning an already-pinned note is a no-op. Unpinning then pinning records a new
UTC `pinnedAt`; unpinning sends `null`.

The dashboard's grid/list choice is a per-account local preference and is not
included in the sync API.

### GET /sync/changes?cursor=&limit=50

The cursor is opaque. Flutter stores it and sends it back unchanged.

```json
{
  "items": [],
  "nextCursor": "opaque-value",
  "hasMore": false
}
```

The client stores `nextCursor` even when `hasMore` is false. It is the last
successfully applied position, not only a request for another page.

Deleted notes remain represented as tombstones until the sync policy allows
cleanup.

## Error envelope

```json
{
  "code": "SERVER_UNAVAILABLE",
  "message": "A safe user-facing message",
  "retryable": true
}
```

The provider adapter must not expose SDK exceptions, stack traces, raw URLs,
credentials, tokens, or request bodies through this contract.

| HTTP status | Contract meaning |
| --- | --- |
| 401 | Missing, expired, or invalid JWT |
| 403 | Authenticated user cannot access the resource |
| 409 | Revision conflict |
| 422 | Invalid mutation payload |
| 429 | Retryable throttling |
| 500/503 | Retryable backend failure |

## Application port

`IRemoteNoteDataSource` in
`lib/application/sync/sync_contract.dart` is the only Application-facing
remote port. The future Infrastructure adapter owns HTTP, token attachment,
JSON mapping, and provider error mapping.

## M1.2 backend semantics

The sandbox implementation stores one per-account sequence item and writes the
note snapshot, change-feed row, and idempotency record in one DynamoDB
transaction. Change-feed rows use the sparse `ChangesByOwnerSequence` index.

```text
OWNER#sub / META#SYNC
OWNER#sub / NOTE#note-id
OWNER#sub / MUTATION#mutation-id
OWNER#sub / CHANGE#sequence
```

An accepted mutation advances the account sequence. A stale `baseRevision`
returns `409 REVISION_CONFLICT`; it does not create a change-feed row. A retry
with the same `mutationId` replays the original applied response.

The cursor is account-bound and opaque. The client stores it even when
`hasMore` is false, because it represents the last successfully applied
sequence. Since DynamoDB GSI reads are eventually consistent, a response may
contain a gap in the account sequence. The server returns only the contiguous
prefix before that gap and stops advancing; a later sync request retries from
the same cursor after index propagation catches up.

## M1.0 stop gate

- [ ] Request and response shapes are frozen.
- [ ] `ownerId` is derived from Cognito JWT `sub` on the server.
- [ ] `baseRevision` and `mutationId` semantics are frozen.
- [ ] Conflict, tombstone, cursor, and error behavior are documented.
- [ ] No AWS SDK or HTTP dependency appears in Domain/Application.
