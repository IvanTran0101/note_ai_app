# M05 — Implementation progress

Updated: 2026-10-02. Scope: **only M05 — Note Security**.

- [Live Notion progress page](https://app.notion.com/p/3ecf9c7a1aa081d5bd92f68f2aa9698f)
- [M05 source plan](https://app.notion.com/p/3e8f9c7a1aa0819bbbded3ee8ff44f32)
- [Planning before code](https://app.notion.com/p/3e6f9c7a1aa080978256eb9e02768c3a)
- [GitHub target](https://github.com/IvanTran0101/note_ai_app/tree/final-tuankiet)
- [Protected-layer review request](COLLAB_REVIEW.md)

## Update rule

After each completed Notion milestone `M05.x` or rubric criterion `[M]` / `[P]`,
update this file and Notion, commit only the relevant files, push a normal
fast-forward to `final-tuankiet`, and verify the remote tip. An interrupted
milestone/preparation batch is recorded as partial or awaiting approval.
No milestone or rubric criterion is Done without its acceptance evidence.

Domain and Infrastructure permission is still pending. The user's explicit
ownership restriction takes priority over the general authorization to code
M05. Receive and record scoped permission before touching those paths.

## Current milestone status

| Milestone | Status | Remaining acceptance |
| --- | --- | --- |
| M05.0 | Preparation recorded; contracts awaiting owner acceptance | M11/M07/M06 contract acceptance and reviewed Summary prerequisite alignment |
| M05.1 | Partial: Application DTO redaction implemented | Domain NoteProtection/safe metadata/capabilities, Domain log redaction, mapping/wiring and acceptance |
| M05.2 | Not implemented | Verifier/grant/OTP and every protected operation authorized |
| M05.3 | Not implemented | Full encrypted envelope, atomic v2→v3 migration, Web/native key lifecycle and crash/pending evidence |
| M05.4 | Not implemented | Metadata feed/content split, mutation/replay/conflict, Summary lineage and stale result rejection |
| M05.5 | Not implemented | Security UI flows and Web/Android verification matrix |

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

Collab reviews the three immediate M05.1 Domain paths in `COLLAB_REVIEW.md`.
After explicit permission is recorded, implement their approved contracts and
Application mapping/wiring; request scoped Infrastructure permission before
adapter integration. Complete each milestone/criterion gate before marking Done.

## Continuity receipt

| Record | Resolution |
| --- | --- |
| `MUST_REMEMBER.md` | Updated with user scope, permission and checkpoint rules |
| `docs/m05/COLLAB_REVIEW.md` | Created with paths/contracts and pending approvals |
| `docs/m05/PROGRESS.md` | Created with honest partial status and next step |
| Notion progress page | Created; updated with delivery receipt after push |
| `_agent_ops/` records | Not applicable: directory/tools/closure template absent; no records fabricated |
