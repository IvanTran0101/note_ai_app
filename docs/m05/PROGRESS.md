# M05 — Implementation progress

Updated: 2026-10-02. Scope: **only M05 — Note Security**.

- [Live Notion progress page](https://app.notion.com/p/3ecf9c7a1aa081d5bd92f68f2aa9698f)
- [M05 source plan](https://app.notion.com/p/3e8f9c7a1aa0819bbbded3ee8ff44f32)
- [Planning before code](https://app.notion.com/p/3e6f9c7a1aa080978256eb9e02768c3a)
- [GitHub target](https://github.com/IvanTran0101/note_ai_app/tree/final-tuankiet)
- [Scope and contract record](COLLAB_REVIEW.md)

## Update rule

After each completed Notion milestone `M05.x` or rubric criterion `[M]` / `[P]`,
update this file and Notion, commit only the relevant files, push a normal
fast-forward to `final-tuankiet`, and verify the remote tip. An interrupted
milestone/preparation batch is recorded as partial or awaiting approval.
No milestone or rubric criterion is Done without its acceptance evidence.

Standing authorization recorded on 2026-10-02: the user approved all subsequent
Domain/Infrastructure changes and asked to continue until M05 is complete.
The previous ownership gate is superseded. Remaining gates are technical
implementation and evidence, not repeated permission requests.

## Current milestone status

| Milestone | Status | Remaining acceptance |
| --- | --- | --- |
| M05.0 | Implemented: contracts and baseline dependency alignment recorded | Runtime acceptance remains tracked in later milestones |
| M05.1 | Implemented: protection/metadata contracts, safe DTOs/capabilities and access guard | Runtime wiring continues in backend/storage/UI milestones |
| M05.2 | Backend implemented and pushed: 5edd28d | UI and Summary integration, deployed/runtime acceptance |
| M05.3 | Implemented: encrypted envelope, per-note wrapping and native/Web cutover | Crash/pending/runtime acceptance; UI wiring follows |
| M05.4 | Implemented: scoped sync and authoritative Summary v0.4 lineage | UI and deployed/runtime acceptance in M05.5 |
| M05.5 | In progress: security UI and capability/lifecycle integration | Security UI flows and Web/Android verification matrix |

## Rubric status

The labels/milestone mapping follow the M05 Notion plan. The DTO patch is a
logging improvement only; it does not finish SEC-NFR-01 or note protection.

| Criterion | Level | Milestone | Status |
| --- | --- | --- | --- |
| SEC-FR-01 Enable protection | M | M05.2 | Not complete |
| SEC-FR-02 Per-note password | M | M05.2 | Not complete |
| SEC-FR-03 Unlock before protected operations | M | M05.2 | Not complete |
| SEC-FR-04 Unlock with correct password | M | M05.2 | Not complete |
| SEC-FR-05 Change password | M | M05.2 | Not complete |
| SEC-FR-06 Disable protection | M | M05.2 | Not complete |
| SEC-FR-07 No plaintext password storage | M | M05.2 | Not complete |
| SEC-FR-08 Backend access enforcement | M | M05.2 | Not complete |
| SEC-FR-09 Password confirmation | P | M05.2 | Not complete |
| SEC-FR-10 Current password before change/disable | P | M05.2 | Not complete |
| SEC-NFR-01 Safe representation/no password logs | M | M05.2 | Not complete |
| SEC-NFR-02 API cannot bypass unlock | M | M05.2 | Not complete |
| SEC-NFR-03 Encrypted local cache | P | M05.3 | Not complete |
| SEC-NFR-04 Locked AI | P | M05.4 | Not complete |
| SEC-NFR-05 Session/timeout scope | P | M05.5 | Not complete |

## Preparation batch 01 — M05.0 / Application portion of M05.1

### Changes

- `lib/application/notes/note_application.dart`: `NoteDto.toString()` uses fixed
  `<redacted>` markers for title/content. DTO data/equality/mapping are unchanged.
- `MUST_REMEMBER.md`: records M05-only scope, the ownership gate, Notion page,
  checkpoint/push rule and separate implementation checkout.
- `docs/m05/COLLAB_REVIEW.md`: concrete Domain/Infrastructure file inventory,
  operation/storage/Summary contracts and approval record.
- This progress file: milestone/rubric statuses and continuity record.

Source commit:
[931d7e8](https://github.com/IvanTran0101/note_ai_app/commit/931d7e850b01ca29fb20762de2032a12dc8fac8a).
The batch checkpoint is the documentation commit containing this record.
Notion keeps the final pushed checkpoint SHA and delivery verification.

### Evidence and limits

- Exact target started at `c46498bdc015735be145147b1f81da842e327d6d`;
  Notion baseline is `6ce2afeec8351c224a1c7b1923630336b7b7b3c4`.
  Neither branch is an ancestor of the other. No baseline merge was performed.
- Graph search/trace/snippets and coverage were followed by direct source reads
  for metadata-changed/partial files and source checks in the target checkout.
  The graph is rooted in the original workspace; it is not proof of target
  source or exhaustive security coverage.
- The source diff changes only two diagnostic string literals; patch whitespace
  check passed. Tests, analyzer, build and runtime checks were not run.
- No Domain/Infrastructure source changes are included. `Note.toString()` still
  exposes title; its redaction is pending Domain approval.
- No lock/unlock, encryption, server grant, OTP or security UI is implemented by
  this batch. None of the 15 rubric criteria is marked complete.

### Approaches ruled out

- Wholesale baseline import: unrelated Summary changes include 11 owned
  Infrastructure paths and the target lacks the baseline Summary backend.
- Moving protection policy/crypto into Application to avoid review: violates
  DDD ownership and leaves backend/storage bypasses.
- Marking the DTO fix as a completed security criterion: the plan requires
  backend, storage, lifecycle and verification evidence beyond this fix.

### Next step

M05.1 files touched: Note/NoteProtection/NoteMetadata and metadata repository
boundary; safe NoteDto, NoteAccessCapabilities/access guard, Application operation
checks; LocalNoteState projection and repository mappings. DTOs and outbox
coalescing were split by responsibility to keep the modified files readable.
M05.1 checkpoint pushed as 987e440. M05.2 implemented in source: amplify/protection/
verifier, grant, recovery, DynamoDB transaction adapters and HTTP routes;
sync response masking and current authorization for mutation/replay/conflict/feed.
M05.3 touched: security crypto/device-key/envelope/bundle adapters, vault port,
local/snapshot schema fields, native atomic store and Web CAS. Legacy notes are
quarantined until authoritative online protection metadata; reads/updates serialize
with cutover. Next: M05.3 checkpoint, then
sync/Summary lineage and UI integration.
Complete each milestone/criterion gate before marking Done. Record evidence
and push after each checkpoint; do not stop at an intermediate milestone.

## Continuity receipt

## M05.0 checkpoint — 2026-10-02

- Recorded standing authorization and the concrete security wire/storage/AI
  vocabulary in SECURITY_CONTRACT.md.
- Aligned 39 required baseline production/config/contract paths, preserved DTO
  redaction and the target history; no branch merge or user-file replacement.
- Indexed the actual worktree as `noteflow-m05` (moderate generation
  `2026-10-01T18:44:53Z`). Domain, local-state/store, repository and backend
  integration paths were discovered through the graph; partial library ranges
  were read directly. No exhaustive caller/coverage claim is made.
- `flutter pub get`, patch whitespace check and `dart analyze lib` passed
  (no issues). Backend dependencies were installed. No tests were added/run.
- Next work, already authorized: M05.1 protection/metadata contracts, safe DTOs
  and capabilities; then continue the remaining milestones.

## Continuity receipt (current)

## M05.1 checkpoint — 2026-10-02

- Added pure Domain NoteProtection/NoteMetadata with revision/availability
  invariants and a separate metadata query boundary. Note diagnostics redact
  title; unavailable content cannot be read or changed via the aggregate.
- Mapped protection/content revisions and availability through LocalNoteState,
  repository and NoteDto. Protected list projections omit private content.
- Added provider-neutral access/capability contracts. Application edit/delete
  and Summary fail closed for protected notes without a live access guard;
  Summary rechecks authority before accepting output.
- Split DTO/error projections and repository outbox coalescing into their own
  files; existing retry/idempotency bookkeeping remains in one owner.
- Dart analysis for Domain notes, Application notes and Infrastructure notes
  passed with no issues. Patch whitespace check passed; tests were not run.
- Next: M05.2 backend verifier, scoped grants, recovery and direct API enforcement.

## Continuity receipt (latest)

## M05.3 checkpoint — 2026-10-02

- Added AES-256-GCM account envelopes and password-wrapped random per-note
  keys using vetted cryptography/FSS adapters. Native key reset-on-error is
  disabled; no missing-key regeneration or plaintext fallback for v3 records.
- Sealed complete note/outbox/conflict bundles; locked reads use blank metadata
  and blocked queue placeholders while preserving the original ciphertext and
  mutation identities. Old-epoch ciphertext remains retained after reset.
- Bounded v2 cutover preserves cursor, IDs, queue order and bookkeeping. Unknown
  protection is quarantined inside the encrypted device envelope until canonical
  online metadata is known. Legacy staging is atomically sealed in place,
  preserving its complete original document rather than deleting drafts.
- Native commits use process serialization, OS file lock, flushed ciphertext
  temporary files and same-directory atomic rename. Web uses encrypted CAS in a
  single IndexedDB transaction and database v2 to fence old v1 writers.
- Lock/account generation changes discard transient keys and reject late reads;
  app disposal clears the vault. Android backup disabled for this private store.
- `dart analyze lib` passed with no issues. Patch whitespace check passed.
  No test/runtime/crash/device acceptance was run; sync/Summary/UI wiring follows.

## M05.2 checkpoint — 2026-10-02

- Added server-side Argon2id verifier, random hashed scoped grants, bounded
  password attempts and one-note mailbox OTP recovery with atomic consumption.
- JWT-protected content/protection routes; owner-only initial ACL, stable safe
  failures, grant header and CORS. Missing SES sender fails closed. Configure
  verified `noteSecuritySender` CDK context before deployment; no deployment made.
- Epoch cutovers write canonical note and change feed atomically. Sync write,
  delete, replay/conflict and historical feed projection use current authority;
  protected writes condition epoch and live grant in the same transaction.
- Split sync models/serialization from the DynamoDB adapter; added TTL only to
  transient security rows, never as the authority for expiry.
- `npm run typecheck` and `git diff --check` passed. No tests/runtime performed.
  Flutter UI, encrypted storage and Summary lineage are the following milestones;
  full rubric acceptance remains pending their integration/runtime evidence.

| Record | Resolution |
| --- | --- |
| `MUST_REMEMBER.md` | Updated with user scope, permission and checkpoint rules |
| `docs/m05/COLLAB_REVIEW.md` | Updated scope and contracts record |
| `docs/m05/PROGRESS.md` | Updated milestone evidence and next step |
| Notion progress page | Created; updated with delivery receipt after push |
| `_agent_ops/` records | Not applicable: directory/tools/closure template absent; no records fabricated |

## M05.4 checkpoint — 2026-10-02

- Added provider-neutral security actions and transient private HTTP grants;
  online/offline unlock remain separate. Session/expiry invalidation clears keys,
  grants and Summary scopes without deleting encrypted pending mutations.
- Each sync attempt/retry/response checks session and operation scope; security
  denial blocks only its note and lets other notes/pull continue. Authorized
  hydration has no save/outbox side effect. Reconciliation preserves protection
  fields and pending bookkeeping, rejects stale cache and guards conflict cloning.
- Summary v0.4 binds canonical owner/note/content+protection revision, random run
  and contiguous UTF-16 sections. Conditional stage reservation and approved
  outputs enforce merge lineage. Authorization runs before quota/provider/output;
  output commit conditions canonical revision/epoch/live grant.
- Recovery resolves mailbox using Cognito GetUser for access tokens and checks
  returned subject. Root wires guard, sync observers, private proofs and Summary.
- Dart analysis, backend typecheck and whitespace check are source/static evidence.
  No tests, app runtime, provider invocation or deployment performed.

Next: M05.5 security forms, locked views, live capabilities and UI lifecycle clearing.

M05.4 source checkpoint: `9dd2f65`. A trailing blank line reported during staging
was normalized immediately in the documentation delivery follow-up. No source
behavior changed; final whitespace check is clean.
