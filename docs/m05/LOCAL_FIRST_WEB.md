# M05 - Web local-first correction

User decision, 2026-10-02: notes are persisted locally first, then synchronized
to cloud. Applies to M05 and all future Web implementation. M06 stays paused.

## Required behavior

- Web creation/edit/protection operations commit to account-scoped IndexedDB
  before cloud work. Network/backend configuration must not gate local success.
- Each note keeps its own password-derived salted representation; raw passwords
  never persist or enter logs, localStorage, IndexedDB, DTOs or outbox.
- Preserve authenticated encrypted content, existing ciphertext/AAD, note IDs,
  cursor, mutation IDs/base revisions/retries, conflicts and encrypted drafts.
- Unlock/relock, current-password verification for change/disable, independent
  note keys and session/expiry/account fences apply locally, including reload.
- Cloud synchronization follows the existing single account sync engine and
  an explicit durable pending protection contract. Local proof and remote
  authorization are distinct. User confirmed cloud continues to enforce protection when syncing.
- Local save and cloud sync states must be distinguishable in UI. The requested
  visual redesign itself remains in M09's two-image Notion backlog.

## Historical source gap (9f94237)

Encrypted IndexedDB is already the Web note backing. Password actions still
require cloud synchronization/metadata before enable, and remote manage grants
before change/disable. Offline unlock exists after online provisioning but
local enable/rotation/disable for a new unsynced note are not implemented.

## Acceptance batch — verified 2026-10-02

- [x] Enable protection on a new unsynced note with network unavailable.
- [x] Correct/wrong password and independent note scopes work across reload.
- [x] Current-password verification + rotation/disable work locally offline.
- [x] Ciphertext and safe password representation persist atomically in IndexedDB.
- [x] Pending cloud changes are durable and cannot publish protected plaintext
  through an unprotected creation/update/feed path.
- [x] Sync conflict/idempotency/access/session guards remain effective.
- [x] Real Chrome offline/reload integration and Android regression pass.
- [ ] Notion/MUST_REMEMBER/progress updated and checkpoint pushed.

The checklist above is the correction acceptance gate. Earlier server-first
acceptance remains historical in PROGRESS.md.

## Accepted implementation batch

Added local atomic vault/outbox intent and fixed salted PBKDF2 verifier with a
separate salt from the wrapping key. Dedicated protected-mutation route fails
closed against old servers; owner/manage grants and epoch are pinned in the
content/protection transaction. Pending/older cloud metadata cannot downgrade
a local password change. Final VM/Chrome/Android and offline reload tests pass; see PROGRESS.md for counts.

An attempted unprotected predecessor uses the read-only receipt route. A known
receipt is acknowledged as metadata; unknown delivery creates an explicit
conflict. The client never resends that predecessor through a write route after
local enable. Use-local conflict resolution retains the latest protection intent.
M06 remains paused.

## Ownership and persistence

Application defines local vault actions and the protection intent carried by the
existing content outbox. Infrastructure owns PBKDF2/AEAD, encrypted storage/CAS,
wire codecs and backend transactions. Presentation calls those use cases.

The Web composition selects local-first; native legacy orchestration remains
covered by regression. Each local action seals content, wraps/rewraps the note
key and writes protection metadata + outbox intent in one encrypted account CAS.
The verifier uses PBKDF2-HMAC-SHA256 (600,000 iterations, 32-byte result, separate
random 16-byte salt). The whole representation is inside the account envelope;
its salt is independent from password wrapping. Raw passwords and cloud grants
are transient. A new device without a local wrapped key provisions it through
online authorization; wrong passwords or tampered ciphertext never trigger a
cloud fallback.

An unattempted mutation can coalesce without changing its ID/base revision; an
attempted or blocked mutation is immutable and the new change gets its own ID.
Pending protection takes priority over older feed/hydration metadata. Compound
ACKs preserve local content even when their metadata-only response has no body.

## Cloud routes and compatibility

- `POST /sync/protected-mutations`: ordinary mutation fields plus
  `protectionChange = {before: {enabled, revision}, after: {enabled, revision},
  verifier}`. Enabled requires the fixed canonical salted verifier; disabled
  requires null. Delete cannot carry a protection change.
- The before epoch must match fresh cloud metadata. Enabling from an unprotected
  predecessor needs owner JWT/ACL; rotating/disabling a protected predecessor
  additionally needs a current manage grant. Content, protection, sequence,
  change-feed and idempotency receipt commit in one DynamoDB transaction.
- `POST /sync/protection-predecessor`: read-only receipt inspection with fresh
  owner ACL and exact legacy fingerprint; missing receipt returns a conflict.
- Ordinary `/sync/mutations` refuses a protection descriptor. Older servers do
  not know the dedicated route and fail closed; the client has no insecure
  fallback to an ordinary write.
- Protected feed/receipt/compound ACKs contain metadata only. The server stores
  authorized note content for existing AI flows: this is app-level protection.
- Offline rotation may leave the cloud password different from the local one.
  The UI's pending-sync action asks for the current cloud password to renew the
  remote grant. It never changes the local password or persists the cloud input.

## Acceptance limits

Real Chrome reload testing loads app assets first, then disables networking for
password/storage actions. This verifies IndexedDB durability across a full page
reload and offline use cases; it does not claim offline PWA asset boot. Platform
integration uses real crypto and storage, with synthetic UI security gateways.
Backend tests use production policies/transactions with AWS/SES/provider doubles.
No cloud deployment or live mailbox/provider delivery is included. Pending cloud
sync requires the new routes to be deployed separately.

## Final runtime evidence

VM942 (2 browser-only skips), Chrome815 (1 intentional local-AI skip), real
Chrome8 and Android8 passed with no failures. Both current-source Chrome seed
and full-page reload phases returned driver true / empty failureDetails with
network disabled for all password/storage actions. Backend64 checks, root
analyzer and TypeScript check pass. Native-only tests remain in VM. Source
fixture/render/target-selection repairs and exact limits are in PROGRESS.md.
