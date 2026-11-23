# UI51 — Settings presentation from direct Notion reference

29 October2026. Scoped Settings implementation and runtime checks complete.
Whole M09 remains PARTIAL; Web>=95% and Android>=95% are UNVERIFIED.

## Scope and reference

Existing Theme, Language, AI consent/permission, Profile, Change password and
Log out only. The caller retains state, async session/request guards, permission
checks, account callbacks and persistence. No Notion-only High contrast, timezone,
calendar or other capability is added. Native compact retains its header and
SafeArea; account actions now have scoped minimum48dp touch targets.

Direct Notion Web Preferences measurements at1280x920: frame1152x820 at64,50,
sidebar240, content pane912. Title26/32/w600 at364,86; subtitle16/24; section16/24/
w500; label14/20 and helper13/18. At1920x1080 the frame caps1512, content column
caps800 and centers within the right pane. Padding60/36/76/40 reserves the end
scrollbar gutter. Sidebar selected row28px. Light/Dark colors were sampled from
the actual Preferences surface and scoped to this Web route. Existing heading
font is reused, without asset/dependency/config changes.

Files split by responsibility: common route/choice dispatch, Web frame and panes,
compact screen, and reusable account touch-target presentation. main.dart only
composes existing actions and localized group headings. Exact-source comparison
confirms the moved account callbacks; compact header is token-identical to the
published baseline. The48dp body wrapper is intentional, not token-identical.

## Defects found before publication

- Actual installed candidate66 exposed44dp account rows inherited from the global
  ListTile theme. A scoped reusable presenter sets min48/standard density. The
  regression fixture deliberately retains min44 and tests100% and200% text, since
  large text alone could inflate a broken target past48 and miss the defect.
- Independent Luna Max source review found narrow-first Web Settings stayed
  fullscreen when widened. Lead reproduced on actual Chrome67: title at352,56
  rather than364,106 and the visible frame filled1280x920 at0,20 instead of
  1152x820 at64,70 after the20px dev strip. Every Web launch now uses the
  responsive helper; native dispatch remains unchanged. The separate regression
  failed with no frame before the fix and passes after it; reviewer confirmed
  the source fix. The semantic dialog wrapper can still span the viewport;
  visual frame/title anchors, not that wrapper's bounds, verify the correction.

## Candidate evidence and limits

Candidate67:1082 runtime paths, fingerprint
`2348a4d4ffb49e3c86e853241d63051c41a92d76f89b20b439f14611bd6229d6`, drift[].
Web216.6s/APK131.9s built; APK
`e69a243a9c19277005804829d0553e09ed6a9fca1a44773b77f60db245f1c216`
was not installed. Actual Chrome21,474,907bytes SHA256
`15caa3416a27ab1a706cb5563ef3613385ce0b50909e50a7ed204eaa0a11a58b`
matched packaged source. Compact account/Close targets measured48px. Light/Dark,
1280/1920/390 and short-window independent scrolling were inspected; System theme
restored. Candidate67 is superseded because of the narrow-first resize defect.

This Chrome session recorded CORS errors: the local fixture rejects origin8782
(OPTIONS403), while its default allowlist accepts8776. This is a QA fixture
configuration limit; no cloud/permission/sync success or zero-console claim is
made. Settings retains its visible permission error state. Do not weaken CORS or
change backend behavior as part of a presentation-only checkpoint.

Earlier candidate66 source/runtime/ink evidence is retained in ignored output;
its installed APK hash matched, but its44dp rows prevent final acceptance.
Source snapshots64-67 are historical, not final UI51 evidence. No source build or
scoped test count establishes whole-platform visual similarity.

## Final evidence

- Final Chrome8/8 passes: six UI51 cases and two existing UI43 Settings cases.
  Strict analyzer on six changed source/test paths is clean. VM11/11 with one
  Web-only skip passed on67; the later68 source delta is Web dispatch only and
  adds one Web-only test. Do not mislabel the earlier VM run as a rerun on68.
- Source68:1082 paths, fingerprint
  `6dbd5caa726603359cf4004e94922d42f972774abb20dde02fa79bcb656b9bf4`,
  drift[]. Web129.8s/APK112.2s; existing Kotlin plugin migration warning remains.
  APK SHA256
  `c62f6d47ca3f5f595cbd704628dac371749747ae9dbe690428fc92d7534ffdfe`.
- Actual Chrome68 fetched21,473,527bytes matching packaged SHA256
  `4935ad38ee00fed4e4f2799a11908d17f7085e54fba3e3b652c8ccd24d7b4f38`.
  Initial390 Settings then1280 gives title364,106 and correct visible frame;
  1920 title672,106. Compact Close/account rows48px. Light/Dark1280/1920,
  Vietnamese700, short1280x500 independent-pane scrolling and Close inspected.
  Theme/language restored to System. Zero page exceptions, two console errors
  from the disclosed local fixture CORS limit at new QA origin8783; no API pass.
  ui51-web68-runtime.json and screenshots retained in ignored output.

- Installed/pulled Android68 hash matches the above APK,174,208,004bytes.
  Retained notes rendered after the startup recovery below. Actual420dpi/2.625
  scale: Profile1501-1627, Change password1627-1753, Log out1816-1942 =48dp;
  Close181-307 =48dp. At200% text, account rows152-153px and the footer ends2211,
  above the3-button navbar at2274. Landscape200% rows remain152-153px, right2227
  before navbar2274 and last bottom1017 within1080. Gesture Settings was reopened
  after configuration recreation; footer ends1942 before gesture area2316.
  Native Profile callback opened the existing unconfigured-service state, then
  Back returned; no account mutation or profile-service acceptance is claimed.
  Font1, auto rotation1/user0 and3-button navigation0 restored and re-read;
  original Dark/System preferences retained. AVD gracefully closed, data kept.
  ui51-native68-runtime.json and fresh XML/screenshots record these checks.

Initial Android launch was not clean: null-root/splash, AM launch timeout and a
System UI ANR occurred under host RAM pressure150-500MB. Wait alone did not
recover. SDK37.2 logs show requests1024/1536MB were raised to ACTUAL2560MB, so
claiming reduced VM RAM would be wrong. Same retained-data AVD restarted with
software GPU; app eventually rendered after force-stop/relaunch and settling.
Do not infer a startup root cause or fix. No data wipe, unrelated-process kill,
or system memory setting change. All accepted UI captures are settled fresh
hierarchies, not the failed null-root captures. iOS remains unverified.

Four paired Web reference/app images were attached to the existing Notion board,
preserving58 prior images as62; native scoped evidence is added separately.
Final root source/callback review complete; publication receipt is on progress.

## Review and ownership

One additional actual Luna Max performed a read-only final scoped review this
resume, finding the narrow-first defect. Twenty-one earlier actual worker
deliveries remain recorded separately. Lead owns all current edits, callback
preservation review, integration, tests/builds, Chrome/Android inspection and
Git/Notion publication. The same reviewer subsequently wrote an isolated ignored
UI52 header proposal; no UI52 production change is part of this checkpoint.
No overlapping writers;22 actual workers since the20-worker UI43 sequence.

Graph generation2026-10-27T21:08:32Z is stale: existing main/settings paths report
metadata_changed; four new source/test paths not_tracked. Parent queried the
Settings symbols, both call directions, and all six coverage paths; every current
scoped source was read directly. No complete graph-impact claim. _agent_ops and
its session tools are absent; existing MUST_REMEMBER/CURRENT_WORK records provide
continuity.

## Closure receipt

| Record | Resolution |
| --- | --- |
| MUST_REMEMBER.md | Final68 evidence, limits and next UI52; both95% gates open. |
| CURRENT_WORK.md | Build/runtime/source identity, resource recovery and next step. |
| VISUAL_REVIEW.md | Scoped Preferences/targets result; no platform percentage. |
| AGENT_IMPLEMENTATION_20261019.md | Actual extra review, finding/fix and22-worker count. |
| ui43/LIVE_REFERENCE.md | Direct Preferences geometry/colors and safe reference context. |
| _agent_ops/* | Not needed: folder/session tools absent; no fabricated records. |
