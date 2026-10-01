# M05 security contract — implementation vocabulary

Version: 1. Date: 2026-10-02. Scope: M05 and required existing integration seams.

## Identity and access

Canonical note identity is ownerId + noteId. Actor comes from the verified
Cognito JWT `sub`, never a body-supplied actor. Existing sync is owner-scoped;
the initial ACL adapter authorizes only the owner. Other roles must be supplied
by an actual sharing ACL adapter; absent sharing support fails closed.

Operations: read, edit, delete, manage, summary, export, attachmentRead and
attachmentWrite. Read does not imply Summary/export/manage. Owner controls
enable/change/disable/reset/delete. Authorization always intersects current
ACL, grant scope, note protection revision and server-clock expiry.

## HTTP boundary

- `GET /notes/{noteId}/protection`: safe protection metadata.
- `POST /notes/{noteId}/protection/enable`: password + expected content revision.
- `POST /notes/{noteId}/protection/unlock`: password + requested operations.
- `POST /notes/{noteId}/protection/change`: current/new password + expected epoch.
- `POST /notes/{noteId}/protection/disable`: current password + expected epoch.
- `POST /notes/{noteId}/protection/reset/request`: owner-mailbox challenge.
- `POST /notes/{noteId}/protection/reset/confirm`: challengeId/code/new password.
- `GET /notes/{noteId}/content`: separately authorized content snapshot.
- Existing mutation, replay, conflict and Summary requests share this authority.

Every request needs JWT. Protected operations carry `X-Note-Unlock-Grant`, never
in URL/body/cache/outbox. Errors expose stable code-only failures. A grant is
random 256-bit opaque data; the backend persists only its hash, actor/note/epoch,
operations and issuedAt/expiresAt. Default TTL is 15 minutes, configurable.
Database TTL cleanup is not an authorization decision.

## Protection and recovery

- Domain metadata: enabled + nonnegative protectionRevision; enabled requires a
  positive epoch. No password/hash/grant/keys/SDK types in Domain or UI DTOs.
- Backend adapter: salted Argon2id, 64 MiB, 3 iterations, parallelism 1; fixed
  version/parameters and constant-time comparison; bounded input/attempts.
- Enable/change/disable updates note epoch conditionally and invalidates prior
  grants. Enable completes only after local sealing is durable too.
- Recovery: owner-only mailbox OTP, hashed code, bounded expiry/attempts and
  atomic consume. Sender configuration and SES permissions are server-side.
- Reset cannot unwrap an old password-derived local key. Keep encrypted pending
  ciphertext and mark it blocked; do not replace/discard it with a remote body.

## Local storage and keys

- Storage v3 is an authenticated encrypted account envelope. Legacy v2 decode
  is bounded to migration; staged writes contain ciphertext only. Keep exact
  namespace/IDs/cursor/outbox/conflict/mutation identities and timestamps.
- Each protected note seals content plus all its pending/conflict copies with
  a random DEK. A password-derived KEK wraps that DEK. Device key access does
  not unlock the per-note ciphertext.
- Local KDF: PBKDF2-HMAC-SHA256, 600,000 iterations, random salt; AEAD:
  AES-256-GCM, fresh nonce, AAD binds account + note + protection epoch.
  Use the vetted cryptography adapter; do not write a custom primitive.
- Native device-envelope keys use platform secure storage. Web uses the
  secure-storage WebCrypto boundary. Per-note key wrapping still requires the
  note password. No raw note password, DEK or server grant is persisted.
- Decode locked records as safe metadata and blocked placeholders while keeping
  their original sealed payload. A save of unrelated notes cannot destroy them.
- Offline unwrap grants local capabilities only; reconnect needs a fresh server
  grant. Lock/logout/expiry/account switch clear keys/grants/display/AI memory.
- Native cutover uses atomic rename; Web persists via one IndexedDB transaction.
  Read/write/sync operations serialize with migration; failure stays blocked.

## Sync and Summary

- Protected change-feed/history responses omit title/content even if unlocked.
  Current protection state masks historical rows, replays and conflicts.
- Metadata hydration does not create edits/outbox entries. Keep encrypted local
  pending work on denied/stale authority; continue unrelated notes and pull.
- Sync commits use current epoch conditions, including retry and replay checks.
- Summary contract v0.4 adds noteId, contentRevision, protectionRevision, runId
  and stage lineage. Backend reads the authoritative snapshot; client inputs
  must match approved direct/section/merge lineage. Validate before quota,
  before provider and before output. Keep existing consent/session/cancel checks.
- Protected operations not provided by the current module remain unavailable;
  no arbitrary attachment/export/share route can substitute for authorization.

## Evidence

M05.0 aligns 39 required production/config/contract files from reviewed baseline
6ce2afe into the target checkout, preserving the prior DTO redaction. It excludes
unrelated local files, developer mocks, phase reports and test files. The target
has its own graph project `noteflow-m05`; direct source fallback covers graph gaps.
Runtime/deployment acceptance is separate from source/static-check evidence.
