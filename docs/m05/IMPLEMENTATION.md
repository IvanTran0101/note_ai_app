# M05 — Implementation and acceptance evidence

Scope: M05 only. Updated 2026-10-02. All six milestones are implemented in
source. Source and automated runtime evidence are recorded below and in PROGRESS.md.
Live deployed API/mailbox/provider delivery is outside this acceptance.

## Rubric mapping

| Criterion | Level | Implementation evidence |
| --- | --- | --- |
| SEC-FR-01 Enable protection | M | Security dialog → NoteSecurityActions.enable; local seal before conditional backend protection/feed cutover; completion requires both sides |
| SEC-FR-02 Per-note password | M | Argon2id verifier and salt per canonical owner/note; random per-note DEK with password wrapping, separate grants and attempt counters |
| SEC-FR-03 Unlock before operations | M | NoteApplicationService, live capabilities, repository write guards, scoped mutation/replay/conflict guards, metadata-only feed/list/history; separate authorized content |
| SEC-FR-04 Correct password unlock | M | Server verifier plus authorized local unwrap/hydration; explicit offline unwrap never creates server authority |
| SEC-FR-05 Change password | M | Current-password verification, conditional epoch update, local rewrap, old grant invalidation and fresh unlock |
| SEC-FR-06 Disable protection | M | Current-password and manage scope; server cutover and local vault transition; stale UI reloaded |
| SEC-FR-07 No plaintext password storage | M | Password strings exist only during calls/forms; persisted server verifier is salted Argon2id; local wrapping stores salt/AEAD packets |
| SEC-FR-08 Backend enforcement | M | Cognito JWT + current ACL + scoped grant/epoch/expiry, conditional writes; no client unlock boolean is authority |
| SEC-FR-09 Confirmation | P | Enable/change/recovery forms and Application check password confirmation before changes |
| SEC-FR-10 Current password | P | Change/disable verify the current password server-side; an existing grant alone cannot change it |
| SEC-NFR-01 Safe representation/logs | M | Domain/DTO diagnostics redacted, fixed error codes, no password/grant/provider payload logging; random grants persisted as hashes |
| SEC-NFR-02 No API bypass | M | Direct protected content/mutation/delete/retry/replay/history/conflict/Summary paths enforce current authority; protected generic responses are metadata-only |
| SEC-NFR-03 Encrypted local cache | P | AES-256-GCM account envelope, password-wrapped per-note DEKs, note/outbox/conflict bundles, bounded v2 cutover, native atomic rename and Web CAS; retained ciphertext on recovery |
| SEC-NFR-04 Locked AI | P | Live Application/Summary guards, immutable run scope, canonical v0.4 note/revision/stage lineage, checks before provider and authorized release; lock clears UI output and rejects late results |
| SEC-NFR-05 Scope/timeout | P | 15-minute unlock, session/account/protection epoch scopes, background/lock/logout invalidation; generation fences across reads, writes, sync and UI |

All rows have source implementation and passed scoped automated acceptance.
See PROGRESS.md for platform results and the separate live deployment limits.

## UI integration

- Note detail has enable, unlock, lock, change, disable and owner OTP recovery
  controls with Vietnamese/English copy. Password fields are obscured, bounded,
  transient and cleared after completion/failure/disposal. Recovery has resend,
  OTP/expiry validation and the old encrypted pending-work limitation.
- Protected lists/dashboard/conflict chooser never render title/body or private
  semantics, even while a note is unlocked. The detail editor reads content
  through Application and becomes read-only when edit authority is absent.
- Lock/expiry/session changes clear editor controllers, Summary output and
  presentation caches. Context generations reject late saved DTOs and results.
  Current protection metadata also rejects stale unprotected DTOs after enable.
- Sync presentation keeps metadata, not decrypted protected payloads. Conflict
  commands reread full current state with live authority; cloning/copy paths
  require export scope and fail closed when no export integration exists.
- Durable local notes/outbox/conflicts survive locking and recovery as ciphertext.
  Unsaved text that has not reached a successful save is not claimed durable;
  the explicit lock control saves dirty edits first. Existing autosave remains.

## Configuration for the separate deployment step

- Deploy the scoped backend normally after project authorization. The Summary
  Lambda receives NOTES_TABLE_NAME and quota-table name from composition. It has
  canonical GetItem/run-row PutItem/conditional authority permissions; no scan.
- Set verified SES sender through CDK context `noteSecuritySender`. Recovery is
  unavailable when no sender is configured; no fallback email/password bypass.
- Use the configured Cognito access-token session and HTTPS sync/Summary endpoints.
  Grants stay in private adapter memory and X-Note-Unlock-Grant headers, never
  URLs/DTOs/outbox. Offline unlock only opens this device's encrypted cached note.
- Summary v0.4 requires note identity, saved content/protection revisions, run ID
  and stage offsets. Old v0.3 fixtures/checkers are historical and not acceptance.
- Summary has a whole-request bound of at most 26 seconds, under Lambda's 28;
  the provider gets at most 15 seconds with 9 seconds reserved for reauthorization
  and release. Authority reads are individually bounded; timeout fails closed.

## Evidence limits

VM and Chrome app suites, Android and real-browser-plugin integration, backend
policy/transaction checks and static checks passed. See PROGRESS.md for exact
counts. UI security gateways and backend AWS/SES/provider calls use test doubles;
real AES/PBKDF, Argon2id, IndexedDB and Android key/file adapters were exercised.
No live provider call, OTP mail or backend deployment was performed. Tests cannot
prove absence of every possible bug; the listed runs have no observed failures.
