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
    "content": "Content"
  }
}
```

`create` and `update` require `payload`. `delete` may omit it. The client
supplies `baseRevision`; the server assigns the next revision and timestamps.

Applied response:

```json
{
  "status": "applied",
  "mutationId": "mutation-123",
  "note": {
    "id": "note-123",
    "title": "Title",
    "content": "Content",
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
  "remoteNote": {}
}
```

The same `mutationId` is idempotent. A retry returns the original result and
does not apply the mutation twice.

### GET /sync/changes?cursor=&limit=50

The cursor is opaque. Flutter stores it and sends it back unchanged.

```json
{
  "items": [],
  "nextCursor": "opaque-value",
  "hasMore": false
}
```

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

## M1.0 stop gate

- [ ] Request and response shapes are frozen.
- [ ] `ownerId` is derived from Cognito JWT `sub` on the server.
- [ ] `baseRevision` and `mutationId` semantics are frozen.
- [ ] Conflict, tombstone, cursor, and error behavior are documented.
- [ ] No AWS SDK or HTTP dependency appears in Domain/Application.
