# M02 / M05 / M06 compatibility review

Date: 2026-10-04 (Asia/Saigon).

## Result

Fetched `origin/final-TanMinh` at
`aabf2294cdf882b9110971345d5f574a8d98e6c0` and verified delivery branch
`final-tuankiet` at `fcb4a546a860512ff22cfa8f7ea25b804eaedbf4`.
M02 source is available locally, but these application sources have **not been
merged**. This receipt answers the user's compatibility question before the
collaborator builds M03 on the shared core.

Ordinary branch merge simulation found **96 conflicting paths**: 57 in lib,
16 backend, 16 tests and 7 other paths. This is a Git path count, not a defect
count. The common Git ancestor is `6233e168904212026ed31c5fb4214a90264b72f4`;
the histories have 123 local-only and 8 incoming-only commits. Several earlier
Summary/sync changes were aligned by source on Kiệt's branch, so their history
still produces add/add conflicts in an ordinary merge.

A second diagnostic explicitly uses the shared *source* baseline `6ce2afe` to
isolate the three M02 commits (`16ee44b`, `20a29a8`, `aabf229`). This delta has
74 changed paths, 2,906 insertions and 599 deletions. It produces **25 conflicting
paths** (20 non-test and 5 test paths). The overridden merge base is a diagnostic,
not the actual ancestor or evidence of a completed branch merge.

## Confirmed compatibility gaps

| Boundary | Source evidence | Required integration |
| --- | --- | --- |
| Atomic writer | TanMinh INoteRepository.updateById uses positional id, actor and void callback; repository lines120-160 checks account, but has no canonical owner or session/access commit-fence parameters. Kiệt editor uses saveEditorSnapshot/saveSnapshot and current role/protection/session checks. | M02.4: one named resource/actor writer with synchronous fresh-instance change + fence. Preserve M06 expected-snapshot review, known revoke/role/protection checks, no-op and one atomic Note/outbox commit. Migrate rename/replace too. |
| Local schema | Both LocalSyncSchema.version values are3. TanMinh fields add pin/preferences; Kiệt fields add protection/share and encrypted storage. Same number is not a compatible shape. | Coordinated schema/migration, distinguish legacy formats, preserve IDs/canonical owner/actor, cursor, attempted requests, preferences, ciphertext, conflicts and retained drafts. No reset or plaintext fallback. |
| Pin wire/backend | TanMinh sends pinnedAt; current Kiệt parseMutationBody constructs payload from title/content only (request_parser.ts:138-147). | Preserve pin through DTO/local/wire/ACK/pull/conflict/protection hydration/backend. Owner may organize; shared Editor text changes must preserve owner pin and must not acquire organize authority. |
| Access and composition | TanMinh Note/DTO/root do not wire the M05/M06 security/share fields and callbacks. Kiệt root passes accessGuard/sessionGeneration, security runtime and grant/observe/hydrate callbacks. | Keep canonical owner separate from actor; carry fields/guards through all new M02 code, encrypted stores, protected feed and dev composition. Choosing one whole root/model/repository loses the other branch's behavior. |
| Summary | TanMinh summary_run_guard.dart:61 uses hasSameTextAs; Kiệt retains full persisted snapshot and protection/session gates. | M02.5: one shared projection and full saved snapshot equality, including pin and accepted security/access lineage. Preserve consent/cancellation and before/after authorization. No metadata or binary becomes an AI input. |
| Editor/transition UI | Both branches modify editor/controller/workspace; M02 adds pin/autosave/peek behavior while M06 adds explicit stale review, Shared with me and access-loss handling. | M02.6: retain both behavior sets, guard late callbacks and retained encrypted drafts; fresh semantic regression after conflict resolution. No new M09 redesign in this review. |

### Executed pin parser probe

One isolated Node/tsx diagnostic executed the **current production parser** with
a synthetic update containing `pinnedAt: 2026-10-04T00:00:00.000Z`:

```json
{"accepted": true, "pinRetained": false}
```

The input is accepted but pin is discarded before storage. This confirms an
M02-to-current-backend incompatibility; it is not a deployed AWS test and does
not mean M05/M06 independently implement or require pin already.

## Handoff decision

1. Complete M02.4, M02.5 and M02.6 integration against this exact M05/M06 source
   before claiming an integrated core or full attachment feature acceptance.
2. Reuse the existing contracts in the Notion M02 report and integration appendix;
   keep a single writer/coordinator. Neither whole-file ours/theirs selection
   nor a successful text auto-merge establishes semantic correctness.
3. M03 Domain/attempt foundation and source/setup may continue behind the agreed
   contracts. Full picker/protected/shared link/read flow needs the integrated
   writer, versioned migration, scoped unlock and binary adapter receipts.
4. On the resolved branch, run concurrent text/pin writes, same-user/new-session
   fences, protected/shared Viewer/Editor/Owner bypass, downgrade/revoke, retained
   drafts, v3 migration, pin replay/lost ACK/late edit, full Summary snapshot and
   Chrome/Android offline/reopen regression. Existing separate-branch PASS does
   not satisfy this integrated regression gate.

M02.4-M02.9 / integrated verification boxes remain pending. M03 design A/A/A
remains settled. No M03 implementation, M09 redesign, AWS call or deployment was
performed by this review.

## Reproduction and audit limits

```powershell
git fetch origin refs/heads/final-TanMinh:refs/remotes/origin/final-TanMinh refs/heads/final-tuankiet:refs/remotes/origin/final-tuankiet
git merge-base fcb4a54 aabf229
git merge-tree --write-tree --name-only fcb4a54 aabf229
git merge-tree --write-tree --name-only --merge-base=6ce2afe fcb4a54 aabf229
```

Both merge-tree calls return1 because conflicts exist. They write diagnostic
Git objects, without modifying checkout/index or starting MERGE_HEAD. Raw output
is outside Git in TEMP/m02-m05-m06-merge-tree-20261004.txt and
TEMP/m02-only-delta-merge-tree-20261004.txt.

Code graph list_projects/index_status/check_index_coverage returned Transport
closed. Exact source at both fixed Git revisions, source diffs, and the parser
probe were used instead; this is a bounded compatibility review, not an
exhaustive graph/security audit. No integrated app exists yet to run Chrome or
Android against, so no integrated Flutter/platform PASS is claimed.

The pre-existing macOS generated-file modification and untracked user files were
preserved. Ops scripts/protocol remain absent; this report, CURRENT_WORK and
MUST_REMEMBER hold continuity.

## Direct M02 delta conflict paths

```text
amplify/sync/dynamo_sync_store.test.ts
amplify/sync/dynamo_sync_store.ts
amplify/sync/request_parser.ts
lib/application/note_intelligence/summary_run_guard.dart
lib/application/notes/note_application.dart
lib/application/sync/local_sync_state.dart
lib/application/sync/sync_snapshot.dart
lib/domain/notes/note.dart
lib/infrastructure/notes/note_repository.dart
lib/infrastructure/sync/local_sync_codec_reader.dart
lib/infrastructure/sync/local_sync_codec_schema.dart
lib/infrastructure/sync/local_sync_store_io.dart
lib/infrastructure/sync/local_sync_store_web.dart
lib/presentation/common/note_flow_primitives.dart
lib/presentation/dashboard/dashboard_note_card.dart
lib/presentation/notes/note_detail_page.dart
lib/presentation/notes/note_summary_controller.dart
lib/presentation/notes/notes_application_controller.dart
lib/presentation/notes/notes_list_panel.dart
lib/presentation/notes/notes_workspace_page.dart
test/application/notes/note_application_test.dart
test/application/notes/note_summary_snapshot_test.dart
test/infrastructure/sync/local_sync_state_codec_test.dart
test/presentation/dashboard/dashboard_page_test.dart
test/presentation/notes/notes_application_controller_summary_test.dart
```
