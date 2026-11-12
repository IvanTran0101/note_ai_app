# UI46 — native header reference inset

27 October2026. Lead-only continuation after20 reviewed Luna Max UI43 deliveries
and UI45 publication b3ae6bd. Whole M09 remains PARTIAL; both platform>=95%
similarity gates remain UNVERIFIED.

## Change and direct reference

Actual Notion Android0.6.4222 Back target[42,144][139,241], Actions[939,144]
[1039,241] on1080x2400/420dpi/font1/dark. NoteFlow56 targets reached both screen
edges: Back[0,181][126,307], More[954,181][1080,307]. Header vertical positions
must subtract the52.5px LOCAL DEV strip before comparing.

NoteFlowPageHeader now adds10dp horizontal content inset for native phones,
inside its existing system SafeArea. Targets stay48dp; wrapping uses the width
remaining after the inset. Compact Web/desktop geometry and callbacks remain.
No service, data, permission, sorting, feature or dependency changes.

Actual57 Back[26,181][152,307], More[928,181][1054,307]: center89/991 vs ref90.5/989,
within1.5/2px horizontally. Center244-52.5=191.5 vs ref192.5,1px vertically.
These are header measurements, not a whole-platform percentage.

## Verification

- Focused native geometry plus existing action-accessibility suites6/6pass:
  ui46-header-tests.log. Portrait/landscape, asymmetric cutouts,48dp, narrow
  wrapping, Back/More callbacks and existing action ownership/trailing Web edge.
- Installed Chrome6/6pass, ui46-header-chrome-repaired.log. First stock Flutter
  test attempt did not execute tests: Windows testSelector contained an unescaped
  backslash-u sequence, causing SyntaxError in generated HTML. Stopped it, used
  the existing local tooling overlay that normalizes separators, then all6pass.
  SDK/repo config/CanvasKit/dependencies were not changed. VM target assertions
  were made portable for the unchanged compact40dp desktop Back control.
- Strict analyzer2 source/test files clean, ui46-analysis57.log.
- Final57 Web69.9s/APK36.6s;1076 runtime paths/source fingerprint
  677bd684581e65429b64666cc10bad63aa4298ebbb06ca017379bd74f163da09,
  source drift[]. Chrome received21,440,553bytes/main.dart.js, SHA256
  eeb431020dcd6bd96d1626795c471ec6dee65b56438158a2a2c36e963404378b,
  matching packaged57. InstalledAPK SHA256 matches
  f7d23f9edd8cb0c1fcfe5ed66b73e5ed4dfa9057ee5118c03024e772a8589a34.
- Actual57 portrait3-button header above; landscape2400x1080 Back[154,116]
  [280,242], More[2122,116][2248,242] clear the physical safe edges. Portrait
  gesture header retains the same bounds; shell rail ends2316 above system
  gesture area. Original3-button/rotation1,0/font1 restored. Actual captures
  ui46-native57-header-settled, -header-landscape and -gesture-header-settled
  include fresh XML. Expected Back/More labels were verified, not inferred from
  a successful capture command. Portrait image attached to Notion board.
- Chrome57 Dark editor, fully loaded Share/No recipients yet/Close, chooser2
  checkboxes/Cancel and Search query viewed with zero collected console errors.
  No invitation. Settings Light/Dark viewed on56; only header inset changed57.
  Actual Notion Web Preferences Light/Dark/Search inspected; both Web themes
  restored to their original Light. Unavailable ask-notes permission in the local
  fixture is retained honestly; this is not live AWS verification.

## Limits and next work

Post-install Android white splash/null-root recurred. Rotation refresh with a
settled intermediate frame restored visible UI; activity recreates on nav-mode
changes. No startup fix is claimed. This is a recorded runtime limit, not a
cold-start pass. Earlier transitional/null-root captures remain in ignored output.
The newer capture helper takes XML before PNG; a settled expected screen is
still required. No app data cleared; no unproven source workaround added.

Stable Web title ink x416/y187 minus20px dev strip matches ref x416/y167. Earlier
short-title transition was not evidence for changing the document column. Labels
remain below title as approved. Found the older complete synthetic fixture in
Search's second same-title result; noon duplicate is only paragraph/H1/H2. Legacy
attachment position and blank-line differences still prevent treating the two
documents as identical full-screen fixtures. No complete typing pass claimed.

Continue responsive Search/empty/loading/error/focus/dialog and native matrix.
At1280x720 Notion Search is600px wide/top64.8px; app top60px. Verify another
viewport before adjusting its responsive position. Recents ordering remains the
existing projection; actual last-opened tracking would need feature approval.
Actual iOS remains unverified. Do not turn these tests/anchors into95%.

## Closure receipt

| Record | Resolution |
| --- | --- |
| MUST_REMEMBER.md | Current57 evidence, complete fixture location, next matrix and limits. |
| CURRENT_WORK.md | Verified source/runtime, measurements, recovery and continuation. |
| VISUAL_REVIEW.md | UI46 component evidence; whole-platform gates stay open. |
| AGENT_IMPLEMENTATION_20261019.md | Lead scope and reviewed20-worker boundary. |
| ui43/LIVE_REFERENCE.md | Current native header, Web Settings/Search reference. |
| _agent_ops/* | Not needed: runtime pack/session tool absent, verified. |

Root reviewed the final runtime/test diff, safe-area arithmetic and exact
packaged/runtime identities. No additional subagent spawned for this follow-up.
