# M05 — Domain / Infrastructure review request

Date: 2026-10-02. Status: **permission pending; proposed changes only**.
The user requires collab permission before editing Domain or Infrastructure.
Selecting Option A approved the direction, not access to these owned files.

Sources:

- [M05 implementation plan](https://app.notion.com/p/3e8f9c7a1aa0819bbbded3ee8ff44f32)
- [Planning before code](https://app.notion.com/p/3e6f9c7a1aa080978256eb9e02768c3a)
- [Progress](https://app.notion.com/p/3ecf9c7a1aa081d5bd92f68f2aa9698f)

## Immediate request: M05.1 Domain contract

These are the three proposed Domain paths for the next milestone. No Domain
patch has been applied. An approval must identify the permitted paths/scope.

| Path | Proposed responsibility | Review invariant |
| --- | --- | --- |
| `lib/domain/notes/note_protection.dart` (new) | Immutable protection state and protection revision; safe metadata contract | No password, verifier, raw grant, key material, crypto SDK, HTTP, Flutter or database dependency |
| `lib/domain/notes/note.dart` | Aggregate protection state, compatible creation/reconstitution, explicit state transitions; redact title in `toString()` | Aggregate owns valid transitions; preserve canonical identity and timestamps; never infer server authorization from a local flag |
| `lib/domain/notes/note_repository.dart` | Reviewed boundary for safe metadata and separately authorized content | Repository persists/queries; it does not decide ACL, password or unlock policy; concrete adapter changes require separate permission |

Application will map these contracts to safe DTOs/capabilities. UI receives
capabilities and locked metadata; raw server grants remain transient behind the
Application boundary. A protected metadata projection must omit title/body,
even when another screen has unlocked content. Existing plaintext notes are not
silently reclassified as protected notes.

The completed Application-only DTO redaction is independent of this request.
It does not implement protection or complete M05.1 / SEC-NFR-01.

## Later protected changes from the Notion plan

This inventory gives advance notice. It is not permission to edit any path.
Recheck current source and obtain scoped approval before each affected batch.

### M05.2 — password verifier, grants and recovery

- New backend adapters: `amplify/protection/dynamo_protection_store.ts`,
  `amplify/protection/argon2id_password_hasher.ts`.
- Proposed inward backend boundaries/use cases: `amplify/protection/handler.ts`,
  `use_cases.ts`, `protection_store.ts`, `password_hasher.ts`.
- Existing backend integration: `amplify/backend.ts`,
  `amplify/sync/handler.ts`, `amplify/sync/dynamo_sync_store.ts`,
  `amplify/sync/sync_response.ts`.
- HTTP adapter: new `lib/infrastructure/notes/http_note_protection_gateway.dart`.

Backend storage/crypto and sync integration are explicitly in the review scope;
placing them outside `lib/infrastructure/` does not bypass the ownership gate.

### M05.3 — encrypted storage and bounded migration

Existing Infrastructure paths:

- `lib/infrastructure/notes/note_repository.dart`
- `lib/infrastructure/sync/local_note_state_codec.dart`
- `lib/infrastructure/sync/pending_mutation_codec.dart`
- `lib/infrastructure/sync/sync_conflict_codec.dart`
- `lib/infrastructure/sync/local_sync_codec_schema.dart`
- `lib/infrastructure/sync/local_sync_store_io.dart`
- `lib/infrastructure/sync/local_sync_store_web.dart`

New adapters: `lib/infrastructure/sync/local_security_migration.dart` and
`lib/infrastructure/sync/protected_state_codec.dart`. Crypto/key lifecycle
adapter filenames and library parameters need owner review before creation.

### M05.4 — sync and Summary authorization

- `lib/infrastructure/sync/http_remote_note_data_source.dart`
- `lib/infrastructure/sync/sync_http_mapper.dart`
- `lib/infrastructure/note_intelligence/summary_http_gateway.dart`
- `lib/infrastructure/note_intelligence/summary_request_policy.dart`
- `lib/infrastructure/note_intelligence/summary_http_mapper.dart`
- `lib/infrastructure/note_intelligence/summary_run_runtime.dart`
- `amplify/ai/summary_contract.ts`, `amplify/ai/summary_handler.ts`
- `docs/summary_api_contract.md` and matching client/parser/wire fixtures

Some Summary paths are missing on the target branch; see baseline alignment.
M05 will add protection contracts to collab-owned flows, not implement M06,
M07, M08 or M09 business modules.

## Contracts to accept

### Identity, operations and grant lifecycle

- Canonical identity is owner + noteId unless M11 guarantees global note IDs.
  JWT actor `sub` is distinct from note owner.
- Owner manages protection, password, reset and delete. Owner/editor can edit;
  viewer read depends on current ACL. Summary/export/attachment operations need
  their own allowed operation and existing consent/ACL contracts.
- Server stores a salted Argon2id verifier, not plaintext password. Unlock
  produces a random opaque grant of at least 256 bits; only its hash is stored.
- Grant binds actor, canonical note, protection revision, operation set and
  expiry. Check server clock plus current JWT/ACL on every request, including
  retry/replay/conflict and before releasing content or AI output.
- `X-Note-Unlock-Grant` and 15-minute server-configured TTL are plan proposals
  awaiting wire/runtime acceptance. Raw grant is never in URLs, DTOs, durable
  cache, outbox, errors or logs. Offline unlock does not mint a server grant.
- Password change/reset/disable revokes the target note epoch. OTP requires a
  verified owner-mailbox challenge with bounded TTL/attempts and atomic consume.
  Reset cannot decrypt old unsynced drafts with an unavailable old key; retain
  their ciphertext and show the recovery limitation.

| Operation | Required actor/authority | Protection requirement |
| --- | --- | --- |
| Enable / change / disable | Owner + current ACL; verify current password when applicable | Explicit confirmation, local sealing and server state must both be safe |
| Unlock / content read | Current read ACL | Password proof issues a read-scoped grant; separate content hydration |
| Edit / delete / replay / conflict | Current operation ACL | Current note epoch and operation grant, checked on each attempt |
| Summary / export / attachments | Current operation ACL and required consent | Explicit operation scope; Summary stage/lineage and output reauthorization |
| Protected feed / history | Current metadata ACL | Metadata-only; omit private title, body and old snapshots |
| Owner email recovery | Owner + proven mailbox challenge | One-note reset; preserve unrecoverable encrypted pending data |

### M11 storage/sync acceptance

- Bounded schema v2 to v3 migration freezes reads/writes/AI/sync for cutover.
  Encrypt notes, pending payloads, conflicts, previews and temporary/staging
  copies. Preserve namespace, IDs, cursor, mutationId, baseRevision, timestamps,
  tombstones and pending/conflict status.
- Native atomic replacement and IndexedDB transaction ownership need review.
  Migration failure stays locked/blocked; no reset, reseed, plaintext fallback
  or plaintext rollback. Unknown legacy protection must use an approved
  quarantine policy, not a claim of password protection.
- Authorized content hydration uses reconciliation, not repository save, so
  it does not create a new mutation/outbox entry. A locked/denied note blocks
  its encrypted pending work while other notes and pull can continue.
- Logout/expiry/account switch clear keys, grants, content and AI memory while
  retaining encrypted pending data. Reconnect requires fresh server authority.

### M07/M06 handoff acceptance

- Summary request/parser/docs version changes together. Authorize note snapshot
  before quota/provider work, bind run/section lineage to note and revisions,
  validate merge inputs and authorize again before output. Preserve consent,
  snapshot, session and cancellation guards; discard stale results after lock.
- M06 supplies current share ACL/canonical owner identity. M05 must not assume
  registration proves email verification or implement sharing business logic.
- These are owner contract/acceptance gates. The selected A direction remains
  fixed; there is no new A/B design decision in this request.

## Baseline alignment before Summary integration

Initial checked refs:

- Notion baseline: `Final-here-do-not-merge-main@6ce2afeec8351c224a1c7b1923630336b7b7b3c4`.
- Push target before this batch: `final-tuankiet@c46498bdc015735be145147b1f81da842e327d6d`.
- History diverged: 101 target-only / 5 baseline-only commits; tree diff 116
  paths. Domain trees match, but Infrastructure differs in 11 paths.
- The baseline has `amplify/ai/summary_contract.ts` and the remote Summary
  adapters; the initial target does not. Do not merge the whole baseline to
  satisfy a dependency. Owners must accept the exact prerequisite patch first.

The 11 Infrastructure paths in that initial baseline diff are:

1. `lib/infrastructure/configuration/summary_runtime_configuration.dart`
2. `lib/infrastructure/note_intelligence/note_summary_resource_policy.dart`
3. `lib/infrastructure/note_intelligence/remote_summarization_service.dart`
4. `lib/infrastructure/note_intelligence/summary_api_failure.dart`
5. `lib/infrastructure/note_intelligence/summary_chunk_splitter.dart`
6. `lib/infrastructure/note_intelligence/summary_failure_mapper.dart`
7. `lib/infrastructure/note_intelligence/summary_http_call.dart`
8. `lib/infrastructure/note_intelligence/summary_http_gateway.dart`
9. `lib/infrastructure/note_intelligence/summary_http_mapper.dart`
10. `lib/infrastructure/note_intelligence/summary_request_policy.dart`
11. `lib/infrastructure/note_intelligence/summary_run_runtime.dart`

This alignment is a later prerequisite to M05.4, not authority to import M07.

## Evidence and limits of the preparation batch

Tier 2 graph project: `D-kiet-hk7-flutter-midterm-note_ai_app-note-ai-app`,
generation `2026-10-01T18:10:20Z`, rooted in the original baseline checkout.
Coverage reported metadata changes on all inspected paths, partial parsing
on local note codec line 2 and local schema line 6. Those source ranges and
the relevant methods were read directly; target source was checked separately.
No graph completeness, caller completeness or runtime security claim is made.

Confirmed source findings:

- `NoteDto.toString()` interpolated title/content on both refs. The only source
  patch in this preparation batch replaces those with fixed redaction markers.
- `Note.toString()` exposes title, not body; this remains pending Domain review.
- Local note codec writes title/content fields; local schema declares version 2.
- `DynamoSyncStore.applyMutation()` has recorded-result and conflict returns;
  both are explicit protection review points. `listChanges()` returns snapshots,
  and `noteBodyOf()` projects title/content onto the wire.
- On the baseline, `parseSummaryBody()` rejects unknown request fields and
  returns stage/inputs after consent validation. It is absent on the initial
  target. Adding noteId client-side alone is not a valid integration.

These checks are bounded source evidence. Tests/build/runtime were not run.
Full milestone acceptance still requires the Notion verification matrix.

## Approval record

| Scope | Status | Evidence |
| --- | --- | --- |
| Application DTO + progress/review files; push to final-tuankiet | Authorized | Direct user request in this conversation |
| M05.1 three Domain paths above | Pending | No collab permission received |
| Infrastructure/backend adapter batches | Pending | No collab permission received |
| Baseline Summary prerequisite patch | Pending | No collab permission received |

Next: receive scoped collab approval for M05.1, record it here, then implement
the approved contracts and map/wire permitted Application changes. Do not edit
protected files or mark a milestone Done before its gate is satisfied.
