# M09 current work

## Active request and boundary

Continue through ALL M09, including actual Chrome/Android QA, fixes, separate
>=95/100 reference scoring, Notion updates and final-tuankiet pushes. Do not
stop at a source checkpoint. UI/UX uses existing features only; new capabilities
need a concrete Notion proposal and explicit user approval. Read MUST_REMEMBER.md.
Keep local-first, the single encrypted actor store/writer/outbox/cursor, all
access/session fences and unrelated work. No C worktrees or unrequested deploys.

## Verified editor checkpoint — 17 October 2026

Runtime807-file fingerprint:
4ee0a0ed21eedc8093b7ad92ab2d7c1bba11a7beeb269013195bc1ef6baa2101.
Source manifest output/m09/p5-oct17-source.json rechecked:0 mismatches.

- Full VM1898 pass/5 configured skips/0 failures,2m46.
- Installed Chrome1700 pass/2 configured skips/0 failures on199 original mains,
  with M09_LOCAL_HTTP=true;2m01 test runtime after cold tools/DDC compile.
- Static lib/test/integration_test/golden tool/modified TableCol: No issues found.
- Matching x64 APK built63.7s; installed-r and on-device hash matched:
  A76328E3ACC42C6B648018D7A3AA1D5F9CF644E1F56FA00662175BE134379096.
- Web debug build104.2s; JS succeeded. Wasm dry-run universal_html warning is
  pre-existing and does not mean the JS build failed.
- New AX reproduction4/4 failed before, focused82/82 after.
- Table rendered-history reproduction2/2 failed before, focused54/54 after.
- Editor/popup/layout subset144/144 passes.

Read P4_EDITOR_CHECKPOINT.md and P4_UI_QA.md for evidence and limits. Publish
this verified checkpoint next, then continue P5/P6. No final UI scores or full
M09 acceptance yet. Before publication branch/remote were final-tuankiet at
23f3652145e3592b5e2f8a398b0d221300b412ae; recheck before mutation.

## Fixes and actual UI receipts

- Table post-frame height measurement now uses recordUndo:false/recordRedo:false
  and a mounted fence. It previously refilled history and cleared Redo.
- Actual matching APK Add row/Undo/Redo/Undo gives4->5->4->5->4 rows; XML total
  EditText counts10->12->10->12->10. Fresh open has Undo/Redo disabled, as expected.
- EditorPopupArea subtracts root-overlay origin and clamps slash/selection to
  actual overlay/keyboard/safe bounds. Short popups scroll. Matching longpress
  Q controls endy677 before selected fieldy750; selected Q is no longer covered.
- Matching cold open retains blue/yellow sqrt{x}+4row table in QA-M09-Blocks17,
  and Q28/H4/A1 tiếng việt 😀/B1 in QA-M09-P4-Sheet-Android-16 (title trailing space).
- Earlier Native core captures cover13 touch choices, todo/Undo, five marks and
  clear, colors/highlight, size49 refusal/28 apply, invalid URL/valid HTTPS reopen,
  invalid equation/painted root. These are preceding-build functional receipts;
  final adaptive/permission UI matrix still needs matching current-source QA.
- Native Telex/emoji/offline/cold reopen/reconnect and Chrome cross-device table
  sync have receipts. Do not claim full browser offline cold boot/PWA support.
- New header is single-owner accessible, right-aligned, compact sync punctuation
  fixed, title/body centered with metadata after content. EN/VI display strings
  preserve stored keys/commands. DEBUG ribbon removed; LOCAL DEV marker retained.

Screenshots/JSON/logs live in ignored output/m09 and output/playwright. Do not
publish raw logs, reference images, keys or user data. Earlier detailed journal
is preserved locally at output/m09/CURRENT_WORK-20261017-0225.md.

## Next P5 adaptive work, then full P6

1. Publish807 checkpoint after explicit staged-path review; preserve unrelated
   .playwright-cli/ and final_project.md. Never git add . or force push.
2. Actual phone landscape914x411 currently chooses desktop sidebar280 and
   desktop title/top padding; keyboard leaves only a clipped title. Data and Q
   focus survive restoration. Prefer mobile UI for Native handsets by shortest
   side, leaving Web width-based. Inspect graph/coverage and shared layout first.
3. Native permanent48dp Plus/Undo/Redo/Table-options row between title/body
   pushes first body about48dp below Android014 reference. Move these EXISTING
   controls to a rail above keyboard/existing bottom actions, with same focus,
   snapshot and callbacks; no feature addition. Web may keep its current header.
4. Regress/build and test actual keyboard/rotation/text scale1/1.6/2, narrow320,
   gesture/3-button insets, light/dark; restore original emulator settings.
5. Finish actual protection/share/revoke/drafts/files/labels/search/settings and
   remaining editor clipboard/nesting/mixed-format cases on Chrome and Android.
6. Fill11 scored criteria separately, paired refs/captures/build provenance;
   fix/retest until each >=95 with mandatory flows working. Update all relevant
   Notion ticks and push verified milestones through final completion.

Ref mapping: REF_MAPPING.md. Web007 title nearx460/y164, column704-720,
sidebar270-280, header44-48. Android014 gutter20-24dp/title32/header56 and bottom
Search/Ask/Create. Record/subtract dev marker/insets honestly. Actual807 Web
field bbox462.1/177/725.6/61.6 (dev strip24); More ends1363.2, one Summary/More.
No final grade has been assigned. Do not derive UI grades from unit-test counts.

## Current owned runtimes and tools

- Local fixture exec97072 serves8796/8797/8798 with M09_QA_BROWSER_ORIGINS=1.
  Same encrypted snapshot/key retained. Random test-port preflight now204.
  Earlier197 opt-in Chrome run failed only because the restarted fixture lacked
  this existing QA flag; final199 actual HTTP passes. No deployed CORS change.
- Static Web exec43738 serves output/m09/p6-final-web on8776.
- Chrome199 exec76071 completed; close its session via write_stdin if needed.
- Native AVD NoteFlow_API35 deliberately STOPPED to free RAM during Chrome.
  Restart -no-snapshot -no-audio -no-window -gpu host, WindowStyle Hidden and
  keep launcher exec alive. No wipe/reset. Restore ADB reverse8796/8797/8798.
- SDK D:/tools/AndroidSdk; ADB C:/platform-tools/adb.exe. Flutter C:/Users/meow/flutter.
  JDK17 C:/Program Files/Eclipse Adoptium/jdk-17.0.11.9-hotspot. R: aliases THIS D
  checkout. Native builds use R:, Gradle3GB/workers2, CMAKE parallel2, TEMP/TMP
  output/m09/runtime-temp. Serialize heavy Flutter jobs (16GB host).
- Emulator original state:1080x2400,420dpi,fontScale1.0,gesture navigation,
  accelerometer_rotation1/user_rotation0, Vietnamese Gboard+English retained.
- Node cpM/fsP5/reqM/pwP5 available; ctxP5 CLOSED, profile m09-chrome-owner kept.
  Reopen installed Chrome with explicit executablePath, --disable-gpu,1363x936.
  channel:'chrome' points to a wrong AppData path. Wait for Back/textboxes after
  async note navigation before capturing. Native helper native_tap.py uses fresh
  hierarchy/clickable control matching and scrolls the observed block menu.
- All VM breakpoints removed, diagnostic socket closed, owned forwards removed.
  Never print debug service URIs/capabilities. No native CUA; use direct ADB.
- Graph Tier2 project D-kiet-hk7-flutter-midterm-note_ai_app-note-ai-app is indexed;
  last generation2026-10-16T19:00:23Z. Prefer graph, verify path coverage and read
  changed/missed source. _agent_ops does not exist; do not fabricate ops records.

## Durable contracts and gates

Document1,13 choices/no Page or Link to page; stable IDs, exact projection,
finite sizes12-48 and limits from P1 remain. Schema7/AAD3/packet3, V3 capability,
exact attempted legacy payloads, backfill, explicit conflicts and access fences
remain. P0-P3 are already published; live AWS/RAG and exact missing manifests
remain separate gates. Never invent tokenizer/policy files or deployed proof.

Notion under final flutter:
- Progress https://app.notion.com/p/3f8f9c7a1aa0817a8f08e793aaaae83d
- Main M09 https://app.notion.com/p/3e9f9c7a1aa080bb85a8d4973595bc21
- Editor plan https://app.notion.com/p/3f5f9c7a1aa0817f9e0bdbe52bb091fe
- Scorecards https://app.notion.com/p/3f7f9c7a1aa0816ab867faaefb40454b
- Implementation https://app.notion.com/p/3e8f9c7a1aa0810ea410c5dc6b6bb7c8
