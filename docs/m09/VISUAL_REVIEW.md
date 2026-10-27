# M09 — UI similarity review (%)

## UI44 native palette/capsule refinement —27 October2026

Lead directly compared real Notion native selection/+ and current NoteFlow53,
then repaired dark per-choice tiles, over-tall palette and dark clipboard pill.
Actual55 palette top1518 vs ref1517px, Text ink anchor within3px horizontally/
2px vertically in the measured ROI; selected keyboard fill and48dp controls are
explicit adaptations. Final File row target now48dp instead of~44 from compact
density.15 scoped cases pass with2 repeated final target cases; strict5 clean,
Web61.5s/APK31s and exact Chrome/device hashes verified. Actual55 captures and
remaining limits: UI44_NATIVE_PALETTE.md. This component evidence establishes
no platform percentage. Both>=95% visual gates remain UNVERIFIED.

## ACTIVE UI43 — twenty-agent review (26–27 October 2026)

User resumed broader UI/UX with20 Luna Max. Seventeen runtime patches, two
verification-only UI scopes and one safe-area audit were reviewed by lead.
Current actual Notion Web/native observations and full handoff table live in
UI43_REVIEW.md and ui43/LIVE_REFERENCE.md. Lead also fixes48dp navigation targets,
IME handoff, Settings overflow, note-row clipping, desktop Share intrinsic-layout
assertion, format-label fallback-font overflow and label chooser whitespace.
Final53:1076 runtime paths/fingerprintcc0fc644...fc4a, drift[]; Web59.8s/APK31.1s.
Exact Chrome bundle and installedAPK hashes match. VM92/3skip plus chooser4pass
(3 overlap); Chrome24 unique pass/2skip after repaired cases; strict61-path
analysis clean. Actual53 chooser/Share operate with zero Chrome console errors;
settled native53 production rail stays above Gboard with shell nav hidden.
Actual51 native3-button/gesture/landscape and Settings200% inspected, separately
versioned; no real iOS run. See UI43_REVIEW.md for receipts and initial failures.
Both full-platform >=95% gates remain UNVERIFIED. No global M09 acceptance.

## UI42 — bounded gutter, toggle and File removal (24 October 2026)

PASS only for the3 requested items on final50. Public first-line geometry aligns
contextual + for H1-H4/callout/quote/task/nested text; layout-positioned Web hit
regions no longer cover the toggle arrow. Actual Notion toggle reference led
to filled triangle, empty hint,32dp Web/24dp native inset and natural title height.
Explicit file removal prunes its positioned blocks; offline pending cancellation
and reopen keep other content without unavailable tombstones. VM36/Chrome15,
static analysis/build identities and actual evidence: EDITOR_POLISH_UI42.md.
Notion checks3 UI42 items and adds8 images, retaining all31 prior ones. This is
not a platform similarity score; both >=95% gates remain UNVERIFIED. Publish and
stop at this boundary. Broader typing/whole-app safe-area backlog remains open.

## UI41 — bounded File / and + review (23 October 2026)

Actual Notion + query, Media/File and positioned Upload reference were used.
Build47 replaces the rejected footer UX with inline File insertion; labels stay
below title. Chrome/native interaction, cancel/reopen, picker/export and exact
build identities are recorded in FILE_BLOCK_UI41.md. This bounded slice passes,
with40 VM/19 Chrome/8 parser cases and clean analysis/builds. Notion24 old images
preserved,7 UI41 images added. Neither overall95% gate is established. Stop
after publishing this slice; await the user before another M09 change.

## Current status — NOT ACCEPTED (19 October 2026)

The user explicitly says the current UI is not similar enough. WITHDRAW the
previous Web96.2/100 and Android96.2/100 self-ratings, their threshold ticks and
the conclusion that functional acceptance may resume. The old57.2/60 visual
group calculation (95.33% of that group) also does not establish UI similarity.
Do not relabel any old points as percentages or invent a replacement number.

| Platform | Current similarity | Target | Current decision |
| --- | --- | --- | --- |
| Web | — Unverified; user rejected the prior conclusion | >=95% | Continue reference UI work |
| Android native | — Unverified; user rejected the prior conclusion | >=95% | Continue reference UI work |
| iOS safe area | Unverified; no actual iOS evidence | Top status/notch/Dynamic Island clearance | Planned, not checked off |

The documentation-only request is complete. Implementation has resumed with
six user-requested Luna Max agents and lead integration/review. Direct Notion
Web and native Android inspection has begun; CURRENT_WORK.md records current
captures and remaining gaps. Both similarity percentages remain unverified.

## Matched native typography — round9 (partial evidence only)

###22 October priority UI checkpoint (no platform percentage)

Actual Notion Web/native label/file/control inspection and NoteFlow28–31
interactions are recorded in PRIORITY_UI28.md. Neutral labels are an explicit
standalone-note adaptation; files remain note-level attachments. Flat file rows,
context menus, quiet Web Add block/More history and native Redo/Undo are now
implemented. Three main Notion priority UI ticks have bounded receipts.
Web31 first export through worker v4->v5 and offline export both downloaded the
same67B/hash with Flutter semantics enabled. Same iframe follows Light/Dark.
Native file/More targets48dp and200% text menu were checked. Board images17,
childpage1 were fetched after inserting current app images; old refs preserved.

Remaining observed UI gaps include native range-handle dragging/clipboard
affordance and renderer colors after theme change. The latter now has a source
fix plus focused theme-rebuild1/1 pass, but actual updated UI remains to check.
The handle diagnostic is not a passing gesture result. Continue the complete
matched screen/state matrix; these observations do not establish either95% gate.

###21 October follow-up (source16, still no whole-platform%)

Web16 packaged at833/d82c9e0...0226b, Web76.4s/APK34.6s. Native installed APK
and device hash f973bbc1...31e4a6 match. Current root heading height change had
no visible geometry effect: heading ink still approximately+3/+8/+15px versus
Notion after20px dev strip; source17 calibrates padding from those INK deltas.
Do not compare Notion editable y290/365/428.2 with app glyph ink coordinates.

Actual Notion Web list editable origins550.2/580.2/610.2 (30px step), font16/24,
padding2px. App16 bullet step~46px. PageBlock applies editor padding PER block;
source17 limits the reduction to Web list types via an optional layout callback.
No stored document/marks or native list spacing change from that callback.

Actual Notion selection screenshot/DOM21: visible background192px;224px outer
hit region includes16px transparent margins each side. Earlier224 painted-panel
assumption was wrong. Source17 uses192 visible width and retains approved size
control using28px compact actions/36px size, native48px targets unchanged.

Actual Notion Android landscape21 was operated (body focus/IME/+grid), captures
notion-native21-landscape{,-ime,-grid}.png. Its grid fills nearly all width;
app16 centers a640dp Material sheet. This is a confirmed remaining layout gap.
Gesture app16 grid scroll exposes Callout/Table/Divider, source16 font2 portrait
header remains readable and grid1column. Threebutton portrait captured; earlier
threebutton-landscape transition returned null-root/stale XML and is INVALID.
These partial observations do not certify all safezones or either95 gate.

Both apps show the synthetic title M09 UI comparison Android and body Local
first comparison. Actual Notion0.6.4222 at1080x2400/420dpi/font1/gesture:
notion-native-resumed-note.png. Current NoteFlow Dart9, hot-restarted against
installed debug7 (NOT a packaged9 APK): p6-parallel9-native-match-note-refined.png
(3button), p6-parallel9-native-gesture-note.png (gesture). Runtime9 title34/
1.18 and body17 were calibrated from actual ink, not inferred Notion CSS.

Dark ink bounds for identical text (raw physical pixels):

| Text | Actual Notion | NoteFlow9, 3button | Comparison after52.5px dev strip |
| --- | --- | --- | --- |
| Title first line | x74..847/y283..364 | x74..847/y337..418 | Same ink advance; top+1.5px |
| Title second line | x69..377/y387..454 | x69..377/y439..506 | Same ink advance; top-0.5px |
| Body | x72..508/y553..585 | x72..508/y610..642 | Same ink advance; top+4.5px |

These bounds cover only the shared title/body in this one state. They are NOT
a whole-screen/platform percentage. Extra NoteFlow metadata/sync controls and
excluded Notion AI/child-page features must be disclosed in any final rubric.
Source8 IME reparenting/Heading2 bug was fixed and H2/Undo operated visibly.
Source9 actual3button+IME/grid targets sit above the system area; captures and
XML p6-parallel9-native-threebutton-{ime,grid}. Gesture restored afterward.
Navbar-mode change visibly restores the installed7 layout; hot restart9 before
each further current-source comparison. A final packaged current APK remains
required. Both >=95 gates remain UNVERIFIED; no broad functional acceptance.

## Earlier direct native editor observations — rounds5/6

Notion Android0.6.4222/API35/1080x2400/420dpi/light actually rendered and edited
the new synthetic QA page M09 UI comparison Android (body Local first comparison).
Current host-GPU AVD17116/5556 preserves app data. Actual reference captures:
output/m09/notion-qa-{title,body,selection,blocks,blocks-lower}.png.

- Selection: Android Cut/Copy system menu above text; a flat full-width formatting
  rail directly above IME, neutral color/B/I/U/strike and horizontally scrolled
  remaining actions. AI/comment/reaction capabilities in Notion are excluded.
- Basic blocks via+: light249/248/247 panel, two-column neutral icon/text cards,
  approximately48dp targets/8dp gaps. Lower part confirms Callout/Quote/Table/
  Divider; Page/Link to page/Media remain excluded. Typing slash with ADB alone
  did not visibly open the Notion menu; do not describe that as a verified path.
- Native5 actual header now Back with Sync/Share/More; More contains existing
  protection/Ask notes/Summarize/Delete. Settings4 fullscreen is visible.
- Native5 selection still inset/rounded; caret controls not visible above IME.
  Candidate6 addresses these and the Basic block grid; inspect current artifact
  before claiming that the new presentation matches. Guarded touch sheet must
  retain its slash snapshot while the menu route owns focus.

Web4 actual Search600/top60 excluding20px dev marker, flat field and compact
rows; Settings900/content gutter60/64 and thin outlined selectors. Source6 is
building serially after scoped static checks. No new similarity % assigned;
neither platform's >=95% gate has been established and no broad QA resumed.

## Required direct references

### Direct observations — 19 October, current iteration

Actual Notion Web was operated in the logged-in in-app browser (1480x668;
some menu captures1280x720, dark). DOM measurements and visible captures:
sidebar270/header44; title column720/title40-48/body16-24; Search popup1008
wide/top60/rows~38; selection panel224 wide/three compact rows; slash324x289;
Share458 wide/top44; Preferences title28, helpers12/right dropdown150x28.
The Preferences dropdown has a thin outline. Live Search with its preview pane
did not show right-side dates; older supporting refs must not override that
observation. Notion-only AI, Publish, child pages and its settings sidebar are
excluded capabilities, not missing NoteFlow features.

Follow-up: toggling Notion's existing "Hide highlight pane" shrinks Search to
600px wide (x440/top60 at1480x668). The initial1008px included its preview pane.
Since NoteFlow has no preview pane, its matching normal Search target is600px,
with viewport-safe bottom clearance. Do not add preview merely to justify1008.

Actual native Notion0.6.4176 was operated on emulator-5556/API35,
1080x2400/420dpi/light/font1/gesture. Valid visible reference captures:

| State | Local reference capture | Observed presentation |
| --- | --- | --- |
| Home | output/m09/notion-native-reference-oct19.png | Compact navigation,132dp recent cards, plain private-note rows |
| Search/IME | output/m09/notion-native-search-oct19.png | Normal18dp titles,13dp subtitles,~64dp rows, hairlines, bottom input above IME |
| Note | output/m09/notion-native-detail-oct19.png | Title32/body16,~24dp gutter, top Back/Share/More; page icon excluded |
| Share | output/m09/notion-native-share-oct19.png | Full-width sheet starting~64dp, radius12, centered20dp header, invite36dp |

Settings captures show a loading spinner, even after official update to
0.6.4222. Loaded accessibility text behind that spinner is NOT visual evidence.
Native Settings/selection/slash still need direct visible reference evidence.
These local captures can include reference account details and remain ignored;
do not publish raw account screenshots. Actual NoteFlow candidates must be
captured after the current source814 freeze/build, not inherited from final7.

Preview1 Web (debug159.4s) exposed a reproduced UI defect: selection overlay
remained above Settings and intercepted its dropdown. Source fix now closes
ephemeral editor UI on route loss/outside tap without clearing editor selection.
Current paired similarity percentages remain unverified until rebuilt and
inspected. This is an observation log, not a threshold decision.

1. Open and operate actual Notion Web in the browser.
2. Open and operate the actual Notion Android application on Android. A narrow
   browser window or a filename in hinhanh is not proof of native inspection.
3. Inspect the corresponding screen/state before changing NoteFlow UI. Record
   what was actually seen and the inspection time; do not infer appearance from
   source, filenames or old screenshots. If login/app access is unavailable,
   record that gap, keep the gate open and continue independent UI work on the
   platform available. Missing access is not permission to award a percentage.
4. Keep hinhanh/UI_web_ref and hinhanh/UI_android_ref as supporting visual
   references. REF_MAPPING.md lists previously inspected images and exclusions;
   append direct Notion reference captures/details to the relevant screen map.

Only NoteFlow's existing functionality is in scope. Keep independent notes,
13 Basic blocks without Page/Link to page, the implemented selection toolbar/
font-size controls and existing settings/security/sharing behaviors. A feature
visible in Notion does not authorize adding it. Record a concrete proposal on
Notion as "Chờ người dùng duyệt" and wait for explicit approval before adding
any new capability. Keep local-first, access guards and existing user data.

## Paired comparison record

For each applicable screen/state, record:

- Actual Notion Web or native Android screen, inspection time and reference
  capture; add the relevant local reference filename where useful.
- NoteFlow exact build/source revision and actual capture of equivalent state.
- Viewport/logical size/DPR, device/API, orientation, theme, locale, text scale,
  status/navbar safe insets, keyboard visibility and selection state.
- Concrete differences: shell/navigation/layout; font family, hierarchy,
  weight/line height; spacing/alignment/density; surfaces/colors/borders;
  icon family/size/alignment; toolbar/dialog/state presentation and safe zones.
- Adaptations needed for NoteFlow-specific functions with no Notion equivalent.
  Compare applicable styling without inventing a new Notion-like workflow.
- Before/after captures and a reasoned visual similarity estimate (%) only
  when evidence exists. Record uncertainty and remaining visible mismatches.

Use synthetic NoteFlow text and equivalent content density; never copy private
reference accounts/content into demo data. Do not use raw pixel equality on
different content as a similarity claim. Tests, reachable buttons or a correct
data contract do not establish visual resemblance. The old0–5/weighted100-point
rubric is retired. Missing evidence stays —, not0%,95% or an inherited score.

## Screen/state coverage to complete

| Screen/state | Web direct pair / similarity% | Android direct pair / similarity% | Remaining gap |
| --- | --- | --- | --- |
| Shell, navigation, Notes/list | Pending / — | Pending / — | Inspect Notion directly |
| Search/results/filter presentation | Pending / — | Pending / — | Inspect Notion directly |
| Open note title/body/metadata/sync | Pending / — | Pending / — | Inspect Notion directly |
| Basic blocks/slash menu | Pending / — | Pending / — | Keep the existing13-block scope |
| Selection toolbar/format/font size | Pending / — | Pending / — | Compare selected/keyboard states |
| Settings/share/password surfaces | Pending / — | Pending / — | Record adaptations for existing features |
| Light/dark; empty/loading/error | Pending / — | Pending / — | Compare applicable state styling |
| Narrow/landscape/text scale/safe zone | Pending / — | Pending / — | Android gesture AND3-button navbar/IME |

## Safe zone — required during UI refinement

- Android: bottom system navbar in both gesture and3-button modes; final scroll
  content, bottom navigation, editor toolbar, dialogs/sheets and action buttons
  remain visible/touchable above the navbar and keyboard. Inspect portrait/
  landscape, keyboard open/closed and text scaling; avoid double safe padding.
- iOS: header, toolbar, content and top controls avoid the status bar, notch and
  Dynamic Island. Retain bottom Home Indicator clearance. Keep iOS checks open
  until a supported actual environment provides evidence; Android proof cannot
  certify the iOS top safe area.

## Hard gate before functional acceptance

Continue direct comparison and UI refinement until BOTH Web>=95% AND
Android>=95% similarity have current paired evidence. Do not average platforms
or omit a required screen/state with visible differences to reach the target.
Do not self-accept halfway, carry old ratings forward or interpret previous
test passes as UI similarity. The user has rejected the current resemblance.

Only AFTER both UI gates may work return to queued functional defects, broad
Chrome/Android regression, protection/sharing/offline checks, fix/retest and
final acceptance. Functional correctness remains required at that later stage;
the visual threshold alone is not completion of M09 or live AWS acceptance.

## Historical technical evidence — retained, no similarity claim

- final7 runtime812:3cd1a6552278eba1599f9bbe1088a9a3c43154663f7f6f4bea064a4ba1b81214.
  Previous VM1932 pass/5 configured skips, Chrome1735 pass/2 skips and8 analyzer
  scopes clean are technical results, not direct Notion similarity evidence.
  Builds: output/m09/p6-final7-web and p6-final7-owner.apk; APK/device SHA256
  A64572C10D80AAF202C646BAC5EF12581DA06B3763B47B003318C4B9C841EB3A matched.
- UI6 runtime812:1bd1dc31503af418e9bc6000095fb699f10ce924ed08a805adc99f04b7a7d255.
  Actual Unicode/multiline popup, font-size/link/math/Undo observations remain
  in p6-ui6-real-toolbar.json and p6-ui6-* captures. Its ratings are withdrawn.
- visual5 runtime812:88077fe6a162daf96ea8ba0bdae760dcb174341d56ceeaa3394b7bb0b2cb76f3.
  Prior visual4/5 note/search/settings/toolbar/light-dark/scale/rotation captures
  remain labeled with their original source. They do not satisfy the new
  direct-reference comparison or prove current safe-zone acceptance.
- Existing images on Notion are historical candidates, not images certified
  >=95%. Source/build/test details and queued M06 navigation observation are
  retained in CURRENT_WORK.md; do not start that functional queue before UI.

Notion comparison board:
https://app.notion.com/p/3f7f9c7a1aa0816ab867faaefb40454b
