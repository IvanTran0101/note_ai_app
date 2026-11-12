# M06.5 acceptance record

## Scope

Current branch final-tuankiet, accepted product source315caf4. M06 local-first
only; M09 is deferred until the two collaborators finish and their changes are
integrated/tested together. No AWS deployment or collaborator pull occurred.
The extra files in this checkpoint are acceptance fixtures/runners and records.

## Verified runtime receipts

| Run | Result | Evidence |
| --- | --- | --- |
| Full VM test/ | 971 passed, 2 skipped | TEMP/m065-full-vm.log |
| Chrome Application/Domain, 35 targets | 232 passed | TEMP/m065-chrome-application-domain.log |
| Chrome Infrastructure/Security/Sharing, 33 targets | 363 passed, 1 skipped | TEMP/m065-chrome-storage-sharing.log |
| Chrome remaining UI, 21 targets | 249 passed | TEMP/m065-chrome-ui.log |
| Real Chrome M05/M06 platform plugins | 90 passed; driver true, no failures | localhost8777; console-2026-10-02T17-37-45-863Z.log |
| Real Android M05/M06 platform plugins | 90 passed after SDK reinstall, no uninstall | TEMP/m065-platform-android-final.log; 524s native build, 6m09s test run |
| Chrome owner + Android editor, same note | Both passed again after SDK reinstall; automatic two-way edits, reconnect, denial and revoke | TEMP/m065-two-client-new-sdk-android.log; Chrome8776 console-2026-10-02T18-12-24-446Z.log driver true; both fixture passed flags true, eventPublishes13 |
| Backend | 84 checks passed; tsc exit0 | TEMP/m065-backend.log |
| Root analyzer | No issues | TEMP/m065-final-analyze.log |
| Owned Dart formatting | 0 changes | m06_regression_test.dart, m06_two_client_test.dart |
| Cloud resource review helper | Local synth and standalone strict tsc passed | tool/m06_cloud_review.ts; ignored output/m06-cloud-review; fictional account/pool, no AWS calls |

Chrome totals844 passed/1skip across all89 browser-compatible original targets,
without changing assertions. Backend count84 expands the40 internal assertions
inside4 file-runner tests:48 reported Node test entries minus4 plus40.
VM skips the configured real-model smoke and browser-only IndexedDB test;
IndexedDB is covered by Chrome. No AI model was downloaded or loaded.

The final platform runner groups the original M05 security12/local-first8 and
M06 sharing56/realtime14 registrations. Plugin storage/key custody is real;
network/provider collaborators inside these scenarios remain documented doubles.

## Two-client fixture and reproduction

1. Start `python tool/m06_socket_fixture.py` on loopback8787/8788. Requires the
   existing Python websockets package; this helper is never deployed.
2. Start `npx tsx amplify/realtime/two_client_fixture.ts` on loopback8786.
   It uses the production DynamoSyncStore, ACL, ShareUseCases and RevisionRelay
   with TestDynamo, synthetic identities and an HTTP WebSocket publication seam.
3. Build/serve integration_test/m06_two_client_test.dart for Chrome with
   M06_CLIENT_ROLE=owner. Run the same target on emulator5554 with
   M06_CLIENT_ROLE=recipient and --no-uninstall, then read Chrome request_data.
4. Both actors' passed flags must be true. Restart only this synthetic fixture
   before another run; do not reset a real account, application or backend.

The clients persist local edits/outbox before HTTP delivery. The test observes
automatic owner→editor and editor→owner writes, disconnect/reconnect cursor
catch-up, a lost publication ACK, active role downgrade, backend direct-write
denial and revoke content masking. The owner's canonical note survives revoke.
Synthetic account namespaces are isolated from real user data.

This is local HTTP/socket acceptance, not live Cognito/AppSync authorization.
The socket fixture emulates the documented AppSync wire protocol. It cannot
prove the deployed auth modes, IAM policies, streams or GSI behavior.

## Excluded setup attempts and preservation

- First two-client fixture bound recipient as canonical owner; production
  handler already used separate owner/actor parameters. Corrected the fixture,
  restarted synthetic state and both clients passed. No product ACL was relaxed.
- Chrome89 aggregate compiler exited before tests during host memory pressure.
  The89 original targets passed after splitting into three disjoint groups.
- Android final platform startup found no emulator. User confirmed deleting the
  old SDK and requested reinstall at D:/tools/AndroidSdk. Existing AVD retained;
  no reset/wipe/uninstall. Earlier M06.4 native setup retries are in PROGRESS.md.
- The pre-existing macOS GeneratedPluginRegistrant SHA256 remains
  72E079184D14D8D03E86FB8928A90BC09F21E1D871F4F4B69FFF96030E67756B.
  It, final_project.md, browser logs, SDK archives and generated outputs are
  excluded from the source commit.

## Remaining provider gate

See [LIVE_GATE.md](LIVE_GATE.md). Final realtime rubric remains pending actual
AWS/Cognito/AppSync acceptance. Notion actual rubric has15/19 checked: all source/
local sharing requirements except FR07/NFR02/NFR03 and two-editor realtime
Done When, which await the plan's deployed provider spike. These local receipts cannot establish that the
entire deployed app is bug-free. Collaborator attachment/routes integration is
also deferred to the requested combined checkpoint before M09 planning.

## Dev configuration follow-up — 2026-10-03

After source/local checkpoint7fcefac, the composition root now accepts selected
public Amplify outputs through a build define, retaining the generated fallback.
.env.example and tool/m06_dev_config.py prepare local defaults/public config and
scope operator auth to an explicit backend child. See DEV_SETUP.md.

Additional scoped receipt: Python13 checks, VM2 composition runs (default and
selected outputs), Chrome2 matching runs, scoped analyzer clean and diff/formatter
checks passed. These are17 additional local cases, not a rerun of the full suites
in the table above. Fixtures contain only synthetic identities/credentials.
Private AWS fields never enter generated public defines; no AWS account, provider
test or deployment was performed. Actual Notion rubric remains15/19.

## Manual Share setup follow-up — 2026-10-03

The earlier config/main-APK startup receipt did not prove manual Share. Plain
flutter run uses generated Cognito settings; local auth mode has no gateway.
The new explicit `python tool/run_m06_local.py` launcher starts main_dev.dart
and loopback services, using two isolated synthetic users and production UI,
application/ACL/store/cursor/protocol paths. See DEV_SETUP.md for exact commands.

Observed browser flow: create owner note -> Share Editor -> recipient's
Shared with me -> recipient edit -> explicit stale editor review -> owner reply
-> Viewer update -> revoke removes recipient projection. Offline Chrome saved
an explicit local review with one durable pending mutation; going online
automatically ACKed it. Restarting both services retained the canonical note,
revision4 and the offline edit in the encrypted disk snapshot. A fresh installed
Chrome profile retrieved the same note through the actual Notes page.

Three main UI defects found by this flow were fixed: restored identity's sync
startup/controller lifetime, long status overflow and stale error after Use
cloud. These are functional repairs, with no M09 redesign.

Scoped current receipt: VM15 + real Chrome15, Python config13, HTTP dev server10
auth/origin/host/revoked read/write/manage/disk checks passed; strict backend tsc
and py_compile passed. Final root analyzer clean164.2s. Initial browser failures
exposed the fixed defects; earlier helper/test expectations were corrected for
Dart URI port normalization and offstage router pages. The Chrome tools overlay
rebuilt after a file-modified build notice; all15 scoped registrations passed.
Old debug pages emit DWDS websocket errors when their debug server stops; a
fresh installed Chrome run on final source had zero errors/warnings at startup.
Logs/screenshots live in ignored output/playwright and TEMP/m06-local-manual-*.log.

This batch does not rerun historical full971/844/platform90 suites or Android.
The two-user backend is a persistent SDK double with explicit synthetic auth,
not deployed Cognito/AppSync validation. Four live criteria remain pending, and
M09 remains deferred. Real-user sharing/email recovery requires the intended
deployment; local dev never sends recovery mail.
