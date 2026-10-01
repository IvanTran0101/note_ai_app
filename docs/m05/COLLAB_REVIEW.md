# M05 — Scope and contract record

Updated: 2026-10-02.

## Current authorization

The user explicitly approved all Domain/Infrastructure changes from this point
on, including future batches, and requested implementation through completion.
This supersedes the original ownership restriction. Do not ask again, require
path-by-path permission, or stop work because of the historical review request.
The task remains only M05; preserve DDD boundaries and existing user data.

## Accepted direction

- Bounded schema v2→v3 migration; metadata/content separation; preserve
  namespace, IDs, cursor, outbox, mutation IDs, base revisions and conflicts.
- Vetted KDF/AEAD adapters, transient key/grant lifecycle, encrypted offline
  cache and drafts. No plaintext rollback/reset/fallback.
- Email OTP is a one-note owner recovery flow. It does not recover an old
  password-derived key: retain unrecoverable unsynced ciphertext.
- Summary binds canonical note identity, content/protection revisions and grant
  to each stage/run; authorize before provider work and before output release.
- Cognito JWT and current ACL remain mandatory. This is app-level protection.

## Implementation contracts

### Domain / Application

- Canonical identity is owner + noteId; JWT actor is distinct from owner.
- Domain NoteProtection and safe metadata have no password/verifier/grant/key
  fields, Flutter, HTTP, SDK, database or filesystem dependency.
- Aggregate owns valid protection transitions; repositories persist/query.
- Application owns unlock/use-case/session orchestration and safe capabilities.
  UI never receives a raw grant. Protected feed metadata omits title/body.
- Redact both NoteDto and Note diagnostics.

### Backend

- Salted Argon2id verifier per canonical note; never store plaintext password.
- Opaque random grants of at least 256 bits, hashed server-side, bound to actor,
  canonical note, protection revision, operation set and expiry.
- Use X-Note-Unlock-Grant and a configurable 15-minute TTL. Validate server
  time/current JWT/ACL on every request and again before output/commit.
- Owner manages protection/password/reset/delete. Read/edit/Summary operations
  require current ACL and operation scope. Retry/replay/conflict are authorized.
- Mailbox OTP challenge has bounded attempts/TTL, hashed secret and atomic consume.

### Storage / sync

- Freeze reads/writes/AI/sync during cutover; encrypt notes/pending/conflicts and
  staging data with authenticated encryption. Preserve all sync identity/state.
- Native atomic cutover and IndexedDB transactions; failures stay blocked.
- Offline unlock unwraps a local DEK; it never mints server authority. Clear
  memory keys/grants/content/AI on lock/logout/expiry/account switch.
- Hydration reconciles without save/outbox duplication. A denied note keeps its
  encrypted pending work while unrelated notes can continue syncing.
- Protected feed/history always metadata-only; content is separately authorized.

### Summary and existing module integration

- Keep request/parser/docs versions aligned. Reject arbitrary or stale inputs;
  bind server-approved run/sections to note and revisions. Preserve consent,
  snapshot/session/cancellation guards and discard late results after lock.
- Align required existing Summary baseline code as a dependency, preserving the
  target branch and M05 diagnostic patch. Do not implement unrelated modules.
- Existing share ACL/attachment/export owners retain their business flows; M05
  adds access boundaries and fails closed where a protected operation is absent.

## Initial evidence

Notion baseline: Final-here-do-not-merge-main@6ce2afe.
Initial target: final-tuankiet@c46498b; preparation checkpoint: d60066b.
The histories diverge. Summary client/backend dependencies existed on the
baseline and were absent on the initial target. The initial graph was rooted
in the baseline; coverage gaps were read directly and target source verified.

The preparation batch redacted Application DTO diagnostics only. Domain title
redaction, backend grants, encryption, migration and UI were not yet implemented.
Those historical limits are recorded in PROGRESS.md; current milestone status
is maintained there and on the Notion progress page.

## Sources and continuity

- MUST_REMEMBER.md: session entrypoint and persistent user instructions.
- PROGRESS.md: milestone/criterion status, evidence and next step.
- https://app.notion.com/p/3e8f9c7a1aa0819bbbded3ee8ff44f32: M05 plan.
- https://app.notion.com/p/3e6f9c7a1aa080978256eb9e02768c3a: planning context.
- https://app.notion.com/p/3ecf9c7a1aa081d5bd92f68f2aa9698f: progress page.

## Source delivery — M05.0 through M05.5

Backend, local encryption/migration, scoped sync/Summary and security UI are now
implemented. Criterion/path mapping and deployment prerequisites are recorded in
IMPLEMENTATION.md. Static/build evidence and remote checkpoints live in PROGRESS.md
and the Notion progress page. Deployed/runtime acceptance is still outstanding.
