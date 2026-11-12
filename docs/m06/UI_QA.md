# M02/M05/M06 actual UI QA — 2026-10-04

Baseline: `final-tuankiet@b5ecc64416ae7123ddc96d9fb9dac74a11a8f4ec`.
Standalone Notion journal, outside the main project page:
https://app.notion.com/p/3eef9c7a1aa0818d85c4ebdfdcca2015.

## Method and scope

Installed Chrome was operated through Playwright CLI using actual pointer,
keyboard, dialogs and rendered screens, both with and without Flutter
accessibility enabled. Android API35 x86_64 AVD `NoteFlow_API35` was operated
through ADB input and UIAutomator, with screenshot checks. No direct service or
application-storage mutations were substituted for these UI scenarios.

`lib/main_dev.dart` uses the actual presentation/application/local encrypted
store/outbox/ACL paths, two synthetic owner/recipient identities, and loopback
HTTP/socket adapters backed by SDK doubles. This verifies local integration,
not deployed Cognito/JWT, DynamoDB/AppSync or SES. Only `QA-20261004` notes were
changed. Existing notes, encrypted backend state/key and AVD data were preserved.
APK installs used `adb install -r`, never uninstall or data reset. M09 redesign,
M03 attachments and M04 provider/model acceptance remain outside this batch.

## Actual UI results

These rows distinguish platform coverage; a pass does not imply unlisted
variants were manually executed on both platforms.

| Feature/scenario | Chrome | Android emulator |
| --- | --- | --- |
| Create, edit title/body, autosave and cloud ACK | Pass, including continuous typing before/after ACK | Pass, owner and recipient-owned note |
| Whitespace-only new note | Save rejected; Cancel keeps draft, Discard leaves no row | Same three decisions verified |
| Valid explicit Save on leaving | Pass; created note then deleted | Pass on NativeSave note, with complete title/body and All synced |
| Delete cancellation and confirmed deletion | Pass on synthetic Save note | Pass on recipient-owned QA note |
| Pin/order, list/grid, search/navigation | Pass; unpin and Created sort selected; layout restored on reload | Pass; pinned note first, list/grid and search |
| Local-first editing, pending/retry | Offline saved locally; reconnect automatically drains queue | Offline cached shared unlock/edit; reconnect/fresh authorization + Sync now ACK |
| Persistence | Reload relocks protected note; fresh profile restores synced data | App/AVD restart retains encrypted data and relocks |
| Dirty remote edit review | Both conflict panel and Use cloud verified by canvas UI | Keep and save local and Use cloud verified on actual conflict panel |
| Password validation/enable/lock/unlock | Short/mismatched/wrong password rejected; correct unlock works | Owner enable/lock/unlock; wrong/correct password |
| Change/disable password | Both pass offline on Web, then pending changes sync | Both pass online; old password rejected, new accepted |
| Password rotation on shared note | Recipient automatically relocks; old rejected/new accepted | Owner independently rejects old/accepts new password |
| Masking and authority | Locked title/body/preview masked; recipient cannot administer protection | Viewer read-only, Editor editable; no owner protection/recovery actions; revoked panel masked |
| Lifecycle/logout | Reload relock; logout returns Welcome back without note/editor | Real background/resume relock; recipient logout removes note/editor |
| Recovery UI | Unavailable guard with retained-data copy and disabled Confirm | Resend unavailable guard verified; no real email OTP claim |
| Share validation | Invalid/self/unknown/duplicate recipient errors verified | Actual verified recipient Viewer/Editor administration |
| Share/realtime/roles | Recipient discovery, Editor/Viewer, owner updates; multiple same-actor devices receive | Create/share, Editor→Viewer, revoke/re-share, actual bidirectional text |
| Offline revoke and old draft | Owner revokes from actual UI | Offline draft then reconnect masks editor, retains encrypted pending draft; re-share new grant does not silently replay old draft |
| Queue isolation | Owner/recipient UI shows the recipient-owned note arriving | A new owned note syncs while revoked shared draft remains pending; deleting owned note does not drop retained shared draft |
| Responsive workspace | Side1280px→center1000px→full390px keeps selected editor; fresh console0 errors/0 warnings | Full-page editor/navigation verified |
| Settings | Dark/Vietnamese and settings navigation | Dark/Vietnamese and account menu |
| Diagnostics | Read-only diagnostics page opens and returns | Read-only diagnostics page opens and returns |

### Confirmed defects and fixes

| ID | Reproduction / cause | Fix and verification |
| --- | --- | --- |
| QA-01 | Disabled Summarize semantics merged into ancestors, marking unrelated fields/actions disabled | Separate toolbar semantics containers. Actual Chrome/Android New note fields remain enabled; toolbar regressions cover enabled/disabled actions. |
| QA-02 | Shared recipients saw Enable protection/recovery controls belonging to owner; revoked panel lacked a useful return path | Gate controls by canonical owner/manage authority and show Note unavailable + Back. Actual Viewer/Editor/revoke UI and widget regressions pass. No server permission bypass was demonstrated. |
| QA-03 | Same-text ACK advanced revision but editor baseline stayed old, producing false remote-change review and resetting caret | Rebase only unchanged authorized full-text baseline; preserve dirty draft/selection, still review genuine text/ACL/protection changes. Editor regression and subsequent actual typing/editing pass. |
| QA-04 | Home stayed empty/stale after account sync until navigation | Subscribe Dashboard to account note changes and coalesce an additional reload when a change arrives during loading. Fresh Chrome Home receives notes; two widget regressions pass. Unshared remote changes still need protocol notification/sync; this does not add a new realtime feed. |
| QA-05 | Desktop→390px transition temporarily retained sidebar width and overflowed Search/content | Release compact sidebar/divider width immediately, retaining editor state. First-frame regression plus fresh browser resize/screenshots pass. |
| QA-06 | Local fixture stored only one connection per actor, dropping realtime for older Chrome/native devices | Keep independent connection/subscription maps, isolate disconnect/unsubscribe/dead sockets. Three Python tests and actual owner→Chrome recipient+Android recipient fanout pass. This is a local tool defect, not an AWS defect. |
| QA-07 | Saved note lost DOM input focus after first character with Chrome accessibility when save status animated | Stable outer semantics container around animated status, inner status-only live region. Two saved notes accept full per-character input with textarea focus retained. Semantics identity/live-region/focus regressions pass. Temporary Content/Summary wrappers were ruled out and reverted. |

## Final automated regression supporting the UI results

- Five targeted widget files: **103 passed**, no failures (11 seconds).
- Local multi-connection socket fixture: **3 passed**.
- `flutter analyze --no-pub`: **No issues found**, 156.7 seconds.
- Final owner debug APK: **built**, 54.4 seconds, installed preserving data.
- Existing Amplify plugin Kotlin Gradle compatibility warning remains a build
  warning; it did not fail this build. Dependency migration is not this UI fix.
- Historical VM1029/Chrome902/platform100 integration receipts in
  `M02_INTEGRATION.md` were not re-run or counted as manual tests in this batch.

Widget command:

```powershell
flutter test --no-pub test/presentation/dashboard/dashboard_page_test.dart test/presentation/workspace/workspace_shell_test.dart test/presentation/notes/note_detail_page_test.dart test/presentation/notes/note_detail_action_bar_test.dart test/presentation/notes/note_manual_qa_regression_test.dart
python tool/test_m06_socket_fixture.py
flutter analyze --no-pub
```

Runtime setup: see `DEV_SETUP.md`; use `python tool/run_m06_local.py`, owner and
recipient URLs on fixed port8776. Native dev APK needs `M06_DEV_USER` and ADB
reverse mappings to loopback services8796/8797. Plain production
`flutter run -d chrome` does not start the synthetic Share backend.

## Evidence and interpretation

Ignored local artifacts are in `output/playwright/qa-20261004/`; they contain
synthetic screenshots/UI XML, browser profiles, local logs and debug APKs, and
are deliberately excluded from Git. Key final evidence:

- `web-accessible-typing-final.png`: full continuous input after QA-07.
- `web-human-conflict.png`, `web-human-use-cloud.png`: real dirty review and
  selected cloud content.
- `android-conflict-final.png`, `android-use-cloud-final.png`: final installed
  owner APK reviews a real remote edit and adopts `HOSTGPU CLOUD CHOICE`.
- `android-revoked-draft.png`, `android-reshare-current.png`: masked revoked
  editor and new grant with old encrypted draft retained.
- `web-center-peek.png`, `web-full-page.png`: selected note survives resize.
- `final-widget.log`, `final-analyze.log`: newest source regression.

Some Flutter semantic textbox values lag a clean remote controller update;
rendered screenshot/full visible text was checked before declaring a data bug.
Stale UI refs, input-helper selection artifacts, hot-reload setup errors and
expected unavailable/offline requests are not counted as product failures.
Three emulator process exits interrupted additional native conflict attempts;
Windows Application Error event1000 confirms host
`qemu-system-x86_64-headless.exe` crashes with `0xc0000005`, not a demonstrated
Flutter application crash. Those attempts are excluded. The same data-preserving
AVD completed the conflict/Use cloud retest with host GPU and Vulkan disabled:

```powershell
emulator -avd NoteFlow_API35 -no-window -no-snapshot -no-audio -no-boot-anim -gpu host -feature -Vulkan -cores 2
```

This run succeeded with that launch configuration; it does not prove a general
fix for the emulator's host crash. Rendering modes/launch flags follow the
[Android emulator documentation](https://developer.android.com/studio/run/emulator-acceleration).

## Limits / separate acceptance

- Native password administration was exercised **online**. Offline enable/change/
  disable is the Web local-first flow; native offline cached unlock/edit passed.
- Loaded Web app offline persistence passed; cold offline shell loading/PWA
  installation was not verified.
- Full SES OTP delivery/reset and deployed AWS/Cognito/AppSync acceptance remain
  pending in `LIVE_GATE.md`. The local unavailable/recovery guard passed.
- Inactivity expiry was not timed manually for15 minutes in this run. Existing
  automated lifecycle/expiry evidence is separate from actual background UI QA.
- Diagnostics navigation is in scope; model download/provider summaries and
  attachment bytes are separate M04/M03 acceptance.
- The verified scenarios above passed after fixes; this is not a claim that all
  possible devices, network timings or provider configurations are bug-free.

## Publication / final additional UI checks

Final owner APK Use cloud passed after host GPU/Vulkan launch adjustment;
recovery unavailable guard and Chrome logout passed. Native diagnostics and
final owner logout were rechecked. No additional confirmed application failures
were observed in those final scenarios. The Notion journal records the remote
SHA after explicit staged review and publication to `final-tuankiet`.

Additional native validation: title-only/empty body cannot save. After entering
both fields, Back→Save creates the expected note and reaches All synced.
Presentation/source commit: `7b1b0bd`; fixture/test commit: `b9a662e`.

Continuity records: `MUST_REMEMBER.md` updated with the latest manual receipt;
`CURRENT_WORK.md` updated during QA with fixes, excluded attempts and next step.
`_agent_ops/` is absent in this checkout, so its session/closure files cannot be
updated; the existing project records above are used. Unrelated dirty macOS
generated registrant, `.playwright-cli/` and `final_project.md` remain excluded.
