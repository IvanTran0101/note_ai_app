# M03 actual Chrome / Android QA

## 06/10 — native PDF navigation and active lock

Corrected working APK27.1s, installed-r with retained data. Native PDF rendered
Page1 but inner drags competed with outer editor scrolling. Added explicit
Previous/Next/page count. Actual Next renders expected Page2/3 text/pixels, Next
reachesPage3/3 and disables boundary, Previous returnsPage2. Lock now while PDF
is open removes document/filename/controls and masks note. Protected WebP native
pixels also render correctly. Evidence m03-native-pdf-page2-painted.png and
m03-native-active-pdf-lock.png. Portable controls VM5/Chrome5; initial RawTooltip
test type cast corrected. Three scoped brace lints fixed; analyzer3 clean6.5s.
No full M03 acceptance yet.

## 06/10 — camera video and picker feedback

e0411dc matching APK installed-r/cold start preserves all notes. Actual native
fake-MIME and21MiB TXT reject with visible feedback; Documents cancel creates
no draft/error. Gallery PNG and camera JPG72450bytes reach Ready. Camera cancel
preserves the four Ready files. Camera video initially returned H264/AMR-NB;
even explicit quality1 was ineffective, so the preset approach was removed.

New Android camera-only AMR->AAC adapter tested by actual Record video/Done:
5th file4def5093...mp4 reaches Ready/All synced. Deliberate native export is
926703bytes; ffprobe H264/AAC1280x720/14.954356s. Real Play reaches14s end and
paused slider seeks14->4s. Original camera selection and normalization scratch
are cleaned after staging (owned scratch directory empty). UI screenshot
m03-camera-normalized-ready/playing/seek.png and native-camera-normalized-export.mp4
are ignored QA artifacts. This actual run used the working normalization APK,
not a clean final HEAD APK; subsequent resource-failure cleanup still requires
current build. VM14/Chrome14 over3 focused targets and analyzer3 clean3.5s.
Do not infer full M03 completion from this camera checkpoint.

## 06/10/2026 — current71a native offline / large / remove

Picker feedback fix: same-scope resumed native picker failures are presented
after lifecycle invalidation; current owner capability and captured session,
note identity/content/protection/access revisions must still match. No staging
or grant check is relaxed. Background Pending retries retain explicit selection
errors. Four new widgets cover invalid/denied/cancel/new-session; combined
VM32/32 and Chrome32/32 pass. Added explicit record type for strict inference;
scoped analyzer3 items clean3.8s. Final source rerun VM32/Chrome32 passed;
matching APK actual retest next.

Matching71a APK SHA2568EEFF931... (build35.8s/sourceDirty=false), install-r
preserves data. Protected cold owner TXT Download exports75bytes with original
SHA2569D467DD58D9B40F0D2246CCC21E5660158DED08AC95F4122DB0962E63714FCF0.

New QA-M03-Native-Offline saved through UI with Wi-Fi/data disabled and no ADB
reverse. Documents multi-select JPG/TXT/large MP4 gives3 encrypted Pending before
server create ACK. Cold stop/start keeps all3 and body; JPG renders and large
40s MP4 opens/plays/time advances/slider seeks offline. Reconnect/reverse8796+8797
and create ACK followed by retries yield3 Ready/All synced. Actual native export
of28,511,765byte MP4 yields SHA25639E568A52EF3FA09AD1A5BE83E4616CA32B9BD635720A6F26F331896FF3C7F8E,
matching original. Ignored receipts: native-export-qa-video-large.mp4 and native
offline screenshots under output/playwright/m03-20261005 / qa-20261004.

Remove TXT: Keep retains file; Confirm Remove reaches2 Ready/All synced and body
unchanged. Invalid chooser files create no extra attachment, but actual feedback
is absent after native lifecycle transition; investigation continues. Pre-create
ACK Pending retry incorrectly shows file/quota error. New typed waiting-state
fix +normal notice has VM29/29 +Chrome29/29; scoped analyzer5 items clean58.4s.
First widget harness blocked on a fake-clock queued read; corrected runAsync /
state assertion, not a product defect. Native still71a pending matching new APK.
Chrome protected TXT export attempt ended with browser closed; no acceptance
claim from that interrupted attempt. Current final UI/Chrome regression pending.

## Latest actual checkpoint — d45e02a and export forwarding fix

APK d45e02a built94.9s, sourceDirty=false, SHA256
2120A0B13B0DC502F93B7F2505B612B3B0DD70AA6F6BA09D3207BD250342E8A8.
Install-r/cold start retains prior data. Native auto-retries its original Pending
PDF, so both clients show8 Ready with All synced. Cold owner Download buttons now
exist. Native protected TXT preview shows expected75-byte content; body remains
the original text plus the earlier typed-retry marker. Protected MP4 renders,
actual Play advances time and the slider seeks from15s end to5s while paused.
Native PDF Page1 renders its expected fixture text; Page2 receipt remains pending.

Recipient Viewer and Editor render protected WebP through real UI but have no
Add/Remove/Download controls. Role change and then revoke while preview is open
close preview/mask note content. Prior revoked draft pending count1 remains;
no new mutation or silent old-grant replay is demonstrated. Browser screenshot
web-viewer-protected-webp-current.png records readable pixels before revoke.

Confirmed export failure: the runtime transport whitelist accepted only
attachmentRead/attachmentWrite, denying export even after the owner's verified
online unlock. Added owner-only export forwarding, preserving session/access
generation and M05 remote grant checks. New4 tests reproduce2 owner failures
before fix; current focused VM22/22 and Chrome22/22 pass. Unicode HTTP test-response setup and a
removed Response.encoding parameter and new-device masked metadata were test
harness corrections. Scoped analyzer2 items clean66.5s. Actual new
APK export/native/Web hash retest and final matrix remain next.

Direct Flutter Chrome test launches are not receipts: existing Windows test-server
URI bugs give CanvasKit404 and stripped test selector (confirmed browser console).
Use tool/run_chrome_tests.py --aggregate isolated tools overlay, preserving the
installed SDK. Own browser profiles and Android data survive temporary shutdown
for resource pressure; do not classify idle uiautomator's stale XML as product UI.

05/10/2026, final-tuankiet. In progress; this is not full M03 acceptance.
Headed Chrome owner/recipient retain their IndexedDB profiles. Android
emulator-5554 retains existing app data. Synthetic accounts and the local backend
exercise the real UI/writer/cache/transport/ACL code; AWS deployment is separate.
Fixtures/evidence are ignored under output/playwright/m03-20261005 and
output/m04-integration. No application database is seeded or reset for UI QA.

## Matching runtime

Source2930639 APK built527.3s, debug main_dev/android-x64, installed with -r.
SHA256:7D6B360FEA93CCF3A1C3FD1A1E35904596D72AA5DA8385F044D6ED5E9BB7B443.
Native data survived installation/cold start. New fixes require a new matching
APK before final native acceptance. Web runs main_dev at127.0.0.1:8776; fixture
8796 and relay8797 preserve encrypted local state on restart.

## Results so far

| Scenario | Current evidence |
| --- | --- |
| Existing M04 data | Chrome and Android retain old notes, pin/label state and protected masks. |
| Create/sync | Android creates QA-M03-Android with body; Back saves, reopen exposes attachment panel; Chrome receives same title/body. |
| Multi-file selection | Chrome selects JPG/PNG/WebP/TXT/CSV/3-page PDF/15s MP4; encrypted Pending survives Web restart. |
| Upload retry/ACK | After dev-composition fix, all7 old Pending files automatically retry, verify and become Ready; All synced. |
| Native picker | Android Documents picker selects QA files. ADB-pushed files require a MediaStore scan before appearing; this is fixture setup. Final native upload still awaits corrected APK. |
| PDF | Chrome renders Page1/3 with expected text; after dismiss-semantics fix, real Next page click renders Page2/3. web-pdf-page2.png. |
| Video | Chrome renders15s H264/AAC media; actual play changes paused true to false/time advances, readyState4; web-video-playing.png. Seek receipt still pending. |
| Image | Chrome JPG bounded preview renders; all image formats final screenshots/reopen still pending. |
| Export | Controlled-navigation/cache v2 retest downloads qa-text.txt,75 bytes, SHA256 matches source9D467DD58D9B40F0D2246CCC21E5660158DED08AC95F4122DB0962E63714FCF0. Large export/protected/native still pending. |
| Protected/shared/offline/remove/large files | Final actual matrix still pending. |

## Confirmed defects and fixes

1. Valid encrypted Pending could not upload in dev on either platform. Logical
   HTTPS API and staging loopback PUT lacked explicit composition support.
   Added debug-only opt-in, exact anonymous staging PUT whitelist and preserved
   abort signals through API rewrite. Focused VM16/Chrome16 passed, then
   combined composition/transfer/semantics VM28/Chrome28 passed. Actual Chrome
   retry of7 existing drafts passed. Native retest pending.
2. Center-peek dismiss barrier's full-screen tap semantics merged over the
   editor and blocked iframe controls with accessibility enabled. Excluded
   only the barrier semantics; Back remains accessible. Actual PDF page2 click
   and focused semantics regression pass.
3. Web download-attributed anchor bypassed the controlled child worker and
   downloaded Flutter's HTML fallback. Changed iframe navigation to use the
   fresh guarded stream's Content-Disposition; public cache v2. Actual TXT
   download filename/size/SHA256 pass; browser reports no download failure.

## Harness / runtime limitations

An offscreen iframe must be brought into the Flutter editor viewport before
clicking its controls. Offscreen timeouts and a mistaken click on the dismiss
barrier are not counted as product defects. Flutter hot restart while a platform
view is open raised a disposed EngineFlutterView SDK assertion; cold reload
restores runtime, without a demonstrated product cold-run failure. Public
viewer cache contains viewer assets only; private bytes remain encrypted in IDB.
Do not count successful adapter doubles as actual UI or deployed AWS evidence.

## Protection/attachment integration — continuation

Cold Web reload retains the seven linked files and the locally protected note.
Unlock preserves its original body/metadata. A protection payload containing
attachments but no labels incorrectly selected legacy v1 route/encoding, which
correctly failed422 at the backend. One shared typed decision now selects v2 for
attachments or labels, including empty unlink; legacy text-only bytes unchanged.

The already-rejected mutation also remained blocked after explicit Sync
protection, and a fresh edit queued behind it. Explicit owner protection retry
now unblocks only invalid protection+attachment entries, preserving stable ID,
frozen payload, createdAt, keys and retryCount. Automatic unlock and unrelated
invalid writes remain blocked. Focused VM11/11 passes; Chrome/actual retry is
pending. Initial new-test extension import, secure-storage mock and typed-empty
fixture setup errors were corrected; these are test harness errors.

Before this last recovery delta: full VM1190/4 configured skips, Chrome1055/1
configured real-model skip over123 targets, backend87/87, tsc/dev config14/14 and
analyzer clean103.2s. Do not add overlapping focused counts to these totals.

Native incoming Ready rows are confirmed after scrolling the editor: this was
viewport clipping, not a canonical sync defect. Old APK2930639 renders JPG/PNG
with expected fixture pixels; final receipt still needs the corrected matching
APK, native upload and the remaining protection/shared/offline/large matrix.

## Retest after interrupted runtime

The backend, emulator and browser processes were restarted with retained data,
profiles and encrypted fixture state. Original protection mutation has ACKed:
Web cold unlock reaches All synced with7 Ready and renders protected WebP;
Android independently receives the locked metadata and unlocks the same note.
Protected cached JPG is readable. UI image/text fixtures remain unchanged.

The later text edit initially received403 under the predecessor's reduced
scope, then full owner grant refresh retried successfully. Owner predecessor/
explicit protection retry now requests the full owner set on the first grant.
The first verified online owner unlock also omitted export, so Android had no
Download controls: export is now requested only for canonical owner. Recipient
scope set and domain policy still deny export/attachmentWrite. Focused VM12/12
passes with a first-online-owner regression. Chrome12/static checks/native retest
are pending. Native still2930639, not final corrected APK. No full M03 receipt.
