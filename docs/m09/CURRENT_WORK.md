# M09 current work

## Latest checkpoint — overrides historical pending entries below

Source/local integration accepted as bounded in INTEGRATION.md: VM1709/4 skips,
Chrome1505/2 +browser-only3/3, backend outside RAG131/131, config14/14, analyzer
clean177.9s; actual fixed Chrome/Android protected unlock keeps body/label/file,
protected export hash matches and Lock/revoke mask private content. AWS/RAG/M01
setup gates remain open. Product commits e53e698,134d910,7577456,96d375e,c3b4cd2,
278add3 are made. Publish docs/push/verify remote, then M09 P0 engine/ref proof.
Active restarted runtimes: backend16945, Web TTY47238, emulator6681/5554. R: alias
restored to this D: checkout; ADB reverse8796/8797/8798 set. Chrome pw/ctx/page
live in Node REPL with preserved owned profile and --disable-gpu.
Native APK448B83F20C715402B389D672388371F0C603B0055669883C1D7B9CC47813F80A includes
all fixes but predates publication; refresh exact-commit provenance afterward.
Graph refresh is pending another index operation; verify current source for
stale/partial graph evidence. AppFlowy6.2.0 remains only a cached candidate,
with no project dependency/spike yet. M09 itself is not implemented or scored.

## Historical continuity

## Active authorization — 2026-10-13

Integrate `anhminh-final` into `final-tuankiet`, verify/fix the integrated
application, then complete M09, real Chrome/Android QA and per-platform >=95/100
scorecards. Push accepted milestones and update Notion after each.

## Integration checkpoint

- Original checkout: `8ec767d`; remote final-tuankiet: `f6e188e`.
- Fetched explicit refs (origin fetch configuration omits anhminh-final).
- Both integrations fast-forwarded; current HEAD `75a90b0`. No text conflicts.
- Local generated macOS registrant had identical canonical Git content to HEAD,
  but LF differed from configured CRLF. Preserved original bytes plus
  `final_project.md` in D:/kiet/hk7/flutter/midterm/note_ai_app-backups/
  2026-10-13-m09-preintegration, normalized only line endings, then integrated.
- Backup branch: `codex/m09-pre-integration-20261013`.
- `.playwright-cli/` and `final_project.md` remain untracked and preserved.
- Incoming source includes M01 profile, AI Summary tests and RAG Phases1-5;
  final incoming commit explicitly labels Phase5 incomplete. Git integration is
  not application acceptance; regressions/runtime setup are next.

## Work next

1. Integrated Flutter VM baseline passed: 1702 tests, four configured skips.
   npm ci restored the new tokenizer dependency. Full analyzer PASS (178.6s).
   Non-RAG backend 128/128 PASS after fixing Windows file URL resolution in
   amplify/ai/test_support.ts; fixture file was present, URL.pathname was wrong.
2. Backend typecheck is blocked by incoming missing tracked source inputs:
   docs/rag/tokenizer_manifest.json and index_job_policy_v1.json. Neither exists
   in known Git history/backups; the referenced collaborator Notion page is not
   accessible to this connector. Requested original files from the user to keep
   tokenizer pins/policy identity compatible. User says originals are on AWS.
   No usable AWS CLI/config/profile/session is present locally; cannot retrieve
   deployed bytes. Do not invent production pins or mark RAG verification passed.
3. Actual Chrome/Android integrated QA continues using production local-dev
   composition; existing NoteFlow_API35 data is preserved. Services session95318.
   Then fix/retest and publish integration receipt before M09 implementation.
   Web actual: Unicode autosave, labels, TXT upload48bytes Ready, Viewer grant
   confirmed to recipient; recipient shared-note/label list verified. Existing
   data retained. Export opens a guarded iframe; IAB download event not observed,
   so final byte/hash export acceptance remains pending. Found stale previous
   upload phase when opening cached attachment; cleared progress at preview start
   in attachment_editor_preview.dart, actual hot-reload/retest still needed.
   Baseline Android build1142.3s installed-r; hash63BBF3EEC36F7CE946DC8F31A3974C53591B1C68091EFE56AE3290F752166CA7.
   Native found a real legacy-label backfill bug: wireVersion1 with stored
   cursor50 intentionally sends a null cursor, but coordinator compared the
   returned page50 to the stored cursor and refused before V2 upgrade. Backend
   paging is correct. Compare to actual pullCursor; keep stored cursor for CAS.
   New regression tests prove multi-page upgrade and unchanged blocked draft/
   attempted mutation, plus genuine non-progress refusal. Fix VM39/39 PASS.
   Chrome selected matrix1498/2 configured skips across156 compatible targets;
   first broad run wrongly included13 filesystem/isolate targets (102 failures),
   separately covered by full VM baseline. Receipt output/m09/chrome-matrix.json.
   Actual Web offline edit/reload kept body, labels, file and queued mutations.
   Fixed Android APK built44.8s (x64), installed-r without data reset. Actual
   cold-start backfill now goes null->50->77, wireVersion2, blocked draft1
   unchanged, loadError null. Fresh shared note/body/label/file appears Viewer.
   Focused Chrome27/27 PASS. Final full VM now running session51500.
   User explicitly authorized Playwright Chrome local. CLI downloaded no event;
   direct persistent Chrome with --disable-gpu successfully exported48 bytes,
   SHA256715b31e28904ac2abc57a78f6fc9d9c9f406557c1d9c4c7b91fb8c6a47f726ce.
   Actual cached preview retest no longer shows stale upload status. Keep owned
   QA profile output/playwright/m09-chrome-owner; never reset user profiles.
   Actual Viewer->Editor reflected on native; protected Android Editor wrote
   ANDROID-EDITOR-QA-20261013; Chrome focused body confirms exact text received.
   Owner offline lock/wrong-password/right-password works. Found cached valid
   key with newer metadata-only body could never online unlock; local unlock
   now falls through to authorized cloud hydration only for online/no pending
   protection. Wrong password/offline still fail closed. New VM3 +Chrome11 pass,
   actual fixed Chrome online unlock/disable preserves Android text and file.
   Revoke masks native immediately and retains encrypted drafts. Native owner
   export48bytes SHA256 matches; APKFB590A27F06EA61E97077530D22B817F8FC8E795F7EC07829B3CB78F9FDA3C48 includes unlock fix, not newer label fix.
   Found label hydration contract gap: protected /content returned legacy
   shape, and Application omitted includesLabels/includesAttachments flags.
   Negotiate wireVersion2 query on authorized content, preserve legacy response
   and grant guard, forward both presence flags. Backend regression3/3 pass;
   VM focused pending a Windows native hook rebuild, session28285. Full earlier
   VM1706 pass/4skip had one fixture-cleanup error (missing already-removed temp
   directory); cleanup now idempotent for absent fixture, deletion guards kept.
   Full label-fix Chrome now session81775. No final acceptance/push yet.
   Source-local profile in main_dev says service not configured; RAG permission
   transport unavailable here. These are setup/live gates, not verified AWS.
   After tool interruption the owned runtimes were gone; restarted preserved
   backend16945, Web TTY47238, emulator6681. Reestablish ADB reverse ports.
   Real Chrome profile output/playwright/m09-chrome-owner retained. Reopen it
   using installed Chrome executable and --disable-gpu, not user profiles.
   Local server with metadata-only trace is session94919; no body/id/token logs.
4. M09.RT.P0 engine/IME/round-trip proof and ref map, then P1-P6 implementation,
   regression/UI QA, scored ref comparison, fixes and final handoff.

## Final integration source/local receipt

All product fixes now verified: VM1709/4 configured skips; Chrome1505/2 on159
targets; non-RAG backend131/131; dev-config14/14; analyzer clean177.9s.
Explicit browser-only entrypoints additionally pass3/3 (hardware + real encrypted
platform storage/migration). All browser-compatible entrypoints now covered. Actual
Chrome and matching Android APK cold online unlock preserve current body/label/
file. Native protected export saved a new qa-integration (1).txt,48bytes/hash
matches original. Native Lock masks body/labels/preview. Read INTEGRATION.md for
bounded scope and unresolved AWS/RAG/M01 setup gates. Publish explicit patch and
docs to final-tuankiet next; remote remainsf6e188e (fetched/rechecked), HEAD75a90b0.
After publication, refresh APK exact-commit provenance, then implement M09 P0.

## Settled scope

13 Basic blocks; independent notes. Selection toolbar including inline math,
color/highlight/marks/link/code/clear and selected-text font sizes 12-48.
Single local-first encrypted writer/outbox/cursor and metadata preservation.
Web and Android independently >=95/100 (60/20/10/10), evidence required.
No claims of live AWS acceptance from local fixtures or source.

## Records

- Editor plan: https://app.notion.com/p/3f5f9c7a1aa0817f9e0bdbe52bb091fe
- Scorecards: https://app.notion.com/p/3f7f9c7a1aa0816ab867faaefb40454b
- Progress: https://app.notion.com/p/3f8f9c7a1aa0817a8f08e793aaaae83d
- `_agent_ops/` does not exist; use these actual docs, do not fabricate ops files.
