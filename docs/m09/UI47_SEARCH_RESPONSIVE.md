# UI47 — responsive Search popup

28 October 2026. Lead implements/reviews this follow-up; the twenty UI43 Luna
Max deliveries remain reviewed. One additional Luna Max prepared isolated UI48
drafts, not included in this runtime. Whole M09 remains PARTIAL and both
platform >=95% similarity gates remain UNVERIFIED.

## Direct reference and changes

Authenticated Notion Web, settled Light Search popup measurements:

| Product viewport | Left | Top | Width | Height |
| --- | --- | --- | --- | --- |
| 1280x720 | 340 | 64.8 | 600 | 639.2 |
| 1280x900 | 340 | 81 | 600 | 700 |
| 1480x1000 | 440 | 90 | 600 | 700 |
| 500x900 | 0 | 81 | 500 | 700 |
| 1280x540 | 340 | 48.6 | 600 | 475.4 |

The rule is top9vh, width capped at600, height capped at700, with16px bottom
clearance. A transitional post-resize frame retained the former height; only
settled frames/computed CSS were used. The reference viewport was reset to its
original1280x720, Light retained, and the Search popup closed after inspection.

DashboardSearchDialog now owns this view geometry, extracted from the large
DashboardPage. It measures the route's available area, excluding the host's
20px LOCAL DEV strip. Web retains its search composition after narrowing. Native
dialogs retain existing60px top/704px cap/24px side inset; normal native phones
retain their compact Search dock. Search query, filters, sorting, permissions,
data, callbacks and controller remain owned by the existing page.

The integrated resize check found a real duplicate compact Search dock behind
the open modal. Hiding that dock then exposed the modal's own stale
dockCompactSearch flag, which hid its field on native multi-window resize.
Both are corrected: an open modal owns its single search field; the ordinary
phone dock remains. The assertion checks the whole widget tree, not a narrowed
finder that would hide the duplicate.

## Verification ledger

- Five geometry cases plus one integrated open/query/resize/close case: VM6/6
  before the final dock guards, followed by the targeted integration1/1 after
  both guards. Six distinct cases, not seven.
- Initial Chrome geometry5/5 passed; the integration failed on duplicate
  fields. Final targeted Chrome rerun1/1 passed after both dock guards,
  ui47-integration-repair-chrome.log. Six distinct cases; earlier failures retained.
- Strict analyzer5 final source/test paths: no issues,
  ui47-analysis58-accepted.log.
- One VM failure was a test expectation error (32px vs existing24px native inset),
  repaired without changing the native production inset. A subsequent VM
  integration exposed the actual modal field suppression described above.
- Final58 Web95.9s/APK76.8s;1077 runtime paths/source fingerprint
  0f2808092ccd4a87ede8be359b7c50e16ee08e06757fc8b1be12daa95405136a,
  drift[]. Chrome received21,441,884bytes, SHA256
  218c790966ab871ff8ab92759a74f146f1c4dd952ec28473c5bcc338763fa7f2,
  matching the packaged JS. Pulled installedAPK SHA256 matches
  285ba9c23db8e074d22c88843b6725133280d12da432b6da1b218ff5b2423545.
- Actual installed Chrome retained one field/the same synthetic query across
  five host sizes1280x920,500x920,1280x740,1280x560,1480x1020 (each has20px dev
  strip). Field top109,109,92.8,76.6,118 respectively follows the popup's9vh
  anchor plus8px inner padding. Escape and Close both dismissed the route; the
  first immediate assertion ran before the close animation ended, then hidden
  state was explicitly awaited. Zero console errors. Receipt ui47-web58-runtime.json.
- Actual Android58 fresh Home/Search then IME: Close[922,1381][1049,1507],
  Sort[786,1381][912,1507], both above keyboard1518. First capture after install
  returned null-root; wake/settled capture recovered without rotation. This
  does not prove the earlier startup cause fixed or establish cold-start acceptance.
  Original3-button/rotation1,0/font1 retained. Transitional IME frame is not the
  settled bound. No data cleared.
- First reload during asynchronous static-server startup returned connection
  refused; readinessHTTP200 was verified before retry. This was a local tooling
  transition, not an app HTTP response or cloud check. Runtime uses local fixtures.

## Remaining visual work

Web filtered-empty content still appears at the top-left, unlike Notion's
centered no-result state. UI48 will integrate the reviewed bounded-scroll draft
after this milestone is published, preserving the existing Clear search action.
Notion's Deleted pages/AI actions are not app capabilities and are not added.
Actual iOS, complete paired state matrix and global similarity gates remain open.
No broad functional acceptance or whole-platform percentage is claimed.

## Closure receipt

| Record | Resolution |
| --- | --- |
| MUST_REMEMBER.md | Current ownership, Search rule and next UI48 boundary. |
| CURRENT_WORK.md | Actual source, failures/repairs and continuation ledger. |
| VISUAL_REVIEW.md | Actual58 geometry/state evidence; global gates remain open. |
| AGENT_IMPLEMENTATION_20261019.md | Lead follow-up and isolated worker boundary. |
| ui43/LIVE_REFERENCE.md | Settled live Search measurements and next empty gap. |
| _agent_ops/* | Not needed: runtime pack/session tool absent. |
