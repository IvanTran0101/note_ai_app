# Profile & Avatar API v1 (M01.1 backend contract — frozen)

Backend lane: `amplify/profile/**`. Owner: backend/profile lane. The Flutter
client (`lib/infrastructure/users/http_profile_avatar_gateway.dart`) and the
root dispatcher (`amplify/sync/handler.ts`) consume this contract; the plan of
record is `_agent_ops/reviews/remaining-implementation-plan-2026-10-09.md`
(M01.1–M01.3). Not user-facing prose.

## Routing & authorization

All routes live under `/me/`, are reached through the existing sync HTTP API and
Cognito JWT authorizer, and are dispatched by `amplify/sync/handler.ts` only when
`requestContext.authorizer.jwt.claims.sub` is present and
`token_use === 'access'`. `handleProfile` repeats both the subject and access-token checks.

- Self-only: the acting account is always the verified JWT `sub`. `ownerId` is
  never read from the path, query string or body.
- A body/field that tries to name another owner (`ownerId`, `userId`, `actor`,
  `sub` with a different value) is `403 PROFILE_UNAUTHORIZED`; any other unknown
  field is `422 PROFILE_INVALID`.
- No email-verification gate: an unverified account may own and edit its profile.
- Storage: one existing DynamoDB table (`ownerId` = JWT `sub`,
  `noteId` = `PROFILE#SELF` / `PROFILE_AVATAR_INTENT#<id>` /
  `PROFILE_REQUEST#<requestId>`). No feed, GSI or relay attributes are written
  (`changeOwnerId`, `changeSequence`, `relayQueue`, `relayDueAt` are absent), so
  profile rows never enter the note stream, labels, cursor or relay projections.
- Intents and request-idempotency rows carry the existing table `ttl` attribute
  (intents and intent-request records 1 h; profile-write records 24 h). The profile row itself never expires.

## Endpoints

### `GET /me/profile`

`200 {"profile": ProfileDTO}` or, when the canonical row is absent,
`404 {"code":"PROFILE_MISSING"}`.

### `POST /me/profile`

Body (all four keys required, unknown keys denied):

```json
{ "requestId": "uuid-or-opaque", "expectedRevision": 0,
  "displayName": "Kiet Nguyen", "avatarReference": null }
```

- `requestId`: `[A-Za-z0-9_-]{8,128}`; stable across client retries.
- `displayName`: trimmed, 1–100 Unicode code points (same Dart runes / JavaScript iteration).
- `expectedRevision`: `0` creates the profile if absent. A mismatch (including a
  concurrent edit on another device) is `409 PROFILE_CONFLICT`; never
  last-write-wins.
- `avatarReference`: `null` clears, the current `av_<32 hex>` keeps. Any other
  value is `422 PROFILE_INVALID` — association happens only through
  `POST /me/avatar-intents/{id}/complete`.
- Retrying the same `requestId` returns the stored prior outcome and never
  overwrites an existing profile or avatar. Reusing an active request id with a changed payload is rejected.
- Whole body is capped at 8 KiB (`PROFILE_INVALID` above that).

`200 {"profile": ProfileDTO}`.

`ProfileDTO = { userId, displayName, avatarReference: string|null, revision, updatedAt }`
— no storage key, object version, checksum, token or URL crosses this boundary.

### `POST /me/avatar-intents`

```json
{ "requestId": "uuid", "expectedProfileRevision": 1,
  "mime": "image/png", "sizeBytes": 4096, "sha256": "<64 lower hex>" }
```

`mime` is `image/png` or `image/jpeg`; `sizeBytes` is 1..1048576. Same
`requestId` returns the same `intentId` with a freshly signed URL.
`expectedProfileRevision` must equal the current revision (`409` otherwise). A display name must already be initialized; avatar upload cannot create a blank profile. Pending intents expire after one hour, enforced by the server clock independently of DynamoDB TTL deletion. An expired request may be restarted safely with a new intent.

`200 { "intentId": "<32 hex>", "uploadUrl": "...", "headers": { ... } }`

The signature covers the exact staging key `staging/profile/<sub>/<intentId>`,
`content-length`, `content-type`, `x-amz-checksum-sha256` and
`x-amz-server-side-encryption: AES256`; it expires in 120 s and cannot be
reused for another key. Bucket is private/versioned/SSE; no public or signed GET
URL is ever issued.

### `POST /me/avatar-intents/{id}/complete`

Body `{}` (client supplies neither key nor version; any field is
`422 PROFILE_INVALID`). The server:

1. pins the staging object's exact `VersionId` (HEAD with checksum mode),
2. reads that version bounded to 1 MiB and verifies actual length + SHA-256,
3. checks PNG signature/chunk bounds/CRC/IHDR/IDAT/IEND and JPEG SOF/SOS/EOI headers, dimensions 1..2048 on both axes; malformed
   or truncated headers are `422`,
4. copies the pinned version to the immutable final key
   `final/profile/<sub>/<intentId>`, then verifies exact final version, length, MIME and checksum before association,
5. commits the association and the intent completion in one DynamoDB
   transaction, conditional on the profile revision.

A lost ACK is safe: the same `intentId` returns the settled profile without a
second association. A revision conflict is `409` and the previous avatar is
retained. A failed replacement never deletes the current avatar or staging bytes
(staging is cleaned by the bucket lifecycle rule).

`200 {"profile": ProfileDTO}`.

### `GET /me/avatar`

`200` with the current avatar as base64 (`isBase64Encoded: true`,
`content-type: image/png|image/jpeg`, `cache-control: no-store`,
`x-content-type-options: nosniff`, ≤ 1 MiB, read at the exact stored version).
No active avatar is `404 PROFILE_AVATAR_MISSING`. `avatarReference` in the DTO
is opaque; the client requests this route instead of building a URL.

## Errors

| code | status | meaning |
| --- | --- | --- |
| `PROFILE_MISSING` | 404 | no canonical profile / unknown intent id |
| `PROFILE_AVATAR_MISSING` | 404 | no active avatar |
| `PROFILE_INVALID` | 422 | malformed body, denied unknown field, bad bytes, bad MIME/size/checksum/dimensions |
| `PROFILE_CONFLICT` | 409 | stale `expectedRevision`, stale intent revision, or intent already settled for different content |
| `PROFILE_UNAUTHORIZED` | 403 | JWT `sub` ≠ actor, or a body field names another owner |
| `PROFILE_UNAVAILABLE` | 503 | storage/provider failure; the only safe-to-retry code |

Envelope: `{"code": "..."}` only — no provider message, key, token or stack.
Unexpected (non-`ProfileError`) failures are mapped to `503 PROFILE_UNAVAILABLE`.

## Verification

`node --import tsx --test amplify/profile/profile.test.ts` — routing/JWT
mismatch, forged owner fields, unknown-field denial, name bounds, revision
conflict, create/rename retry idempotency, absent feed/GSI/relay attributes,
owner isolation, intent bounds, SSE/checksum upload headers, successful
associate + idempotent complete, base64 `GET /me/avatar`, malformed/truncated
PNG+JPEG, >2048 px, checksum mismatch, stale version pinning, and TTL bounds.
Provider-level (live S3/DynamoDB/Cognito) evidence is out of scope for this
source-level contract.
