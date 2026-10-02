# MUST REMEMBER

Read this file at the start of every turn that may change source code. Then read
the current `AGENTS.md`, inspect `git status` and the active branch, and confirm
the codebase-memory index before structural code discovery. Begin the M05
implementation only within the scope the user has approved below.

## Approved direction

- Finish **M05 — Note Security** first, using the reviewed baseline
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
- **Standing authorization, 2026-10-02:** the user approved all Domain and
  Infrastructure changes from now on, including backend persistence/crypto
  adapters and M05 integration prerequisites. Do not ask again or stop for the
  superseded ownership gate. Continue until M05 is implemented. Keep ordinary
  DDD boundaries, scoped progress/pushes and data-preservation rules.
- Keep each push limited to the active Notion module (M05 first; M06 only
  after M05 acceptance). Do not merge, force-push, or deploy without
  separate authorization. New user instruction on 2026-10-02 authorizes full
  M05 testing/fixes on Chrome and Android, marking verified Notion checkboxes,
  then implementing/testing M06 with the same checkpoint workflow after M05
  passes. Do not start M06 source changes while M05 failures remain. Other
  modules remain outside scope.

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
- Current primary checkout: D:/kiet/hk7/flutter/midterm/note_ai_app-note-ai-app,
  branch final-tuankiet. Use graph noteflow-final-d and R: short-path alias.
  The former C: implementation and merge worktrees were archived/removed per
  user request. Keep .playwright-cli/ and final_project.md untracked and unchanged.
  Normal fast-forward push to HEAD:refs/heads/final-tuankiet; verify remote SHA.
- Historical baseline divergence and M05 alignment are recorded in docs/m05;
  do not return to the old checkout or recreate C: worktrees.
- `_agent_ops/` and its `session_start.py` are absent in this checkout, despite
  references from `AGENTS.md`; do not assume those tools or records exist.
- Testing is now explicitly authorized (2026-10-02): run the suites and Chrome/
  Android flows, add scoped regression coverage and fix confirmed failures.
  Do not remove, overwrite, or stage unrelated/untracked files.

## Progress and approval checkpoint

- [M05 progress page](https://app.notion.com/p/3ecf9c7a1aa081d5bd92f68f2aa9698f)
- Read `docs/m05/PROGRESS.md` and `docs/m05/COLLAB_REVIEW.md` in the
  implementation checkout before continuing M05. Keep both current. M05 automated acceptance passed on VM/Chrome and real
  Android/Web-plugin integration; see the final acceptance table for scope.
  Continue with M06 only, following its Notion plan and the same per-milestone
  progress, test/fix, checkbox and fast-forward push workflow.
- M05.0–M05.5 are now implemented in source, including backend, encrypted
  storage/migration, scoped sync/Summary and security UI, and passed automated
  runtime acceptance. Read current progress and IMPLEMENTATION.md for evidence
  and separate live deployment limits.
  Keep reading this file before future coding turns; do not reopen settled choices.
- `_agent_ops/` records and the closure receipt template are unavailable. Use
  the actual M05 progress files for continuity; do not fabricate absent records.

## Source pages

- [DDD conventions](https://app.notion.com/p/3e6f9c7a1aa0805f833fd3b618131eee)
- [Planning before code](https://app.notion.com/p/3e6f9c7a1aa080978256eb9e02768c3a)
- [M05 Note Security plan](https://app.notion.com/p/3e8f9c7a1aa0819bbbded3ee8ff44f32)
- [Project AGENTS.md](https://app.notion.com/p/3e6f9c7a1aa080d097f9f281bc352e68)

- [M06 Sharing & Real-time Collaboration plan](https://app.notion.com/p/3e8f9c7a1aa08193b4f9d1fbf42999ed)

## Active module — M06

M05 automated acceptance is complete and pushed at 22587a5; 15 Notion rubric
boxes are ticked. M06 is now authorized. Read docs/m06/CONTRACT.md and PROGRESS.md
before continuing. Notion progress: https://app.notion.com/p/3edf9c7a1aa0817fb5fedd1e18b52ab2.
Share ACTIVE to verified sub, owner+note pair identity, viewer/editor policy,
fresh server ACL/conditional commit, separate M05 unlock, encrypted retained
drafts and one cursor sync engine are mandatory. AppSync Events uses durable
metadata relay and account/session fences; preserve dirty editor and Summary
consent/lineage. Follow M06.0–M06.5, test/fix Chrome+Android and tick only verified
criteria; update/push after each M/P or milestone. Other modules/deployment stay
outside the current scope. M06.0 freezes contracts, not feature acceptance.

## Workspace correction — 2026-10-02

The user requested removing this repository's C: worktrees and continuing in
D:/kiet/hk7/flutter/midterm/note_ai_app-note-ai-app. The primary checkout is now
final-tuankiet@61a826b, with the four uncommitted M06 domain files restored and
hash-verified. The managed M05 worktree was archived with a recoverable snapshot;
the clean old merge worktree and a stale registration were removed. Original
untracked .playwright-cli/ and final_project.md stay in the primary checkout.
The prior untracked instructions and non-generated configuration backup are in
D:/kiet/hk7/flutter/midterm/note_ai_app-backups/2026-10-02-worktree-move.
Use graph project noteflow-final-d (root D:), Tier2, with coverage/source fallback.
R: is only a short path alias to this same D: folder, not another worktree.
All subsequent source changes happen in the primary checkout; do not recreate
C: worktrees. For platform tests use Chrome in a real browser and Android on
emulator-5554, preserving installed user data. Record this workspace correction
and continue M06.1; M06.0 was pushed at 61a826b.

## Implementation checklist tracking - 2026-10-02

User requested ticking the actual Implement plan Note AI App child pages for
M05/M06/M09, including Functional, Non-functional and Done When. Consult
/docs/m06/CHECKLIST_AUDIT.md. M05 has 19 verified checkboxes; M09 has 11 checked
and 5 pending evidence. M06 rubric stays pending until each acceptance gate.
Keep those pages synchronized after every completed M/P or milestone and push.

M06.1 foundation accepted: real Chrome40 and Android40, strict legacy codecs,
canonical pair queue/conflict/vault, access-first encrypted retained draft and
legacy reserved-ID authenticated bindings. Next M06.2 backend. Final M06 rubric
remains pending integration; see docs/m06/PROGRESS.md and CHECKLIST_AUDIT.md.
