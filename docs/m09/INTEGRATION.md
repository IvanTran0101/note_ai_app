# Integration receipt — 2026-10-13

## Source and preservation

Primary D: checkout, branch final-tuankiet. Fast-forwarded8ec767d -> f6e188e
-> anhminh-final75a90b0, with no textual conflicts. Original local generated
macOS bytes and final_project.md were backed up before line-ending normalization.
Unrelated macOS generated state, final_project.md and .playwright-cli remain
preserved outside the explicit staged scope. No C: worktree was created.

## Verified regressions

| Check | Result |
| --- | --- |
| Full Flutter VM after all fixes | 1709 passed, four configured skips |
| Chrome,159 compatible targets | 1505 passed, two configured skips |
| Chrome, two explicit browser-only entrypoints | Three passed (Web hardware, real encrypted platform storage/migration) |
| Non-RAG backend | 131 passed, zero failures/skips |
| Dev configuration | 14 passed |
| Full Flutter analyzer | Clean,177.9s |

The aggregate selection excludes18 targets with platform annotations or
filesystem/isolate fixtures; its two browser-only entrypoints were then run
separately (three passes). VM covers the native fixtures. Logs and selection receipts
are in ignored output/m09, never shipped as application data.

## Confirmed fixes

1. Windows Summary fixtures: use fileURLToPath instead of URL.pathname.
2. Cached attachment preview: discard a previous transfer's stale progress.
3. Legacy label backfill: compare pagination progress with the actual null pull
   cursor, preserving the stored cursor for CAS and old blocked draft/mutation.
4. Online unlock after a protected content revision: a valid cached key with an
   obsolete payload now retrieves current content through server authority.
   Wrong passwords/offline requests still fail closed; pending protection stays
   local and never falls through to cloud overwrite.
5. Authorized protected content: negotiate V2 labels without changing legacy
   response shape; carry labels/attachments presence flags through hydration.
6. Test cleanup: tolerate an already-absent owned temporary fixture; resolved
   path/deletion safety checks remain in place for an existing directory.

## Actual user flows

Synthetic QA note only: QA-M09-Integration-20261013. Existing notes and encrypted
stores/emulator data retained; no logout, account reset or storage wipe.

| Flow | Chrome local | Android emulator |
| --- | --- | --- |
| Unicode autosave/local-first and reopen | Passed; offline edit/cold reload preserved body, label, file and outbox | Cold reopen/current cloud body preserved |
| Label and TXT association | Ready48bytes | Same file/label/body visible |
| Viewer/Editor/revoke | Owner changed grants; received exact Android Editor text | Viewer readonly, Editor wrote, revoke immediately masked note and retained drafts |
| Protection | Enable/lock/wrong/right offline/online unlock/disable; current body retained | Correct online password opened current protected body; label and file retained; lock masks content |
| Protected content after cold reopen | Label/body/file preserved with fixed V2 path | Same matching APK verified |
| TXT export | Actual UI download48bytes/hash matches | Actual protected export48bytes/hash matches |
| Settings | Dark then System restored | Core workspace checks above |

Export SHA256:715b31e28904ac2abc57a78f6fc9d9c9f406557c1d9c4c7b91fb8c6a47f726ce.
Chrome is installed Chrome controlled by Playwright, headed, preserved owned QA
profile, --disable-gpu (machine-specific download issue with the default session).
Android NoteFlow_API35/emulator-5554, install-r, source fixes included in APK
SHA256448B83F20C715402B389D672388371F0C603B0055669883C1D7B9CC47813F80A.
That APK was built from75a90b0 plus this patch; it is not yet a final published
commit artifact. Refresh exact commit provenance after publication.

## Open runtime gates

Full backend typecheck/RAG tests remain unverified because the incoming branch
imports absent docs/rag/tokenizer_manifest.json and index_job_policy_v1.json.
The user says originals are on AWS; no usable local AWS credential/profile
exists. Do not invent pins/policy identity. RAG provider/deployment acceptance
and M01 cloud profile/password/avatar acceptance are separate; main_dev currently
reports profile service unconfigured and RAG permission transport unavailable.
No paid provider call or deployment was performed. This receipt accepts the
recorded source/local scope, not all live AWS functionality or a bug-free claim.

## M09 next

Proceed with P0 engine/IME/selection/round-trip proof and ref mapping, then the
approved P1-P6 implementation. Scores remain ungraded until paired screenshots
and platform-specific functional/visual evidence exist.
