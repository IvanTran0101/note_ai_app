# M06 — Contract freeze

Source: https://app.notion.com/p/3e8f9c7a1aa08193b4f9d1fbf42999ed
Planning/DDD and settled Option A apply. Baseline is the accepted M05 worktree
at 22587a5954c182c202d07923ec8be1e3060fa42d; only M06 is active.

## Identity and access

- NoteIdentity is the immutable pair (canonicalOwnerId, noteId). Neither field
  is rewritten for recipients. Account/cache namespace remains the JWT actor.
- Add a collision-free pair key for comparisons, selection, navigation, pending
  queues, conflicts, blocked-note sets, grants and Summary run scope. Existing
  bare-id calls resolve only inside the caller's owned namespace; received-note
  references explicitly carry both fields. Wire requests carry canonical fields.
- NoteRole has viewer/editor. NoteShareGrant contains canonical identity,
  recipientId, role, sharedAt, updatedAt, revokedAt, accessRevision and status.
  Active share is immediate; no invitation acceptance. Owner transfer/copy is
  outside scope. One active grant per recipient/canonical note; no self-share.
- Foreign local projections require a matching recipient and canonical identity.
  Revoked projections remain for bookkeeping but cannot disclose content or
  authorize writes. Independent accessRevision applies before content/pending
  filtering. Access removal does not delete/tombstone the owner's note.
- Client policy governs local UX/offline edits; server current ACL is authority.
  Viewer reads and uses permitted Summary; editor changes title/content only.
  Owner manages sharing, protection, delete, pin and labels. Attachments retain
  the M03 handoff; do not create attachment writes in this module.

## Server contract

- Owner resolves registered, email_verified Cognito identities privately. Never
  auto-verify a mailbox or expose a directory; unknown/unverified/self/duplicate
  requests return safe typed errors. Persist recipient sub, not email authority.
- List/create/change/revoke requires owner and current M05 manage authority.
  Role/revoke update conditionally against expected accessRevision.
- Every content/edit/replay/history/conflict/Summary path checks fresh ACL.
  Authorization stamp participates in the note/output transaction, including
  actor, canonical key, ACTIVE role and accessRevision; preflight is insufficient.
- Mutation idempotency is scoped to actor + canonical identity. Stable original
  mutationId/baseRevision/attempt history survives retries. A stale access epoch
  cannot replay under a later re-share. Grant headers never enter fingerprints.
- Share creation seeds the recipient's actor feed with the current note, even if
  owner content did not change. Downgrade/revoke/re-share append independent
  access revision metadata. Feed is authorized at read time; historical payloads
  do not bypass current ACL/protection. Revoked actors receive only safe removal.
- Protected bodies/titles/history remain absent from feeds/events. Protected
  recipients verify the same note password independently and obtain their own
  actor/operation/epoch/expiry grant. Owner grants are not transferable.
- Protection epoch change invalidates every actor's grants. No password travels
  via sharing UI/email/feed/event. Recovery remains the owner's M05 operation.

## Local storage/sync and editor

- Reuse the M05 encrypted account store, staged atomic migration and one M11
  coordinator. Preserve legacy IDs, cursor, outbox IDs/base revisions/retries,
  conflicts and staging. Unknown legacy protection stays quarantined.
- Extend strict codecs compatibly with canonical owner and share access metadata.
  Existing protected vault packets keep their original authenticated binding;
  add canonical owner where needed rather than changing old ciphertext labels.
  Shared notes with duplicate bare IDs must have independent vault/key scopes.
- On learned downgrade/revoke, persist access metadata first, stop only that
  note's pending writes, clear private UI/key/Summary scope and retain encrypted
  draft evidence. Continue owned/other-note queue and pull. Do not promise erasure
  of a disconnected device; enforce access when the client learns the change.
- Re-share gets a new access revision; old blocked writes remain blocked until
  an explicit, freshly authorized review. Conflict local/cloud/later is retained;
  choosing local is still subject to fresh ACL and current base revision.
- Authorized hydration reconciles canonical content without repository.save or
  duplicate outbox entries. Dirty editor/selection stays stable under same pair;
  safe access/protection metadata overrides stale private UI immediately.

## Realtime

- AWS AppSync Events is the chosen signal transport. Enable table streams and
  write durable EVENT relay rows in the same transaction as note/ACL/feed commit.
- Stream relay and failed-delivery recovery use scoped IAM publication, stable
  eventId, leases/idempotency and bounded retry/backoff. Recheck current access
  before fanout; revoked targets can receive an invalidate/removal signal only.
- Cognito ID-token subscribers are restricted to their own sub channel, rejecting
  wildcard/foreign channels. Server IAM publish events contain only identities,
  revisions/invalidation and eventId; never bodies, passwords, grants or email lists.
- Application owns account/session subscription lifetime. Adapter refreshes JWT,
  handles keepalive/reconnect and discards stale-account callbacks. It signals
  existing HTTP cursor sync, including catch-up on reconnect; no second writer.
- Web and Android protocol/integration checks are required. Distinguish local
  protocol tests from a deployed AppSync/Cognito spike; do not claim live success
  from mocks, build success or CloudFormation typecheck.

## Summary

Replace owner-only checks with operation policy while retaining selected canonical
note, content/protection/access revisions, actor-bound grant, consent, saved
snapshot/session/cancellation guards and canonical approved stage lineage. Fresh
ACL applies before provider work and before output commit/release. Learned access
loss cancels the run and clears private output. A raw local input cannot bypass
canonical server note content or a viewer/editor/owner policy.

## Evidence and implementation order

Tier2 graph noteflow-m05 generation 2026-10-02T00:53:31Z. Exact source read:
Note/NoteDto, NoteApplicationService owner gate, LocalNoteState/LocalSyncState,
PendingMutation/SyncNoteSnapshot/SyncConflict, repository save/read and
NoteBundleProjection. Known partial ranges are library headers at line2, read
raw; trace edges around repository.save are heuristic leads, not proof. Existing
backend/sync source reconnaissance and M05 tests establish the accepted baseline.

M06.0 freezes this contract. M06.1 adds domain/composite projection and storage;
M06.2 backend ACL/verified lookup/conditional commits; M06.3 UI/offline access;
M06.4 durable relay + session adapter; M06.5 full Web/Android acceptance. Commit
and push after each completed milestone or criterion; never mark partial work Done.
