# MUST REMEMBER

Read this file at the start of every turn that may change source code. Then read
the current `AGENTS.md`, inspect `git status` and the active branch, and confirm
the codebase-memory index before structural code discovery. Begin the M05
implementation only within the scope the user has approved below.

## Approved direction

- Work on **only Module M05 — Note Security**, using the reviewed baseline
  `Final-here-do-not-merge-main@6ce2afeec8351c224a1c7b1923630336b7b7b3c4`.
- The user selected the plan's recommended Option A for all three open M05
  decisions:
  1. Use a bounded local schema v2→v3 migration, split protected metadata from
     content, preserve IDs/cursor/outbox/conflicts, and use staged atomic commit.
     Never silently reset data, keep a plaintext rollback, or leave plaintext
     protected data after successful migration.
  2. Use vetted KDF/AEAD and key-lifecycle adapters. Email password reset does
     not recover a key derived from a note password; retain unrecoverable
     ciphertext and explain that tradeoff clearly.
  3. Make Summary note-aware: carry `noteId`, revision,
     `protectionRevision`, and the scoped grant through authorized stages.
     The backend validates authorization before provider work and before
     releasing results. Preserve existing consent, session, snapshot, and
     cancellation guards.
- The user has approved starting M05 and committing/pushing its scoped changes
  to `final-tuankiet`. After each completed Notion milestone `M05.x` or rubric
  criterion `[M]` / `[P]`, update the progress page and local progress record,
  then commit and push. A preparation batch or interrupted milestone must be
  recorded as partial / awaiting review, never as Done.
- **Ask for collab permission before changing Domain or Infrastructure.** This
  restriction comes directly from the user. Record proposed and approved paths
  in `docs/m05/COLLAB_REVIEW.md`; include backend persistence/crypto adapters.
  Approval of Option A does not grant permission to edit these owned layers.
- Keep every push limited to M05. Do not merge, force-push, or deploy without
  separate authorization. Do not implement M06/M09/M07 business features.

## Security contract

- A protected note has its own password. Passwords are transient; never log or
  include them in DTOs, errors, analytics, URLs, cache, or outbox.
- Unlock grants are random opaque capabilities scoped to user `sub`, `noteId`,
  `protectionRevision`, allowed operations, and expiry. Every request still
  requires the Cognito JWT and a fresh ACL check. Never persist/log a raw grant
  or put one in a URL, cache, or outbox.
- The sync change feed must not disclose a locked note's title, body, or history.
  Protected content uses a separately authorized path. Protected mutation,
  delete, replay, conflict, and Summary paths must enforce the same grant scope.
- This is app-level protection, not end-to-end encryption. Do not replace
  Cognito or expand M05 into M06/M07/M08/M11 implementation.
- A previously identified independent issue is `NoteDto.toString()` exposing
  title/content. Recheck it on the active branch; the latest workspace snapshot
  is clean at the baseline commit, so do not assume the earlier uncommitted
  redaction exists.

## DDD and layer rules

- Dependency direction: `Presentation → Application → Domain`.
  `Infrastructure` implements inward Domain/Application ports. `main.dart` is
  the composition root and only wires dependencies.
- Domain owns business concepts, invariants, aggregates, and inward contracts.
  It must not depend on Flutter, HTTP, databases, provider SDKs, filesystems,
  FFI, or platform APIs. The aggregate owns its own invariants; repositories
  persist/query and do not decide business policy.
- Application owns use-case orchestration, authorization coordination, DTOs,
  and session coordination; it stays provider-neutral and contains no widgets
  or concrete infrastructure.
- Infrastructure owns adapters, serialization, storage, crypto, network, and
  provider/platform details. Presentation owns UI state, navigation, semantics,
  and user-facing copy; it calls Application, never Infrastructure directly.
- Map models at layer boundaries. Do not put provider/database DTOs in Domain.
  Add abstractions only for meaningful boundaries or clear test value. Keep
  changes small and avoid unrelated refactors or generated/native files.

## Workflow and current workspace snapshot

- For code discovery, use codebase-memory in this order: `search_graph`,
  `trace_path`, `get_code_snippet`, then `check_index_coverage` for every source
  path relied on. Read missed/partial source ranges directly and qualify claims.
- The current checkout is `Final-here-do-not-merge-main` at `6ce2afe`; the prior
  `codex/m05-note-dto-redaction` branch is not present in the current checkout.
  Current untracked user data: `.playwright-cli/` and `final_project.md`; preserve
  both. Recheck status before each change.
- The implementation checkout is a managed worktree at
  `C:/Users/meow/.codex/worktrees/m05-final-tuankiet/note_ai_app-note-ai-app`,
  branch `codex/m05-final-tuankiet`, initially based on
  `origin/final-tuankiet@c46498bdc015735be145147b1f81da842e327d6d`.
  Push normal fast-forwards to `HEAD:refs/heads/final-tuankiet` and verify the
  remote commit after each push. Recheck the remote before writing/pushing.
- The target and Notion baseline diverge (101 target-only / 5 baseline-only
  commits at the initial inspection). Their tree diff includes 11 Infrastructure
  paths. Do not wholesale import that diff; baseline dependency alignment needs
  collab review. Verify actual source in the target worktree before each patch;
  the existing code graph indexes the original workspace, not this worktree.
- `_agent_ops/` and its `session_start.py` are absent in this checkout, despite
  references from `AGENTS.md`; do not assume those tools or records exist.
- Do not add or run tests unless the user explicitly asks for testing or
  verification. Do not remove, overwrite, or stage unrelated/untracked files.

## Progress and approval checkpoint

- [M05 progress page](https://app.notion.com/p/3ecf9c7a1aa081d5bd92f68f2aa9698f)
- Read `docs/m05/PROGRESS.md` and `docs/m05/COLLAB_REVIEW.md` in the
  implementation checkout before continuing M05. Keep both current.
- Initial batch: Application DTO redaction plus review/progress documents.
  M05.0 is pending contract acceptance; M05.1 is partial. No rubric criterion is
  Done. Domain/Infrastructure permission has not been granted.
- `_agent_ops/` records and the closure receipt template are unavailable. Use
  the actual M05 progress files for continuity; do not fabricate absent records.

## Source pages

- [DDD conventions](https://app.notion.com/p/3e6f9c7a1aa0805f833fd3b618131eee)
- [Planning before code](https://app.notion.com/p/3e6f9c7a1aa080978256eb9e02768c3a)
- [M05 Note Security plan](https://app.notion.com/p/3e8f9c7a1aa0819bbbded3ee8ff44f32)
- [Project AGENTS.md](https://app.notion.com/p/3e6f9c7a1aa080d097f9f281bc352e68)
