# UI49 — native Search presentation and landscape ownership

28–29 October2026, after UI48 publication2084f14. Whole M09 remains PARTIAL;
both Web/Android >=95% similarity gates remain UNVERIFIED.

## Direct reference and scope

Lead reopened actual Notion Android0.6.4222,1080x2400/420dpi/font1/Dark/3-button.
The same complete synthetic query qxzvbnmptkswj gives No pages found at
[388,613][693,666], supporting text679-729; field1381-1507 with IME. Landscape
2400x1080 gives No pages found548-601, the same65px upward header shift. With
landscape IME the no-page message is below the fold; parent scrolling is needed.
The existing NoteFlow labels replace the unsupported Ask AI/deleted-pages UI.

DashboardNativeSearchEmpty now uses a natural-height centered message and the
existing Clear action after60dp reference spacing,14px/20 line-height/weight500.
It owns no scroll/query state. Only native compact Search no-match uses it;
generic/Web/desktop empty states retain their path. Existing localized copy,
keys, query/filter/sort/access/error/retry/refresh/callbacks/data remain.

The compact dock uses a muted20dp filled-circle X on native phones. Web keeps
its X glyph; its clear control also retains48dp under compact density. Close,
sort, prefix/border/fill/SafeArea and controller behavior remain. Root checked
the narrower compact Web text area and callback; no visible overflow. No new
capability, dependency, config, lockfile or permission change.

## Lead review and checks

The additional Luna Max reused from UI48 supplied isolated empty/dock drafts.
Lead read every artifact, retained one production writer, adjusted native type/
font/density, Vietnamese200% case and Web icon expectations. Twenty UI43 workers
plus that one reused worker=21 actual across the task. No new late-resume spawn.

- Initial scoped VM10/10: final UI48 compact viewport3, native empty3 including
  Vietnamese200% short parent scroll, dock3, compact integrated query/no-match/
  Clear/query/close1. Chrome7 specific plus4 continuity=11 distinct, not14.
  Native component tests on Chrome validate layout; they are not emulator proof.
- Analyzer6 source/test paths clean, plus later Web-guard test recheck. Root then
  found a real landscape bug on installed61: duplicate inline/docked fields and
  close controls and a Clear control clipped to37px. Scaffold/Content use native-phone
  shortest-side classification; DashboardPage._buildBody used width alone.
- The new Android landscape/IME regression's first run failed compilation due
  to the test's restricted foundation import. Fixed import/analyzer, then actual
  red run failed on two fields: ui49-landscape-red61-corrected.log. Root aligned
  _buildBody to NoteFlowLayout.isCompact(context, availableWidth: constraints.maxWidth).
  Green regression1/1 passed, ui49-landscape-green62.log, including unchanged
  query, one field/dock, no inline close and reachable48dp Clear after scrolling.
  Native-only case is intentionally excluded from Chrome.
- Chrome page continuity2/2 passed after the helper repair. Final VM3/3 includes
  native landscape center.x422, one field, preserved query and reachable Clear,
  plus compact and desktop continuity. The initial final subset was2/3 because
  the new test leaked IME160 into the following desktop case. Proper test cleanup
  fixed this; the original desktop704 expectation remains. Final strict7 paths
  clean. Initial10 plus landscape1 and desktop1 are12 distinct VM cases across
  the recorded runs, not12 fresh final cases. Counting runs is not a percentage.

## Final62 runtime

1079 runtime paths, source fingerprint
`d6dd1ad16590572c87d51d687e442a49ca61ad50c60c5440923a13c7bd7bdaea`,
drift[]. Web93.6s and APK50.6s. Chrome fetched21,462,326-byte bundle with SHA256
`6553392b42629374dd6990762f7bdfe62c44dd5aab48b67edd306397bcdd0574`,
matching the packaged file. Installed/pulled APK matches
`18275d24b97f74ab8b930d89a0cbc639037bdf80d2402f1f674167dfcb293e56`.
Build warns about existing plugin Kotlin Gradle migration; no dependency upgrade.

Actual Chrome62 wide and initially390px: one field, body/dock Clear callbacks,
typing and Close checked, no captured console errors. Wide body Clear104.56x48;
compact dock48x48, compact legacy body40 remains UI50's explicit presentation gap.
Web restored1280x920/Light/Home. Receipt ui49-web62-runtime.json.

Actual Android62 stable landscape with IME: one field/dock, no inline duplicate.
Scrolled until body Clear[1065,120][1337,246] is fully visible,126px=48dp;
dock Clear[1854,384][1980,510], Close[2117,384][2243,510], keyboard starts520.
Tapped body Clear and real results returned with query empty. Native Search
now fills available width with balanced gutters, rather than a396dp frame.
One capture failed because ADB server disconnected between dump and fetch;
fresh complete retry accepted, not stale XML. Post-install null-root settled
after wake; this does not establish a startup fix. A green window outline
recurred on62; the earlier Home/resume recovery was temporary, cause unresolved.
After a settled portrait resume, the outline was absent in the final capture.
Portrait62 body Clear[404,729][676,855] is centered at540px and48dp high;
dock Clear/Close remain126px high above keyboard1518. At real200% text body
Clear[316,847][764,973] and dock controls remain fully visible. Restored font1,
rotation auto1/user0 and original3-button navigation0. Notion itself showed ANR
after rotation back to portrait; Wait did not recover it, so the reference app
was force-stopped/reopened without deleting data. The earlier valid portrait/
landscape ref remains evidence; a failed/null-root capture is not accepted.

## Runtime ledger and limits

Superseded61:1079 paths/2d720019...be6d23 drift[], Web91.4s/APK73.3s; exact
Chrome21,462,295bytes/d538aa05...1983ce and installedAPK0c885b54...7519bc match.
Do not publish/accept its broken landscape.

Portrait61 body Clear[389,729][661,855] and dock Clear/Close126px=48dp. Glyph ink
app(366,679)-(684,714) minus52.5px LOCAL DEV strip vs reference(392,622)-(690,663):
vertical anchor within~5px; horizontal center525 vs541 follows the existing
reading frame, not an exact full-screen match. Actual200% text kept content/
action visible above IME; filtered current-process logs showed no layout errors.
Body Clear was tapped, results returned, the full query was retyped successfully.

A green whole-window outline persisted after typing and on raw screencap. It
disappeared after Home/resume and did not recur after Clear/retype or200% text.
Magnification was inactive1x, no media projection/debug-layout flags. Cause is
unproven; no product/default-focus workaround was added. Android's optional
[fallback focus highlight API](https://developer.android.com/reference/android/view/View#getDefaultFocusHighlightEnabled())
was investigated as a hypothesis, not confirmed as this cause. Earlier green
captures remain in ignored output. This is not a claim that the cause is fixed.

Graph transport closed during later discovery. Previous Tier2 snippets/coverage
were supplemented by exact current source reads, including common layout71-213
and page497-522. No exhaustive graph completeness claim. A driver invoked with
--help ignored the argument and reran4 continuity cases, overwriting an ignored
old stdout file. The new run is preserved as ui49-ui48-continuity-chrome61.log;
historical stdout was not recreated. Prior published report/build/runtime
receipts remain. This changes no product source/result count.

Compact Web still has the legacy full-page Search/no-match presentation/body
Clear40px when opened narrow initially. That remains an explicit next reference
comparison, not a >=95% pass; no visible overflow was inferred from the oversized
merged textbox semantics rectangle. Actual iOS/full paired matrix and broad
functional acceptance remain open.

## Closure receipt

| Record | Resolution |
| --- | --- |
| MUST_REMEMBER.md | Final62 evidence and UI50 next; both95% gates stay open. |
| CURRENT_WORK.md | Actual failures/repairs, final62 evidence and UI50 next. |
| VISUAL_REVIEW.md | Scoped final62 verification and remaining Web gap. |
| AGENT_IMPLEMENTATION_20261019.md | Lead review of isolated draft/repair. |
| ui43/LIVE_REFERENCE.md | Native portrait/landscape and remaining Web gap. |
| _agent_ops/* | Not needed: runtime pack/session tool absent. |
