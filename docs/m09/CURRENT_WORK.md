# M09 current work

## ACTIVE — six-agent reference UI implementation (19 October 2026)

The user has now resumed implementation and explicitly requests up to six
Luna Max agents. The previous documentation-only request is complete. Lead
owns direct Notion Web/Android comparison, shared tokens/config/integration,
source review and final evidence. Disjoint ownership and working state:
AGENT_IMPLEMENTATION_20261019.md. No visual percentage is yet established.
UI>=95% on BOTH platforms remains a hard prerequisite for broad functional
regression/acceptance; do not inherit the rejected96.2 scores.

### Latest candidate — continue UI refinement, no acceptance

ACTIVE22/10: Chrome31 offline export also downloaded exact67B/hash; network
restored. New paired app images uploaded and board fetched17images/1childpage.
Main label/file/controls ticks succeeded; review/push still open. Theme renderer
map invalidation patch delivered by priority28_review; root reviewed and focused
production RichNoteEditor theme-switch test1/1 PASS, retains state/node/key/
selection/keyboard-service/focus. Initial test finder matched caret too; narrowed
to width3 marker before rerun. Actual new theme patch not yet packaged/runtime.
APK33 diagnostic a9346e44...caecbb installed-r; service.init log appears, but
neither parent nor child pan callbacks fire at visible handle (right265..306,
y653..694 physical). So prior parent-pan explanation is NOT confirmed. VM handle
test fails before hit assertion because UniversalPlatform reads actualWindows;
no supported override. Drop newly authored unsupported test; no fake skip/pass.
header_history28 now investigating parent/child pointer-down and bounds only.
All debug M09_HANDLE diagnostics still MUST be removed before publish.

LATEST22/10 candidate31: 1053-path runtime65e9ce70...e6070; analyzer clean91.7s,
Web82.7s/APK39.3s, drift[]. APK9932dee65e005a81badfefb63ef53a28f6bcec7f808bfd284e3b06e4c38c9fdb
is byte-identical to installed30; device hash verified. Static31PID23012/8776.
Actual FIRST open through v4->v5 update now uses correct Light CSS/min48 and
mouse export WITH semantics downloads67B exact96fbf4c9...ecc7278, failure:null,
page/console errors[]. No forceclick, worker bypass=false. First reload raced
server startup (connection-refused); server200 verified and Chrome loaded31.
30 cacheReload fixed v4 cached assets, but iframe still loaded old CSS before
activation. 31 explicitly awaits registration.update before choosing candidate;
offline rejection only permits an already activated worker. Post-return updates
still fail closed/reopen; no atomic iframe-handshake guarantee.
Native30/31 longpress visibly shows blue range handles above IME. Drag attempts
left range unchanged and hid formatting rail: NOT a passing drag check. Agent
header_history28 added TEMP assert-only M09_HANDLE parent/child pan logs to two
engine files; no text/IDs/tokens. Root reviewed; MUST REMOVE before commit.
32 source331ee5ac...3a9ca frozen/build66313 running; root also split bridge
session registration/URI/cleanup into small helpers (same authority/cleanup).
Next: actual31 Light->Dark same iframe, install32/log drag, bounded fix/remove
diagnostics, focused retest/current package, upload actual paired images and
push UI checkpoint. Both95 gates OPEN; no broad regression/acceptance.

CONTINUE22/10 source30: source29 generic semantic overlay is fixed in real
Chrome (iframe owns pointer hit; normal click accepted with semantics enabled).
First export during v2->v3 worker upgrade returned403; after reload the same
67B synthetic file exported with exact SHA. Root source30 fixes single-flight
worker lifetime, waits for pending worker activation, retries lifecycle change
once, and cleans local sessions/ports even if postMessage throws. Independent
Luna review found no concrete new regression; a later update after handle return
still fails closed and requires reopening (no atomic iframe handshake claimed).
Actual29 Light theme changed the live iframe data-theme without replacing its
handle, but cached v3 CSS was stale/blue while network29 CSS was new/neutral.
Source30 public cache v4 uses cache:reload requests for its allowlisted assets;
must verify actual installed CSS, first-upgrade export and fresh light/dark PNGs.
Native29 font_scale2 file menu is readable/no overflow in real PNG; file/More
48dp at font1, three-button and gesture captures. Restored font_scale1.
Header_history28 now owns ONLY native handle style + focused test, while root
owns bridge/media assets. No overlapping writers. Both95% gates still OPEN.

LATEST22/10 — priority UI candidate29 is in progress; source28 packaged and
actually exercised. Read PRIORITY_UI28.md for scope/references and current receipt.
Root current branch final-tuankiet, publishedHEAD still ed64394; source23-29
and reports remain uncommitted. Preserve unrelated .playwright-cli/final_project.md.

28 analyzer clean97.8s, Web74.5s/APK84.9s,837 runtime paths source09ba42ce...cac11;
APK d145ba1145ead4887e8623558061e8f9d40b29d31a746ac9414758f549f55fa5
installed-r and device/local SHA matched; drift[]. Static28PID32208/8776.
Fixture8796/7/8 and AVD5554/5556 running, reverse ports restored; data retained.
Root13/13 VM UI cases passed(file4/control3/menu2/label4), after fixing extra
keyboard focus stop on quiet Add block wrapper. Header_history28 delivered;
root reviewed menu custom PopupMenuEntry, conditional Delete and guarded history.

Actual28 Chrome and Android: label chooser/attach, flat file/menu, TXT preview,
Download, Add block and Undo/Redo exercised. Both exports67B have SHA256
96fbf4c9f79c7137d7f3c424b45ac08fb21ee21f344dfe6b74cb815a0ecc7278.
Chrome normal mouse download succeeded; Web history marker UI28 was undone,
redone and undone again; native paragraph->H2->Undo->Redo->Undo restored.
Two clients intentionally/accidentally edited same label baseline concurrently,
producing expected conflict; Web Resolve/Use remote cleared it before continuing.
Do not classify this test-created conflict as a product integration regression.

IMPORTANT browser setup: keep Network.setBypassServiceWorker=false for media.
Bypassing SW creates a host reload loop because viewer requires its own narrow
worker. Disabling HTTP cache is fine; do not disable/bypass worker or security.
Earlier timeout was not a failed download proof. With SW restored, normal mouse
export succeeds. However semantics-enabled editor has a real large generic tap
node covering iframe controls. Live elementFromPoint confirms full-document
720x676 semantic overlay; no force-click/bypass used to claim this path passes.

29 root edits: file target exactly48dp native/font17, honest terminal read status,
export viewer100px, theme-aware public viewer CSS (preserving iframe sandbox,
capability and access owners). Cache public viewer v2->v3 for updated stylesheet.
Agent priority28_review delivered Web-only excludeFromSemantics:kIsWeb on generic
SelectionGestureDetector; root reviewed per-block semantics and corrected new
focused test APIs/focus/semantics lookup. Native behavior remains unchanged.
New semantics VM test1/1 passed after test corrections; other13 passed with29
row changes. Chrome focused14/14 PASS, exit0 via output/m09/run_ui29_chrome.py; no skipped
cases. Native C++ hook completed normally before Chrome tests loaded.
Original ignored M05 aggregate restored in helper finally; verified SHA
57AAFEBE1CBABDAD042B03CB4FE481944DBA62FB7CD9B62694DD8AAAEBCF66D7.
29 first analysis completed154.8s: only2 deprecated hasFlag test calls; product
scope otherwise clean. No29Web/APK yet. Test now uses flagsCollection; runtime
1053-path fingerprint unchanged6ea5572b7f6269e30f9c7339aaa876c71f0838bd583fdb1e2f4ec50dfd0a6675.
VM API-cleanup retest59006 completed1/1 PASS. Final test-only analyzer clean15.6s.
29 packaged: Web78.6s/APK51.4s, no runtime drift. Installed-r and device/local SHA
match d11b4608c427fe6936a88c40d9d535b32b481647a7a59ba3a594de68c6e7d4d1.
Static29PID42440/8776 (old28server stopped after identity check). Chrome29 reloaded
SW enabled and Flutter semantics enabled, dark. Android29 file row/More target
126physicalpx/2.625 =48dp confirmed; gesture and3-button captures exist.
Actual29 iframe pointer and theme/narrow checks are now in progress.
Old manifest bounded Dart/assets subset and did not include host.css.

Direct Notion22/10: Web file1280x720/dark, file/menu captures; native0.6.4222
1080x2400/420dpi/Light/gesture, normal Media>File picker, synthetic67B only.
Current idle Page Actions>More Web did not show history (don't claim otherwise).
Native rail Redo precedes Undo. Board new refs uploaded/inserted and fetched (15images/1childpage); preserve existing13images/1childpage. Main first inspection tick
and progress update succeeded. Both overall95% gates remain UNVERIFIED.

NEXT: finish build29 session20709 (source frozen),
install-r/hash, restart static8776 to29, verify iframe click WITH semantics,
light/dark/narrow native target/safe zones. Upload paired29 app images, update
Notion and push explicit UI checkpoint. Then resume remaining M09, especially
native selection handles (desktop EditorStyle currently hides them; diagnosis
only, not changed), full matched state matrix, both95% gates, THEN broad QA.

24 packaged/installed-r: source835/6b894b6bd7b061d5e0288f1b8cb29b7dc28b4b8f581c822d3a62607787b355a3;
APK a7c3b04ad7d78f22d5c6e1c90338116acee193635fb6bcbaaa2026b7e8ab3a2f;
analyzer clean186.8s, Web80.4s/APK68.2s, drift[]. Native selection dialog
options previously36dp now have a32dp content minimum plus16dp padding =48dp;
large text may grow. Web keeps its compact rows. Actual24 validation ongoing.

25 source frozen: Web Settings title26/w600, helper13, standard input density
and single down-chevron after fresh direct Notion Preferences DOM inspection.
Ref title26/32/w600, label14/20/w500, helper13/18, selector28px. Notion's full
Settings route is1332px at1480 viewport (includes sidebar); older900px note
does not describe this current full route. App keeps its reduced existing
settings set/900px pane as an explicit adaptation; no new settings features.
25 helper first failed before build because old8 source manifest had disappeared;
rerun derives the835-path manifest from24, runtime source unchanged by recovery.

Focused chooser4 Chrome cases still NOT EXECUTED: direct runner CanvasKit/path
bootstrap failed; existing helper+official SDK CDN stalled before Chrome/test
loading, then interrupted. Agent's temporary8780 server after a policy rejection
was a workflow deviation and is stopped; do not restart/bypass. No product pass
or failure from these attempts. Prior focus/padding6/6 remain historical21.

Fresh native Notion24 Settings briefly showed spinner-only while XML retained
underlying cached controls: those PNG/XML are NOT matched visual evidence.
Ordinary force-stop/relaunch retained data and restoredHome; root recapturing.
Named earlier native ref PNGs are now absent locally (board-uploaded pairs
remain). Do not claim their current existence or reuse a loading image as ref.
Native24 Search query and gesture grid23 captured; both95 gates still OPEN.
ed64394 Notion progress receipt8737955a8e0e4725b909213ad1fefa3b succeeded.

23 packaged/installed-r/hash matched: source835/0b75eff7ad1c211d08a9a95c3d966f85c906d58714242c4784219e16d9fd4ed0;
APK d5f2aa21910660dfb1e04e672bc4f12ce7d49c739520c0bfd4cd5bbb36922ee6;
analyze clean152.2s, Web66.4s/APK37.9s, drift[]. Static23PID30060/8776;
server200 verified beforeChrome reload. Native23 Theme sheet actual clean
portrait3button capture app23theme-light-threebutton.png: previous green frame
absent; historicalcause remainsunknown, no image pixels modified. Header/group
anchors now match ref afterDEV52.5px; navbar surface paints light with controls
above it. Rows keep48dp targets (ref about45dp, explicit accessibility adaptation).
Current23 Web editor captured; menu/selection/remainingdialogs ongoing. Focused
chooser4case Chrome test launched33885, no result yet; no pass claimed.

22 Theme landscape/font2/3button REAL capture is
app22theme-landscape-font2-threebutton-real.png, all3choices/Done inside safe
left128/right126. Earlier similarly named without-real was HOME PORTRAIT after
system-overlay recreation; invalid as a theme/landscape receipt. Do not reuse it.

21 October progress22 published: final-tuankiet local/remote both
ed643949a6100780fc466e95849a944ae688a50c (98 explicit UI/fonts/docs/tests paths).
Unrelated .playwright-cli and final_project.md retained untracked. Credential
scan clear; authored diffcheck clean; original vendorOFL warning preserved.
Notion progress push-receipt update task8737955a8e0e4725b909213ad1fefa3b pending.

23 runtime FROZEN/build running: only native chooser header gaps/vertical
alignment and Material outside SafeArea (paint navbar surface, keep content safe).
48dp targets kept; header grows with textscale. Actual22 sheet comparison:
Notion title ink32px; app same font scale but header lower; adjusted handle/gap
by7dp and top-align title to match ref anchors afterDEV52.5px. No new choice or
callback. Root testing current22 landscape/font2 while23 builds; label captures
as22, not23. Both95 gates still open; remaining matched UI matrix before ratings.

21 October22 packaged/installed-r: analyzer clean80.7s; Web85.1s/APK90.4s;
835 runtime paths fingerprint48ead4784dc6e9e6d2a9967b3e3b9fbbff7251bb834697f7c75fe813e3419605;
APK6f010da8743955fb66231a90ffdc9bd69d104d8cc8fb2ace111aae15ae290079
matches device hash. Drift[]. Static22 PID20380/8776. First reload while Python
server started returned connection-refused; listener verified, retry succeeded.
First native capture immediately after launch had null UI root; discarded.
Current22 Home XML/PNG stable, existing data retained. Native currently gesture.
Lead now capturing new Settings chooser, toolbar and remaining safezone matrix.
Two interrupted Windows UI-test runs did not reach test loading; do not report
them as product fail/pass. UI progress checkpoint can publish with both95 gates
still open; it is not M09 completion or functional acceptance.

22 actual chooser now captured on native gesture: original Dark checkmark,
Done48dp target and3existing choices visible; choosingLight closes the nested
sheet and updates the parent setting. Sheet replaces the old right-edge popup.
Ref comparison still shows header vertical alignment can tighten; next23 adjusts
only handle/header gaps (keep48dp targets). Current22 captions/header fonts,
neutral palette and full-width surface verified; no whole-platform% yet.
Git checkpoint uses98 explicit UI/fonts/docs/tests paths, excludes unrelated
final_project.md and .playwright-cli. Credential scan clear. Preserve upstream
OFL license verbatim (one original trailing-space warning); authored code/docs
whitespace checked separately. No broad regression or final acceptance.

21 October21 built/installed before the user's next continuation: analyzer
clean133.9s; Web97.5s/APK50.8s; source834/b3280c730056069cc4bb1e252d3af54dac73614c17ba68a8d6b9534f350fe57a;
APKf98cce022831550320238b28ea7fb755f1295e8871b5273a6b62bafc13a2a359
matches installed device; drift[]. Native H-subscript/checklist/toggle glyphs
captured21. Updated focus test now supplies real parent onDirtyChanged setState
and stable GlobalKey; focus+padding6/6 pass. Web21 served before interruption.

22 source in progress: native_choices22 worker delivered native-only existing
Theme/Language sheet in common/note_flow_settings{,_choices}.dart and report;
no worker tests/builds. Root is reviewing, owns delivered files now. Root also
changed desktop H glyphs to subscript after direct Notion inspection.22 is NOT
built/installed. New continuation reset browser/runtime processes; restored
fixture29444, static21/10060, appAVD42236/5554 and NotionAVD16736/5556 without
wiping user data. Readiness still being verified. These PIDs are current only
for this resume. New Chrome uses same persistent profile/origin.

Notion board now contains a current20 native Search/ref image pair and exact
ink measurements; no percentage or threshold tick. Progress20 update succeeded.
Persistent thin green frame in19/21 whole-device captures remains unproven;
padding18_review is diagnosing read-only. Do not paint it out or call those
frames final acceptance evidence. Actual Notion native Settings now loaded,
Theme switched normally toDark and note/selection/IME directly inspected.
Broad functional QA and queuedM06 remain deferred behind both95 gates.

22 lead review: native caption16/w400, chooser header16 (actual Notion Theme
ink32px at420dpi), full available sheet with16dp top inset, original values/
enabled flags/callback, Web dropdown retained. Scoped5path analyzer clean135.8s.
New chooser UI test source covers portrait/landscape, textscale1/2, insets,
disabled item, Done cancellation and exactly one selection callback. Independent
static review found no blocker; barrier/drag/unmount/semantics test coverage
gaps remain. Windows focused run was interrupted before test loading (exit1,
NOT product failure): verbose rerun showed local_llm_bridge native C++ MSVC
hook compiling. Root interrupted this run too to prioritize actual UI22; no
test pass claimed. Prior21 focus+padding6/6 remains the last completed run.
22 build/analyze->Web->APK now running with835 runtime paths including the new
chooser file. Keep runtime frozen. Resume checks may use browser widget runs,
while full native-LLM/regression remains after both95 UI gates.

21 October20 packaged and installed-r: analyzer clean225.9s; Web91.8s/APK51.9s;
834 runtime files fingerprint8923c1a9bb34a159a6fa5415c0920399e96656ce71a1559cdbd574e507c0abd7,
APK4ca7a79d8695e321a67a3e6ab0b72b729ba2b0baa47044063d391ab606de8d0b,
local/device hashes match; source drift[]. Current20 captures confirm desktop
H1–H4 glyphs no longer wrap and semantics are plain Heading1–4; selection
popup is192px wide,16px from selection and adapts above/below. Native query
Search title measured463x33px versus actual Notion450x35px (same text),
left+5px; warm background matches. Remaining differences/adaptations recorded
in PADDING18_REVIEW_20261021.md. Native3button grid/IME captured20; additional
rotation/gesture/dark/scale states remain to complete. No green border after
normal20 relaunch; cause of old19 border not established.

Chrome20 focus: a click that leaves BODY is not valid typing evidence. After
confirmed TEXTAREA focus, the same connected node326 acceptedZ, retained focus
through autosave and later accepted the full suffix ' — M09 Focus20 stable'.
Earlier M-only observation remains unconfirmed/run-specific, not a proven
production defect or proof that the wrapper change is necessary. Direct-page
focus test omits production onDirtyChanged parent rebuild; agent supplied a
test-only harness proposal. Focus+padding6/6 and desktop Search-overlay1/1
focused UI tests pass; these do not substitute for visual evidence. Both95
similarity gates remain UNVERIFIED. Broad regression/M06 still deferred.

21 October20 frozen/build running: root reviewed both worker patches, corrected Search scope (query only) and added real Material Scaffold to new embedded-focus test harness. First focused run5pass/1fail was missing Material ancestor in the new test, not an accepted product result; rerun6/6 PASS (new-note focus+rich-state identity and5padding cases), no failure suppression. Root also fixed19 H1 glyph wrapping/duplicate semantics, and selection popup painted margin16px/adaptive placement. Actual19 Escape with established TEXTAREA/menu closes only menu and retains note; earlier exit observation notconfirmed productbug.19 menu/Share/password captures current, password initial screenshots were submenu/intermediate (not form); form has now opened.20 builds fullpresentation/main+engine+twoUItest analyze ->Web->APK; keep runtime source frozen until receipt. Workerownership finished; lead owns all files. Both95 gates UNVERIFIED, broad regression remains deferred.


21 October19 packaged: analyzer clean207.6s; Web71.6s/APK103.3s, source834/49d87d23012db6dfa343ab249923cb82e7cb24f877208d9b7c0ff460d81eb6fd, APK e540b10ce137cdd5db7f5ca9728e61c828a7a525ac702d3daaffedf5dd1121ea, drift[]. Installed-r; static19 PID16996/8776. Current19 UI still to capture.20 work in parallel: worker toolbar18_review owns ONLY note_detail_view.dart+new_note_focus_test.dart, fixes proven post-save title focus loss with stable root. Controlled18 repro: parent semantic click ->TEXTAREA empty; typeF->TEXTAREA F; afterautosave->BODY. Earlier blind textarea click observations are notproof ofinitialblur. Worker padding18_review owns ONLY DashboardPage/Content/Card, native Search style after exact matchedtitle darkink app546x41px vsref450x34px; query andlandingref fontdiff must staydistinct. Root owns allotherfiles/runtime/Notion/Git.19 artifacts immutable,20 notbuilt. No95gate or broadQA.


21 October current19:18 installed-r, runtime Web18, actual portrait-open->landscape grid now fills current safe width (128..2400px); bottom Quote/Table/Divider scroll reachable above gesture63px. Normal Share Web/native No recipients state loaded after async wait; earlier waiting snapshots were intermediate, not confirmed failure. Current18 pairs saved. Two new Luna Max reviews checked toolbar split/padding source; no blocker; copyWith null preserves callback as existing API convention.19 changes ONLY desktop Basic menu267px height/33px rows/caret gap16/glyphs, native Share title18/handle44 after actual Notion measurements.19 not built yet; both95 gates still UNVERIFIED. New-title Chrome first key only M observation queued for focused UI reproduction; first focus before typing was not observed, cause unproven.


21 October interruption checkpoint: source18 build DID finish before execution
was interrupted. Receipt output/m09/p6-parallel18-build.json confirms834 source
36f8f96aa69ae99564cd8db3306ed8abdf6d29ff44f901dd7feb34868cb7bcc6, drift[],
APK6893a91b5521edadb5e2a1cd64ac4830bd49082d1370012cb28e8340464f2a0f.
Analyzer clean201.6s; Web96.6s. APK duration not retrieved; don't invent it.
18 is NOT installed/visually verified. Last installed/captured app is17.
At the final read-only check, no8776/8796 listeners and no ADB devices remained;
the prior runtime PIDs are historical. Restore normally without wiping data.
The last Share click in Chrome was interrupted; inspect current UI before retry.
New synthetic NoteFlow note M09 Share UI21 was entered via clicked/focused
keyboard input; title/body UI confirmed, final save/Share ACK still unverified.
Do not treat Playwright fill on an unfocused Flutter semantics field as proof
of controller input. Actual typed body was UI share layout comparison.

Next after explicit continuation: restore local services/AVDs/Chrome profile,
install-r/hash18 and serve18, verify portrait-open->landscape menu width (18 now
uses unbounded maximum resolved by route), recapture toolbar after part split,
finish current paired UI matrix including Share/Settings/password states and
safezones. Update Notion with the18 receipt and current paired evidence, then
publish a verified incremental checkpoint to final-tuankiet. No staging/commit/
push occurred in this iteration. Both95 gates remain UNVERIFIED; broad QA and
queued M06 investigation remain deferred. All delivered runtime files now
lead-owned; no agents remain live after the session interruption.

21 October latest18 resume: runtimes/agents from the preceding active turn were
terminated when the execution session changed; files/data/artifacts preserved.
Lead now owns every delivered file. Six21 Luna Max reports and the Web worker's
padding API + toolbar split were delivered/reviewed; its final lint follow-up
did NOT run. Root removed exactly19 unnecessary-this qualifiers, preserving
constructor fields. No claim that the lost follow-up completed.

Packaged17 actually completed Web71.1s/APK41.3s/full presentation+main+2 engine+
new UI-test analyzer clean92.0s, drift[]. Runtime833 source
a376e73d0f0a70d324543396c759f208954aac11aecfb9f2103ef140006cb4fa.
Installed-r hash local/device dc499d8cec747feea17effa22f5415784ce68461e15da4fa40bd6dd245508184.
Clean rerun5 layout tests passed before the named-local-function lint polish;
the earlier8-path analyze had only2 test-style infos, both corrected.

Web17 capture uses1480x688 host with20px DEV strip clipped by browser screenshot
API: product viewport1480x668, same as actual Notion. Raw/product provenance is
explicit, no painted pixels replaced. p6-parallel17-web-rich-product.png now
places H1/H2/H3/paragraph and bullet/todo/quote within about1–4px of direct Ref
ink; not a whole-platform%. Home/Search/selection/Settings/Share captures exist.
Share Web's QA note showed waiting-server-confirmation after its local services
stopped; this is not a usable normal-Share pair. Preserve note and resume local
services before collecting a fresh synthetic Share UI. No broad QA started.

17 landscape regression: passing opening-context width held the portrait1080px
after rotation. Actual p6-parallel17-native-landscape-grid.png is still NARROW,
not a fix receipt.18 changes maxWidth to infinity, allowing route constraints
to resolve current width. Native17 note/grid/share + Web images are current17,
not18. Actual Notion native21 landscape grid is full width; Share settings was
reopened21 and inspected (private account image stays ignored).

Source18 adds selection_toolbar_dialogs.dart (guarded style/size/link/color
extension); original354 lines, part155. Root reviewed all moved guard/snapshot
callbacks; same capabilities. First18 analyzer stopped build on19 style infos,
NO18 artifacts. Root fixed them; new18 analyze->Web->APK running session51321,
helper output/m09/build_parallel18.py includes834 runtime files. Keep frozen.
Restarted hidden runtimes: fixture30000, static Web17 PID32656/8776, AVD launchers
26016/5554 and15620/5556. Actual readiness/unlock still to verify. Older session
IDs and process IDs below are HISTORICAL; don't use without checking live state.
Both95 gates UNVERIFIED. Continue UI, not queued M06/broad regression/acceptance.

21 October next17, not built: lead reviewed/accepted worker's optional
EditorStyle.blockPadding and both PageBlock branches (default padding preserved).
First focused5 widget tests passed, but hook printed file-modified-during-build
because later UI files changed while native hook compiled; clean frozen rerun
35366 now running then scoped8-path analyzer. Runtime source is frozen now.
17 applies zero outer padding ONLY Web bullet/numbered/todo blocks (actual
Notion list step30px vs app16~46px); native/all other blocks keep prior padding.
Heading Web top27/21/15/18 follows INK-to-INK deltas, quote bar uses theme ink,
Web checkbox24 +3verticalpadding. Desktop toolbar visible panel192px; Notion's
224px outer region includes16px transparent margins, directly inspected21.
Compact28px actions plus36px size keep approved extra size control in176px row.
Native touch48 unchanged. Native rotated Search now uses isCompact so the phone
doesn't open the desktop popup solely because its width exceeds600.

Packaged16 built Web76.4s/APK34.6s, drift[], installed-r successfully; local and
device SHA256 f973bbc154e053776b8ca51a144bc08dda70f3db5fe48aca38de75cdfa31e4a6.
Static PID12452/8776 serves16. Five-path16 analyzer clean78.0s. Chrome profile
was reopened after node-control timeout; same origin/data, bindings recreated.
Native gesture/3button portrait grid and font2 captured; header readable and
grid becomes1column at2x, no clipped header. Gesture landscape menu scroll
exposes Callout/Table/Divider; clipped final row scrolls, no overflow reproduced.
The first threebutton-landscape transition capture/XML was stale after dump
returned null root; INVALID, do not use it as current layout proof. Native
landscape menu still640dp centered; actual Notion landscape inspection ongoing.
Both95 gates stay UNVERIFIED. No broad QA or current-source Git publication yet.

21 October latest16: all six fresh Luna Max review agents delivered separate
reports (*_20261021.md). Lead reviewed their findings; Web box/range versus ink
coordinates were corrected, and nominal Search font-size advice was withdrawn
pending matched result-row evidence. No report opens either95 gate.

Packaged15 completed Web126.2s/APK493.0s; source833 fingerprint9005734f...cee5,
drift[]. APK b6ede374dfd6995fdcba3821aac0dd5462cec449d335e19645518b22b4b08faf
has required assets/fonts; NOT installed. Static server32248/8776 now serves15;
native55573 uses installed13 plus hot reload16. Both retain QA/user data.

Source16 frozen833/d82c9e0ec38ea2824dd8db1f80e16a72d3bee19a93723cb091a92ffd1eb0226b;
serial Web->APK build52255 running (output/m09/build_parallel16.py). Per-process
compiler temp uses ignored D: output/m09/compiler-temp16; no cleanup/deletion.
Web root heading height1.3 now matches inline style; Web checkbox28 high (native48).
Native block menu includes the existing48dp editor rail, localized Close, plus
label reflects its close-toggle action, and the Basic-block header grows at
large text scales. Mounted expired snapshot closes transient slash state.
Actual hotreload16 grid/close XML confirms menu opens/closes and QA body remains
Local first comparison. New package install and current safezone matrix pending.
Five-path16 analyzer49404 running. Both95 gates UNVERIFIED; broad QA stays queued.

Next: finish16 builds/assets/drift, install-r/hash verify current APK, swap Web
static root, capture same rich note and toolbar, compare actual Notion. Engine
PageBlock applies EditorStyle.padding PER BLOCK (currently Web8px vertically),
so list rhythm needs a bounded current-render comparison; do not shrink line
height or mutate stored formatting to compensate. MCP transport closed21;
current exact source reads are fallback, not fresh graph evidence.

21 October continuation: source15 freezes the current UI. New Web heading
font NoteFlowHeading uses unmodified SDK Roboto Medium/Bold/italic and its
Apache2 license, bundled offline. Native typography unchanged. Direct Notion
DOM21 measured H1/2/3:30/24/20px,600,line1.3; text advances132.85/110/91.66.
Previous Web13 rich headings were too bold/wide and vertically compressed.
15 calibrates heading line height/top/bottom spacing in the public builders.
Basic blocks native now uses a transparent modal barrier (same snapshot/access
guard), serif decorative heading glyphs and ref-like label spacing. The idle
native caret rail is hidden until IME editing; focus still exposes Add/Undo/Redo.
Both95 gates remain UNVERIFIED; no broad regression or final acceptance.

Runtimes were stopped between19 and21 October, data preserved. New AVD
launchers23264/28840 (5554/5556), Notion unlocked using authorized existing
credential. Native session55573 runs installed13 plus hot restart/reload15.
Fixture process2844/socket13512. Static server PID8/8776 serves packaged13
while15 builds; Chrome profile m09-chrome-owner retains IndexedDB. New
Flutter web-server92655 displayed white and was quit; static13 visibly works.
Do NOT call current Web screenshots source15 until replacing that static root.
Actual Notion native21 note and edit/grid captures saved locally; private
account reference images stay ignored. Actual Notion Web QA tab1/IAB2 at
1480x668. New Chrome node bindings appM/chromeM; error/request arrays empty.

Source14 Search typography calibrated further: title28 gives ink55..277/
y262..316, actual ref56..281/y208..263; after52.5px dev marker, top+1.5px.
Results16/preview13, existing sort moved inside white pill, outlined48dp close
outside.14 Home cards132dp/two lines/12radius/16gap inspected. Full presentation
analyzer clean127.7s BEFORE the later idle-rail and15 renderer/menu edits;
analyzer4781 and serial source15 Web->APK build now running. No APK14 exists.

The synthetic Web QA note persists H1/H2/H3, paragraph, bullets and an empty
to-do created through real UI19. First bullet currently reads 'irst bullet':
initial F was missed when typing immediately after menu conversion. Reproduce
with human-paced input before attributing a product defect; repair QA text
through UI. Complete task/quote and compare the same rich content to Notion.

Current source14 unbuilt: extracted DashboardRecentRail from the oversized
DashboardContent by card/rail presentation responsibility. Native cards remain
132dp square, now12dp radius/16dp gaps/two title lines and6dp lower top spacing
following actual Notion13 Home. Same note projection/open callback; card text
now observes the supplied readable predicate (same masking as main rows).
QueryNotes itself does NOT redact returned DTOs, verified current source; do
not assume unreadable cached titles are safe to render. Web List/Grid and
label selection use neutral washes, keeping callbacks/selection semantics.

Packaged13 source825 cade00add742b5308ac915d997fbe83520af9af20861a57b5a0712617b4be5b8:
Web138.0s/APK67.1s succeeded with required assets and no runtime drift. APK
c484d1ab42e840dd77760a81455c3df972e0386446ad58079fc55379d1a4dcf9
installed-r on5554 and device hash matched. Build targeted emulator x86_64;
archive also has dependency native libraries in the other ABI folders, which
is NOT evidence of testing physical ARM devices. Current source14 is newer
than installed13; do not mislabel its captures. No similarity gate opened.

Current source13: Search presentation now labels existing pinned results as
Pinned, then Today/Yesterday/Past week/Past30days (selected Updated/Created
date); query, pin ordering and access projections unchanged. Extracted only
the section-label responsibility into dashboard_search_sections.dart. Real
Chrome p6-parallel13-web-search.png shows Pinned then Today,38px dense rows;
actual Notion Search no-preview600px inspected directly again. Settings
native reference now visibly loaded after scrolling to Preferences:
notion-native13-settings.png.13 uses its light249/248/247 background,48dp
header/back chevron and compact down-arrow selector. Native/Web hot reload
sessions15562/17956 active. Five-path analyze clean27.3s BEFORE final selector
icon/padding adjustment; final current-source package/analyze still required.
No new whole-platform percentage, acceptance, staged files or push.

Current source12:3 Share paths analyze clean22153;4 list/query paths clean46375;
NotesWorkspaceView clean35424. Native hot reload15562 and Web17956 include12.
10 Share actual capture p6-parallel10-native-share.png now top~223px minus52.5
dev=170.5 vs Notion ref~168, same light249/248/247, normal navbar background.
Web Share target456/dark37 follows direct current Notion DOM. Native Settings
captured p6-parallel10-native-settings.png; content/selector/rows still compare.
11 Notes rows18normal/13preview/compact gaps, inline one-row filters and neutral
Owned/Shared chips;12 folds All synced into a small icon alongside those chips,
removing the large separate status row. Actual p6-parallel12-native-notes.png
and XML show controls/labels/notes, no large status text in the canvas.

Git inspected: local/remote final-tuankiet both76bb3384847d1a739a7b769bde9a2a84254c1fd0;
no U paths. NO staging/commit/push yet. Prior dirty tests include obsolete1008px
Search expectations (current direct no-preview600),704px legacy form versus
current720px rich-column expectations; review them later with UI gate order.
Do not claim they pass. Previous workspace initial-refresh/save-focus fixes
and their tests remain in the dirty tree; reviewed but not run this continuation.
No new broad tests, no current packaged APK12. Continue reference UI work until
BOTH platforms have justified>=95%; no final acceptance or queued M06 work yet.

Current source10 adds Share surface calibration; native session15562 and Web
web-server session17956 (8776, source9 initial52.3s) hot reload pending. Native
Notion AVD32680/5556 restarted data-preserving, currently booting/locked; user
already authorized its existing unlock credential. Source103-file analyze22153.
Direct actual Notion Web Share measured456px/x923.84/top44/darkRGB37/radius12.
10 uses456px and dark37. Native Share fixed top64dp target minus ACTUAL physical
safe-top (both AVDs dumpsys report128px cutout/status, NOT assumed24dp). Compact
route now reserves top/sides, sheet paints behind navbar and its content takes
bottom SafeArea. Invite field light236/234/232/radius8/font16. Inspect before
claiming match; existing service/access callbacks unchanged.

Source95-path analyze clean. Matched title/body9 ink advances equal actual
Notion: first74..847, second69..377, body72..508; after52.5px LOCAL DEV strip,
title top+1.5/-0.5px and body+4.5px. Board now has actual Notion reference image
and corrected NoteFlow9 gesture note image; one too-early transition capture
is explicitly labelled INVALID (cannot replace image URL through exact MCP
search, but correct picture is above it). Never use that discarded list image
as title evidence. Fetch readback confirmed corrected/ref images and caption.

Native source9 on3button: valid note/IME/grid captures; controls above navbar.
Returning gesture DID restore installed7 layout (header191 vs181, title32 vs34)
in the same process5198. Hot restart15562 reloads source9; valid gesture9 note
captured AFTER fresh title-field XML, output p6-parallel9-native-gesture-note.png.
Current navbar gesture restored. NO current-source APK9/10 yet; build8 APK was
stopped, Web8 valid122.7s. Six agents are no longer available in live inventory;
their original deliveries were reviewed earlier; lead continues code/review.
No current-source commit/push. Both >=95 gates remain UNVERIFIED.

Current source9 refines native typography after matched synthetic text: actual
Notion QA title first-line dark ink x74..847/y283..364; source8 x69..796/
y367..443, including52.5px LOCAL DEV offset. Native body plain-text advance is
also approximately6% smaller.9 uses native title34/1.18, default body17,
gutter26/header48/editor padding4; Web title40/body16 preserved (body now uses
the bundled theme family explicitly). These are calibration changes, not a
verified percentage. Explicit stored range sizes remain unchanged. Five-path
analysis session69132 pending. Native interactive session15562 uses verified7
APK + hot restart current Dart; keep tty=true. After Android system navbar-mode
change, Activity recreation restores the INSTALLED7 kernel, so hot-reload source8
cannot be inferred from the filename of a screenshot. Source8 threebutton-ready
capture is actually restarted7 and NOT valid8 evidence. Current mode3-button;
restore gesture after its UI checks and hot restart again if needed.

Build8 Web completed122.7s, output/m09/p6-parallel8-web, source824 below.
APK8 was STOPPED during fresh native LLM armv7 compilation to keep doing UI
refinement through hot restart. No APK8 produced; do not claim build/install
success or use installed7 hash as source8/9 artifact proof. C12.5GB/D15.6GB at
last check. Final current-source APK build still required after UI refinement.

Candidate8 source824 fingerprint
4abfd751c0276701793d11882fb00d74c0c66595357a53f0ce13cdd60ba1482b.
Serial build session51340: output/m09/build_parallel8.py, Web then APK;
manifest p6-parallel8-source.json records the canonical-JSON hash algorithm.
Runtime code frozen during this build. Six touched paths analyze clean.

Native7 H2 failure traced: old RichNoteEditor was mounted=false when its sheet
returned. Shell MediaQuery.removePadding read the OUTER Scaffold context,
restoring consumed IME insets; detail viewport757.5dp dropped to172.8dp and
conditional scroll wrapping remounted the editor.8 reads body-context metrics
and keeps the bounded viewport's element path stable. Actual hot reload8 via
installed7 binary: H2 now changes text to24dp and enables Undo; Undo restores
paragraph16dp (native-fixed-h2.png/native-fixed-undo.xml). Guards/writer untouched.
Temporary diagnostics have been removed. Glyph H1-H4 fits its slot with separate
label semantics; Home selector is neutral; Web style row14px/T/chevron matches
the directly inspected Notion row. Full current artifacts still pending.

Flutter run without --use-application-binary caused an expensive x64-only
native LLM recompile, stopped without source/data deletion. For iterative native
UI, run existing verified debug APK with --use-application-binary and tty=true;
hot restart loads current Dart, reload subsequent edits. Session19957 detached.
Notion AVD5556 deliberately stopped after fresh direct QA/caret/grid captures
to free RAM for compilation; restart data-preserving for remaining comparison.
Both >=95 gates remain closed. Notion progress updated with fix and Web7 image.

Candidate7 source824 INCLUDING bundled Arimo font files/license/provenance:
825d6c6c637e4726f4243f04dbd0afb8948865bc41c4d38a16cbf74007374526.
Manifest p6-parallel7-source.json; serial pipeline13563 completed: Web95.6s,
APK41.4s, required font/manifests present. Installed5554 SHA256 matches local
56a36afb505c1d752709aaba266d84b7c573a8093b24cce50fcf63cf63720ddf.
After environment reset, restored preview8776 (PID31348), fixture18148,
NoteFlow AVD8352/5554 and Notion AVD3476/5556; no data wipe or cleanup.
All Presentation +main/main_dev analyze clean
95.2s after2 new multiline-if lint fixes; pubspec.lock unchanged. Font samples
include Vietnamese, em dash and required Latin glyphs; native font unchanged.

Actual6 Android caret rail is now visible above IME, but its OverlayPortal
semantics were absent in UIAutomator.7 uses a lifecycle-owned root OverlayEntry;
verify visible AND accessibility nodes.6 grid opens with2 columns/48dp targets;
choosing H2 on the synthetic note appeared to do nothing (text stayed16dp and
Undo disabled).7 makes the sheet own/pass its original guarded snapshot to the
same BasicBlockCommands; actual7 still does NOT convert H2 (Undo disabled,
body remains16dp). Lead debugging via Flutter run session69992: temporary
assert-only metadata diagnostics in rich_note_editor.dart must be removed.
Current unbuilt source also scales decorative grid glyphs to avoid clipped
H1/H2 and excludes decorative glyph semantics. Do not hide this gap
or open the95 gate.7 grid:310dp target panel,44dp card inside48dp hit region,
52dp row pitch, native header48; compare current capture before rating.

Direct Web typography evidence: Notion QA h1 range655.625px at40px/700; installed
Chrome Arial653.535/Segoe UI654.336 versus previous narrow fallback.7 bundles
unmodified official Google Fonts Arimo (OFL) for Web only. No runtime font fetch;
Actual7 real Chrome image p6-parallel7-web-note.png, compared with actual
Notion Web at1480x668, now matches the title advance much more closely.
No similarity percentage is established. Font provenance in assets/
fonts/arimo/README.md. Actual6 Web title was narrower than Notion; no % claim.

Candidate6 source818 fingerprint
5e428c43f768781c83e81519daabc28938832cfe8cad146ffad4a88d44fabf15.
Manifest output/m09/p6-parallel6-source.json; serial Web->APK pipeline49194
running. Includes native Basic blocks two-column grid (same13 choices), flat
full-width selection rail, native caret-controls portal above IME, compact
More/header/Settings, Home249/248/247 and shell safezone refinements. Split
rich_note_editor_overlays.dart by overlay responsibility; native_editor_rail.dart
and basic_block_grid.dart are presentation-only helpers. Static analyze6 paths
clean6.0s after replacing deprecated OverlayPortal constructor; broad regression
has NOT resumed. Own guarded touch sheet must keep slash.snapshot until choice
returns; source fix preserves it while dismissing unrelated overlays.

Candidate5 Web87.0s/APK41.5s succeeded, fonts/manifests present. Installed5554
local/device SHA256e9028aea2b57d8aa642573d811b1f74766edcab0cc46d3d9ab46a6855c4058e7
matches. Source815 0f3da233a5bcb1a62d6a12df9964c81fdec670935ee57a769331c8923aae1fca.
Actual note and More captured output/m09/p6-parallel5-native-{note,more}.png:
header Back + Sync/Share/More; security/Ask notes/Summarize/Delete in More.
Selection5 is still rounded/inset, caret controls not visible above IME; candidate6
must be inspected for both. Candidate5 static9 paths clean35.1s.

Candidate4 Web236.8s/APK69.1s succeeded. Installed SHA256
3ee70204be5ffa0612377c814b2c43b072ed6a1604792a3e453bf96bf0f0bd24 matched.
Native fullscreen Settings capture output/m09/p6-parallel4-native-settings.png;
Web Search/Settings output/playwright/p6-parallel4-web-{search,settings}.png.
Scoped6 paths clean32.4s after2 MaterialStatePropertyAll deprecation corrections.

### Direct references and remaining comparison

Notion Web logged in via IAB qaNotion tab2;1480x668/dark. Direct measurements:
sidebar270/header44, column720, title40/48, body16/24; Search600/top60 WITHOUT
preview pane (1008 included excluded preview); selection224/3 compact rows;
slash324x289/34rows; Share458/top44; Settings content gutter60/64 and outlined
150x28 selectors. Actual Web candidate2 selection and opening Settings verified
overlay no longer covers/intercepts dialog. Current preview server8776 PID35952
serves candidate5. Browser appM real Chrome uses output/playwright/m09-chrome-owner;
preserve origin/IndexedDB. Restart exact server for6 AFTER Web build completes.

Notion native5556 API35/1080x2400/420dpi updated0.6.4222. Current AVD PID17116
host GPU, no-window/no-audio/no-snapshot; data preserved. This specific session
now renders and edits synthetic QA page M09 UI comparison Android, body
Local first comparison. Actual captures output/m09/notion-qa-{title,body,
selection,blocks,blocks-lower}.png: full-width formatting rail directly above IME;
Basic blocks light249/248/247, two-column48dp cards. Page/Link to page/Media/AI
are excluded. Slash typed via ADB remained literal; + opened actual block grid.
Previous valid Home/Search/Share captures notion-native-*-oct19.png and Settings
notion-gpu-settings.png / notion-settings-gpu-scroll.png remain supporting refs.
Do not confuse old Loading/XML-only captures with visible reference evidence.

Next: inspect candidate6 current Android caret/selection/grid choice, Web editor/
menus/Settings; create matching synthetic content if needed. Refine actual gaps;
verify Android gesture AND3-button/IME/landscape/font scale. Both >=95 similarity
remain UNVERIFIED. No queued M06 defect/full regression until both meet UI gate.
No iOS environment: no iOS safezone PASS claim. No current-source commit/push yet.

### Agent delivery and environment history

Actual6 Luna Max agents delivered disjoint initial patches. Follow-up shell,
dialog and independent-review turns hit model capacity and made no new edits;
lead took ownership/review. Do not claim those follow-up reviews ran or spawn
more than6. Ownership map AGENT_IMPLEMENTATION_20261019.md.

Candidate3 Web190.5s/APK737.3s serial, required assets present; installed SHA256
49115E4E16F7A9834DA27B35523C8CA8F7E5FB485FA161B5FAAEFE3DB4F8731B matched.
Candidate2 APK built734.6s/hash36DA25E4...67872 but MISSING font manifests/assets:
INVALID visual evidence. Overlapping Web/APK staging is suspected, not proven;
all subsequent builds serial with ZIP asset checks. Pub get restored user-deleted
.dart_tool, pubspec.lock unchanged. Never run parallel Web/APK builds.

User freed disk; latest verified C13.7GB/D16.63GB. No deletion/archive/AVD move
performed by us. Automatic policy blocked generated runtime-temp ZIP+cleanup;
do NOT retry another cleanup path. ADB deep-link start to the known synthetic
Notion URL was also blocked; do NOT bypass using another URI/tool. Normal
native UI navigation is available. Existing user unlock credential never goes
in project docs. Native GPU cold boots improved specific captures; no general
Notion rendering fix claim. Epochs matched; no time settings changed.

## AUTHORITATIVE NEXT STEP — REFERENCE UI, NOT ACCEPTANCE (19 October 2026)

The user says the current UI is NOT similar enough. Previous Web96.2/100 and
Android96.2/100 ratings, the57.2/60 visual-group calculation and the conclusion
"UI threshold reached; resume acceptance" are WITHDRAWN. Notion score ticks
are reset. Current similarity on BOTH platforms is UNVERIFIED / NOT ACCEPTED.
The metric is now UI SIMILARITY IN %, never points converted to percentages.

Historical documentation-only turn (now complete): Notion first, then MUST_REMEMBER.md and
related docs; no UI code, tests or acceptance now. On the next "tiếp tục":

1. Read MUST_REMEMBER.md, this section and VISUAL_REVIEW.md before code.
2. Recheck the checkout/dirty state; preserve all uncommitted source, unrelated
   .playwright-cli/ and final_project.md. Current branch final-tuankiet, base
   76bb3384847d1a739a7b769bde9a2a84254c1fd0; source delta is NOT published.
3. Open actual Notion Web AND the actual Notion Android application. Inspect
   matching screens/states and interactions; narrow browser mode cannot stand
   in for the native app. Verify browser/AVD/app access then; do not assume old
   process IDs, sessions or logins remain alive. If access is missing, record
   exactly what is missing, keep the similarity gate open, and continue the
   independent UI comparison work possible on the available platform.
4. Compare NoteFlow directly, using hinhanh/UI_web_ref and UI_android_ref as
   supporting images. Record paired reference/actual captures, time/build,
   viewport/device/DPR/theme/insets/keyboard/state and concrete differences.
   Refine existing UI until Web>=95% AND Android>=95% similarity with evidence;
   do not invent a %, average platforms or hide a visibly mismatched screen.
5. Android safe zone: bottom navbar for gesture AND 3-button modes; toolbar,
   sheets/buttons/final scroll content above navbar and IME, no double inset.
   iOS safe zone: top status bar/notch/Dynamic Island, retaining bottom Home
   Indicator clearance; no iOS test evidence means still unverified.
6. HARD GATE: do NOT resume functional defects, broad regression or functional/
   final acceptance until BOTH platforms meet >=95% similarity. Do not self-
   accept halfway. Only then return to the queued cases below, fix/retest and
   update/push verified milestones. Existing features only; local-first and
   security guards unchanged. New capability needs Notion proposal + approval.

Notion comparison/status: https://app.notion.com/p/3f7f9c7a1aa0816ab867faaefb40454b
Progress: https://app.notion.com/p/3f8f9c7a1aa0817a8f08e793aaaae83d
Main M09: https://app.notion.com/p/3e9f9c7a1aa080bb85a8d4973595bc21
Editor plan: https://app.notion.com/p/3f5f9c7a1aa0817f9e0bdbe52bb091fe
Implementation plan: https://app.notion.com/p/3e8f9c7a1aa0810ea410c5dc6b6bb7c8

### Documentation update receipt — 19 October 2026

Updated and re-fetched all five Notion pages linked above: current top rule
withdraws the old ratings, uses similarity%, requires actual Notion Web AND
Android, records safe zones and blocks acceptance until BOTH>=95%. No checked
similarity-threshold boxes remain. Historical captures/test results retained.
Updated MUST_REMEMBER.md, CURRENT_WORK.md, VISUAL_REVIEW.md, REF_MAPPING.md,
P5_P6_ACCEPTANCE.md and the remaining-work order in P4_EDITOR_CHECKPOINT.md.
Documentation whitespace checked; no runtime edit/test/commit/push in this
documentation-only turn. All previous uncommitted work remains intact.
_agent_ops session tooling/records are absent in this checkout; no pack closure
template is available. These project docs provide continuity instead.

## Technical baseline to preserve — NOT UI acceptance

Final7 runtime812 source:
3cd1a6552278eba1599f9bbe1088a9a3c43154663f7f6f4bea064a4ba1b81214.
Manifest output/m09/p6-final7-source.json. Historical technical gates: VM1932
pass/5 configured skips/0fail; installed Chrome1735 pass/2 skips/0fail (206
original mains,17 Native/VM exclusions covered separately, local HTTP on);
analyzer8 scopes clean. These do not prove >=95% UI similarity. No new test
run or runtime source edit is part of the documentation-only request.
Web output/m09/p6-final7-web; APK output/m09/p6-final7-owner.apk, SHA256:
A64572C10D80AAF202C646BAC5EF12581DA06B3763B47B003318C4B9C841EB3A.
Device hash matched during prior QA; verify again before relying on a future
installation. Existing actual table typing/Web-Android sync evidence remains
historical. UI6/visual5 images retain their original build identity.

## Functional queue — ONLY AFTER BOTH UI similarity gates

- M06 observation, provisional: owner changed Viewer->Editor for synthetic
  "QA M09 Functional 19"; recipient then showed a DIFFERENT existing shared
  note. No typing/mutation was performed on that other note. Investigate
  selected-note/navigation preservation during access refresh after UI>=95%;
  root cause is not established. Toolbar on the wrong note does not prove
  Editor rights on the QA note. Preserve all existing notes/permissions.
- Finish intended-note Editor/Viewer/revoke, offline protection and remaining
  functional cases, then current-source regression/fix-retest and publication.
  Do not start this queue on a bare "continue" while UI is still below target.

## Historical activity below — superseded next-step instructions

All old ACTIVE/Next labels, point ratings and runtime/process states below
are chronology only. The authoritative next step is the UI section above.
Historical tests/captures are retained, not silently relabeled as current UI
evidence or permission to resume acceptance.

### Historical final7 runtime and technical QA

Final7 Web64.1s/APK84.0s; installed device hash matches
A64572C10D80AAF202C646BAC5EF12581DA06B3763B47B003318C4B9C841EB3A.
StaticPID42200 serves output/m09/p6-final7-web on8776; fixturePID23108 alive.
Own NoteFlow_API35 running (emulatorPID25532), owner APK. Playwright context
visual95.ctx/page/cdp is real installed Chrome, profile m09-chrome-owner,1363x936,
default timeout5s. Node reset once after a harness timeout; current live bindings
fsFinal/cryptoFinal/rootFinal/pwFinal/freezeVisual(final7)/visual95 restored.
Synthetic note QA M09 Functional19 created via UI; initial too-fast title input
was missing, corrected with real click/Ctrl+A/type; note saved and survived
browser reload. No product save defect confirmed. Always confirm title value
and put caret in body before contextual block commands; use current snapshot.
Actual Web: inserted Table, typed Cell tieng Viet (accented) and Second cell;
saved/reopened, both retained. Add-row/Undo retained data; temporary status
needed longer than12s, later Saved/All synced confirmed. Native Sync now pulled
same table; tapped actual empty EditText bounds, typed Native cell, saved; Web
Sync now received it while retaining Unicode and other cells. Current table
functional path works; old memory's unresolved semantic activation is not a
current failure from this physical mouse/ADB test. Screens p6-final7-table-*
and p6-final7-native-table-*. The functional follow-ups are now queued behind
the19 October UI similarity gate above; no score carry-forward is valid.
Current owner Chrome sharing dialog has just been opened on this table note.

FINAL7 full gates confirmed on runtime8123cd1a655...b81214:
- VM1932 PASS/5 configured skips/0fail (4m37).
- Installed Chrome1735 PASS/2 configured skips/0fail (2m06),206 original mains,
  17 Native/VM exclusions separately covered, M09_LOCAL_HTTP=true.
- Analyzer8 scopes clean16.8s; new browser-only popup regression passes in the
  Chrome aggregate. JSON reporter saved p6-final7-chrome-results.jsonl.
Started final7 Web then owner APK pipeline p6-final7-{web,apk}. Own QA browser/
AVD remain closed; fixturePID23108/staticUI6 retained. Reopen final7 only after
build; recheck labels/style/actor transition and actual table-cell entry +
remaining functional protection/sharing cases. The old96.2 UI milestone is
withdrawn; functional follow-ups wait for the new similarity gate. No runtime edits after gates.

FINAL7 VM confirmed:1932 PASS/5 configured skips/0fail (4m37), analyzer8 scopes
clean16.8s. All3 UI6 failures resolved. Started full Chrome206 original mains,
17 native/VM exclusions separately covered, M09_LOCAL_HTTP=true, using existing
Windows URI overlay (installed SDK unchanged). Current report paths:
output/m09/p6-final7-{full-vm,analyze,full-chrome,chrome-results,chrome-matrix}.
Wait final Chrome result, then build final7 Web/APK and inspect affected labels
and remaining actual functional cases (including table-cell input); not done.
Source812 remains3cd1a655...b81214. No runtime edits during current gates.

Final7 runtime812 fingerprint3cd1a6552278eba1599f9bbe1088a9a3c43154663f7f6f4bea064a4ba1b81214.
Focused Dashboard+label run:51PASS/1FAIL. Both TextStyle actor-change failures
are fixed; the remaining test reaches a later outdated exact Text('Alpha')
expectation because reference Search now renders Text.rich('Alpha — Alpha body').
Both old title/body finder assertions now check that exact combined rich text;
strict width1008/height704/top78 retained. Runtime unchanged by these test edits.
Started full VM p6-final7-full-vm.txt and analyzer8 p6-final7-analyze.txt. Chrome
matrix prepared p6-ui6-chrome-targets.txt (206 mains,17 VM exclusions), update
receipt to final7 before running current source through Windows tools overlay.
No final7 builds or current broad PASS yet. Retain UI6/visual5 captures as
identified predecessor evidence until final7 affected label style is rendered.

### Historical final7 — regression repairs

UI6 full VM completed1929 PASS/5 configured skips/3 FAIL (5m06). The3 failures
are two actor-change tests raising TextStyle.lerp inherit mismatch, plus one
old desktop-search top65 expectation after the approved -20 offset (actual78).
Analyzer8 scopes reported2 infos (null-aware list element, unnecessary test
services import), no compile errors. Genuine Windows C++ native hook compiled;
no fake DLL/shim was used. Prior cold startup explains empty early log.
final7 now derives Manage-label text style from Theme.labelLarge (12px/w400)
to keep inherit parity during actor/widget transitions; null-aware syntax and
unused test import fixed. Geometry assertion remains strict but now78.
Source812 manifest output/m09/p6-final7-source.json; next focused Dashboard+
label tests p6-final7-focused.txt, then full VM + full Chrome206/17 exclusions,
analyzer8 and rebuild/review affected UI. The old UI96.2 source6 conclusion is
withdrawn and proves no accepted similarity. No branch push yet.

### WITHDRAWN — UI threshold reached / functional acceptance resumed

The previous Notion Web96.2/100 and Android96.2/100 self-ratings were rejected
by the user19 October. Score ticks reset; no current similarity% is verified.
MUST_REMEMBER and VISUAL_REVIEW now require direct Notion Web/Android comparison
and >=95% similarity on BOTH before any functional acceptance resumes.
UI6/812 source1bd1dc31503af418e9bc6000095fb699f10ce924ed08a805adc99f04b7a7d255
has zero drift. Web57.4s/APK59.9s; device/APK hash
7A9195B3EC54809D33F208A18BAE6D3D77BE661335B431941FB8DE7777061224 verified.
Actual Chrome popup previously losing text now preserves multiline and Unicode
after B/I/U/S/code+blue/save/reopen. Size49 rejected/28 applied; link retained
text; sqrt rendered; Undo restored exact Unicode. Native current rail scrolls
through Link/Equation/Clear; Divider/Undo returns Unicode71px+Saved/All synced.
Actual13 menu choices inspected via scroll; prior thirteen-conversion matrix
is identified predecessor evidence, not silently relabeled as current.
Current screenshots p6-ui6-*; Notion final Web/Native images uploaded/read back.
Browser-specific new DOM-input regression annotated TestOn(browser), because
the corrected branch is Web only. Native uses existing delta lifecycle and
generic editor suite. Earlier focused direct-Chrome run was stopped/no result;
must use tool/run_chrome_tests.py Windows URL overlay for the current SDK.
Full VM started p6-ui6-full-vm.txt, concurrency2. Own QA Chrome/AVD closed, their
data kept; Native settings restored font1/rotation0/accelerometer1. Next: inspect
VM result, full Chrome aggregate206 mains/17 VM exclusions, analyzer6 scopes,
then queued functional actual flows/retest and final Notion/push. No source
changes after UI6 freeze other than test annotation/docs.

UI6 source812:1bd1dc31503af418e9bc6000095fb699f10ce924ed08a805adc99f04b7a7d255.
Frozen output/m09/p6-ui6-source.json. Popup-focused automated check was stopped
before producing any result (p6-ui-popup-after.txt); no pass claimed. Prioritize
actual Chrome UI6 typing/toolbar/popup/reopen as requested; no further automated
loop before UI grade. Pipeline Web first then APK (p6-ui6-*). Own QA Chrome and
AVD closed for compilation, local fixture/static retained. Source6 differs
from visual5 only in Web focus/input-client release; Native branch unchanged.
Native5 portrait/font2 and landscape captures show no clipped layout; settings
restored font1, accelerometer1/rotation0. visual5 APK/device1C156774...2456F.

### Historical — UI interaction before former point review

visual5 now rendered on Chrome and Android. Exact APK/device
1C156774CB37139F372CD705157BECB192D67277E496084320A190DAB562456F.
Former V01–V05 calculation57.2/60 (95.33% of that group) is WITHDRAWN as proof
of adequate UI similarity; no current percentage has been established.
Actual Search5 is a compact list; horizontal filter and no spacer verified.
All6 uploaded visual4 images and2 visual5 images are visible on Notion.
To finish the full UI rubric, UX02 still requires correct toolbar/popup input.
This is a UI interaction correction, before any broad functional acceptance:
keyboard_service_widget._onFocusChanged releases Web IME client on lost focus
while preserving selection. Original before-failing regression already exists.
Patch now applied; next focused Chrome UI-input check and current build. Broad
non-UI regression/acceptance remains deferred until UI criteria reach>=95.

### Historical — 19 October, visual5 Search polish

MUST_REMEMBER UI-first rule read. No functional acceptance or full regression
run during this pass. visual4 Web and Android rendered; exact APK/device
AD166A4227F4B9EBFDA8A1AA57EDC55D99383F897DCBEF83761B8B9E04CE8960 confirmed again.
Source812 a32282c1...d189 has zero drift at restart. Images uploaded and fetched
back on Notion progress page (new19/10 section,8 image blocks including history).
Latest actual p6-visual4-* captures include note, Home, Search, Settings, Ready
share, password, selection, dark and Web390px VI Settings. All app data retained.
Native selection rail is48dp above IME, no16px overflow or covered header.
Actual Native Search still inherited Home Grid and excess whitespace. visual5
changes ONLY presentation: Search landing always list results, no spacer text,
single horizontal filter row; same query/readability/commands and Home layout.
Source812 88077fe6a162daf96ea8ba0bdae760dcb174341d56ceeaa3394b7bb0b2cb76f3,
manifest output/m09/p6-visual5-source.json; pipeline28768 APK then Web.
Closed own Chrome ctx and NoteFlow_API35 to free RAM while building; services
remain: fixturePID23108; staticPID22440 serves visual4. Node bindings live:
fsFinal/cryptoFinal/rootFinal/pwFinal/visual95 (ctx closed), freezeVisual visual5,
imageMarkdown95 with6 uploaded file-upload image sources. Reopen same profile.
Native last UI Search with keyboard; app theme/language System. Source5 must
render before scoring Search. Fixed11-criterion total remains Pending; do not
call the visual60 percentage a full100 score. UI popup IME loss remains queued.

### Historical UI-only pass — 18 October, visual4

Latest MUST_REMEMBER rule is recorded: finish actual reference UI on both
platforms before returning to queued functional regression/acceptance.
visual3 source d2f5568237a19aa66e9dd0bea2ac58c2fb96dce20f2dac0bcdab76b7a60afae2
rendered on actual Chrome/NoteFlow_API35; APK/device C90A4C7352BA0EDEB114F3C83BF0B3FFAD4A9A184AD9360C3477A5B59730ED14.
Recents moved above label filters, quiet metadata row, Settings/search/Notes
hierarchy completed. Actual Native selection revealed16px overflow and toolbar
covering header/title. visual4 fixes presentation: no duplicate engine padding,
48dp horizontal Native rail docked above IME; Web retains wrapped bubble.
visual4 source812 a32282c1b8e8ec306fef833b6725793ab6f017b3b614e685a83eb8b85b26d189,
manifest output/m09/p6-visual4-source.json. Build pipeline session87899, APK
first then Web. No functional regression run during this visual pass.
Fixture restarted session48475 (8796/7/8), static8776 session82069 serves visual3.
Actual Chrome persistent object visual95/ctx/page/cdp; synthetic Design notes
created through UI. Native installed visual3, Dark mode, selected text with IME.
Scores remain pending until new toolbar renders; full11-criterion total remains
separate from visual60. Known Web popup data-loss source fix still QUEUED.

### Historical steering — visible UI first, bug acceptance afterward

USER RECONFIRMED: keep going until UI meets the Notion criteria and BOTH Web/
Android reach>=95; only then resume the queued bug fixes/tests/acceptance.
MUST_REMEMBER now states this order explicitly. No functional test/debug work
is authorized ahead of the visual milestone in the active sequence.

Visual v1 built: Web139.5s, APK128.4s, APK5505249FF3FAC2768D43F7EEF0533D633DF80F7963846C1DF393D47CEEB64EC1.
Static8776 is nowPID28296 serving p6-visual-web. Actual Chrome visual95 object
has ctx/page/cdp/source/evidence; profile same owner. Current screenshots:
output/playwright/p6-visual-web-settings.png and p6-visual-web-search.png.
Settings renders the new clean rows as intended. Search revealed another
layout gap: loose Flexible date consumes half flex space leaving rows stranded
left. Source now fixes this with bounded trailing date on wide rows, date below
preview on narrow rows, denser inline preview for desktop search, subdued date
headings and compact input/filter spacing. These latest3-file edits are AFTER
v1 freeze; must build/freeze visual v2 before grading. NoteFlow_API35 booted
again (own emulatorPID31812), not yet installed v1. Do not run the bug regression.

CURRENT VISUAL812 freeze: output/m09/p6-visual-source.json; preview pipeline
p6-visual-web.txt -> p6-visual-apk.txt (Web skips unrelated Wasm dry-run).
Changes: adaptive Settings rows +account ListTiles; Notes title before query/
filters and no duplicate workspace AppBar; search input first, filters/sort on
one desktop row; calmer label styling;64dp wide selection popup,112dp compact/
160dp narrow/large-scale,48dp short-landscape; neutral20dp LOCAL DEV marker.
Only existing callbacks/capabilities. Current older p6-ui-* build was explicitly
stopped/superseded before acceptance so it is NOT a source receipt. Own Chrome
and NoteFlow_API35 closed for preview compilation; fixture/static retained.
Static8776 stillPID34792 serves original p6-aa-web (diagnostics removed).
After build switch this own static server to p6-visual-web, restart actual Chrome
and install-r/exact-hash APK, capture reference UI and grade V01–V05 first.

User: "chỉnh UI đến khi đạt điểm đi rồi sau đó nghiệm thu mấy cái lỗi đó lại sau".
Finish actual reference visual comparisons and V01–V05 before returning to
regression. No new tests/debug loops should block design work. Main current
visual gap: oversized filled Theme/Language fields/account buttons. New
presentation-only note_flow_settings.dart plus main.dart wiring implements
section rows, neutral dropdowns, fixed title/dismiss, adaptive dialog/sheet and
account ListTiles; callbacks/persistence/permissions retained. Build/preview next.

Recorded open editor bug: full selected text +B/I/U/S/code ->color popup produces
a spurious NonDelta IME delete from empty reactivated Web TEXTAREA. Before trace
is output/m09/p6-color-ime-trace.json. Pure formatting combo regression6/6 pass.
Temporary built-JS experiments: always republish equal value broke typing;
moving debounce cancellation alone did not fix. Closing Web input client when
focusNode loses focus (keeping selection) DID fix exact reproducer. New test
editor_popup_input_lifecycle_test.dart fails before at hasAnyClients false/true
on actual Chrome (p6-popup-before.txt). Source fix NOT yet applied: do after UI.
Original p6-aa-web/main.dart.js has been restored from p6-aa-main-original.js;
no diagnostics left in the served artifact. Browser bypasses service worker for
QA; original source914a gates1931VM/1733Chrome remain predecessor after new UI.
Installed APKBFEDF4FB...F5D7 is original914a, exact device hash verified.
Actual Native13 all pass/Undo Text height71/Saved+All synced, custom49 rejection
and28 paint/clear, sharing panel, protected mask/offline unlock and rotation pass.
Cases/captures p6-95-*; native settings currently open, System/System unchanged.
No score assigned yet. Node persistent pageO, ctxO, fsFinal/rootFinal/helpers live.

### Historical AA candidate — previous review order

Current811 fingerprint914a938cb583d78bf32773ccb688b0b8a0f8709ff700e14df558ea5027239c09,
p6-aa-source.json. Workspace light/dark muted/link/error colors had2 failing AA
regressions (shared palette already passed); corrected colors =>4/4 PASS.
No more speculative source edits: next actual Web/Android full acceptance.
VM59860(shell12944), analyzer90132(shell25280), pipeline waits then Chrome205
mains/17 VM-only exclusions -> drift -> WEB FIRST then APK, all p6-aa-*.
Previous6e665 source FULL VM1929/5skip PASS, analyzer clean246.3s; old Chrome
run intentionally stopped for confirmed palette change. Its earlier full run
1927 pass/2 failures was only legacy geometry assertions720/280 after approved
704/270 ref changes; corrected explicit expectations. All are predecessor logs.
Current AA full expected1931VM/1733Chrome; verify actual. Own Chrome and AVD
closed; fixture8796/7/8 retained; old static8776 p5-ref-final-web unchanged.
After new Web success, switch static8776 and run actual Chrome while APK builds;
then install-r/exact device hash Native and finish criteria. Record actual
screens/flows, separate honest scorecards and final Notion ticks/push. NO final
acceptance/scoring yet. User explicitly says do not stop until both >=95.


### Historical — previous points target, now replaced by similarity%

User explicitly requires continuing through both >=95 scorecards; no partial
checkpoint final. New current811 fingerprint6e6651bd844a125d2fbf1fd5c5650fdf60a8133f3fbb63913bf543979dccaa29,
output/m09/p6-95-source.json. Fixes: initial security/sync refresh now ends
superseded loading on success/failure (two before-failing regressions); pending
local ACK cannot replace Undo while saving (before-failing async regression,
including reentrant disposal); focused34/34 PASS. Password dialog neutral field/
lock heading; wide Web share transparent backdrop/y44 inset to match ref.
All existing capabilities only. No full M09 acceptance/score yet.
Current VM session45464(shell39944), analyzer28981(shell27144), pipeline waits
then Chrome205 mains/17 VM-only exclusions -> drift -> p6-95 APK/Web. All p6-95-*
receipts under output/m09. Chrome/AVD closed during gates. Fixture and old
static8776 (p5-ref-final-web) retained. Need switch to new build, actual full
Chrome/Android matrix, honest11 criteria each, final Notion ticks and push.


### Historical priority - 18 October2026

User wants visible reference styling now; avoid another repeated full-regression
loop before visual scope is settled. Continue existing-feature-only M09 work.
Local-first canonical writer/access guards and unrelated files stay intact.

### Historical visible UI checkpoint

Branch final-tuankiet. Runtime811 fingerprint
88194311c59324df3e5bed84cc5903b0317da823601978a7faefe116d279974c
(output/m09/p5-ref-final-source.json). This record is committed with that source.

Implemented: sidebar270/neutral selection/search field/New note header icon;
reading column704; Web Add/Undo/Redo below body; saved-note metadata disclosure
with children kept mounted, actual summary/progress retained; responsive
share panel top-right Web/bottom compact and compact invite form. Existing
callbacks, DTOs, access checks and writer retained. No new product capability.

Web debug build86s and APK61s succeed. Native install-r/device SHA256 EXACT
93612F2599C3F071897C9289C83CD5814FABECAB15153F6BBB1818428040FAF5.
Actual installed Chrome155 at1363x936: retained Unicode/emoji and heading,
Saved/All synced; utility expansion reveals labels/files; share Ready and controls
enabled, then Close. Actual Native API35/1080x2400/420dpi/font1/gesture: same
retained content, utility expand/collapse and Ready sharing panel. Current captures:
- output/playwright/p5-ref-final-web-note.png, web-share.png, web-details.png
  (all use full prefix p5-ref-final-).
- output/m09/p5-ref-final-native-note.png, native-share.png, native-details.png.
No final score or full M09 acceptance. Notion evidence is being published.

### Historical next steps — superseded by19 October UI directive

1. Finish remaining visual comparisons: search/settings/protection/selection
   toolbar, dark/locale/rotation/keyboard and small/large-scale layouts.
2. Resolve observed cold-start navigation finding: clicking Notes immediately
   after fresh load remained Loading notes; Home then opening a card worked.
   This has NOT been fixed or accepted. Size-popup/selection final UI matrix
   also remains open; an automation wait for28pt alone is not a product finding.
3. Once visual scope settles, affected regression and one final full matrix,
   separate11-criterion Web/Android scores >=95, Notion ticks and final handoff.

### Earlier verification - bounded predecessor

Runtime810 b775db4b...2a80832 before this reference pass: VM1926/5 configured
skips/0fail, Chrome1728/2 skips on204 mains/17 VM-only exclusions, actual HTTP
rich sync/share/revoke/protected read PASS, analyzer6 scopes clean212.7s.
Actual Chrome all13/Undo returned Saved/All synced; visible tooltip has one
accessible name. Native13 touch choices completed with Unicode retained.
Not every intermediate native header capture confirmed Saved; no full timing
acceptance from that batch. Old noisy timing/viewport experiments are superseded.

Earlier fixes retained: compact phone landscape and delayed caret scroll,48dp
targets, real button semantics, decorative icon scale, open Settings EN->VI,
host English fallback for absent vendor vi catalog, save feedback derived from
dirty state without controller callback context lookup. Two real-crypto tests
use5min budgets (assertions/production600k PBKDF2 unchanged).

### Historical runtime / tooling — rediscover before use

Static8776 serves p5-ref-final-web (session85822). Fixture8796/7/8 retained.
Chrome owner profile output/playwright/m09-chrome-owner. NoteFlow_API35 installed
current APK, original font1.0/density420/accel1/rotation0/gestural unchanged.
R: SUBST is the same D checkout, no new worktree. Preserve local data.
Node Playwright helpers must receive Page parameters; old closures may hold
closed tabs. Native utility label includes Collapsed/Expanded suffix; use fresh
UI hierarchy. Native_tap bare label failure was a harness mismatch, not app error.
Graph Transport closed on list/search/coverage; targeted source fallback used.
_agent_ops pack absent; continuity is in this file, MUST_REMEMBER and acceptance
receipt. Do not stage .playwright-cli/ or final_project.md.

Source/local UI is not live AWS/AppSync/RAG, real GGUF, actual iOS or Wasm proof.
Notion under final flutter: progress3f8f9c7a1aa0817a8f08e793aaaae83d,
main3e9f9c7a1aa080bb85a8d4973595bc21, editor3f5f9c7a1aa0817f9e0bdbe52bb091fe,
score3f7f9c7a1aa0816ab867faaefb40454b. Keep final checkboxes/scores open.
