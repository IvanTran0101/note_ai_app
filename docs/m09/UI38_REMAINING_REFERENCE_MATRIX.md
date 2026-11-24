# M09 UI38 remaining reference matrix — 22 October 2026

## Decision and freshness

The Web and Android native ≥95% gates remain **unverified**. This matrix lists
the reference pairs still needed; it assigns no score. The withdrawn 96.2
ratings and retired 57.2/60 calculation are not evidence.

Current checkpoint is packaged UI37. The native package/device hash matched,
and the UI37 Home pair is a direct 1080×2400, font-scale-1, light, 3-button
comparison. UI38 Home typography, wider destination pills, and avatar-menu
shell wiring are source changes only; they need a package and a focused Home
pair before being called current. Existing Settings/Share captures remain
usable while their render dependencies are unchanged: a Home or capsule edit
alone does not make those captures stale. Recheck only a surface whose code,
assets, or layout dependency changed.

Keep the evidence tiers distinct: “paired” means matching content and state on
both apps; a live inspection or an app-only screenshot is useful but does not
complete that pair. Use synthetic content, and do not publish raw Notion Share
screens that expose account identity.

## Required matching states

| State | Web — current evidence and remaining proof | Android native — current evidence and remaining proof |
| --- | --- | --- |
| **Shell, navigation, Home/list** | UI37 has a current dark note capture, but the current receipt does not identify a Web37 app/Notion shell-and-list pair. Capture both with the same sidebar state and synthetic recent-note content. | **Current pair:** [app37-home.png](../../output/m09/app37-home.png) / [notion37-home.png](../../output/m09/notion37-home.png), light, font 1, portrait, 3-button. Measured gaps: app destination pills are about 29 px narrower (168 vs 197 px); common note-row title ink is about 17% wider and 18% taller; app avatar opens a large drawer while Notion uses an anchored popup. App label/Manage controls shift the first note row down about 160 px after excluding the 52.5 px LOCAL DEV strip; retain this as the approved label adaptation. The carousel's first cards differ, so align content before judging its x-offset. UI38 must be packaged, then recapture this pair. |
| **Search, results, filters** | Direct Notion Search measurements are documented, but no current same-query app/reference result pair is recorded. Pair the same query, result, and visible filter state; keep the existing label filter as a neutral adaptation. | Android25's title-only comparison used different query/filter context and is historical. Pair the same query/result/filter with IME open and closed. |
| **Open note: title, body, metadata, sync** | The current app37 note shows corrected bullet/task and quote positions. The receipt does not name a same-content current app/Notion Web pair covering labels, note-level files, and sync state. Capture that state on both; do not add inline file blocks. | UI37 note and actual Notion note states were opened, but the current receipt does not establish a fully matched content/metadata/sync pair. Pair the same synthetic note and visible labels, note-level files, and sync state. |
| **Basic blocks, Add block, history** | UI28/31 interaction receipts are useful history; a current matched app/Notion menu pair is not recorded. Capture the existing 13 Basic blocks and existing history controls in the same menu state. | Prior direct Notion grid evidence exists, but no current matched app/reference menu pair is recorded. Capture the same existing 13 Basic blocks and Undo/Redo presentation. Keep files as note metadata; exclude Page/Link-to-page and other absent capabilities. |
| **Selection, formatting, clipboard** | UI36 has an app selection capture and the current receipt says actual Notion Web selection was reopened. The receipt does not identify a current side-by-side UI37 pair. Carry forward UI36 evidence only if the selection/toolbar dependency is unchanged; otherwise capture the same selected text, font-size/format controls, and clipboard state on both. | UI37 app selection/slow-drag shows range extension, the 48 dp capsule, and formatting rail above IME; Cut removed the selected text and Undo restored it. Actual Notion Android selection/clipboard was also inspected. No new visual mismatch is logged by the current bounded review; retain the pair if these dependencies stay unchanged, and record a side-by-side alignment for the final rubric. |
| **Settings, Share, password form** | App36 Settings/Share captures remain valid for UI37 while those code paths are unchanged. Actual Notion Web Preferences/Share were reopened. Do not recapture solely for unrelated Home/capsule changes. The current receipt does not name a matched password-form pair; check that exact form state, not only its submenu, if it is still required. | App37 Settings is captured; app36 Share remains valid while its path is unchanged. Actual Notion Android Settings and Share/Invite were reopened. Reuse these states unless their dependencies changed. Confirm a matched password-form state only if the existing capture set does not show the form itself. |
| **Light/dark; empty/loading/error** | The current Web37 note capture is dark. Complete matched light and dark states plus applicable empty/loading/error states; earlier theme interaction evidence does not cover the full current visual pair. | The UI37 Home pair is light. Complete matched dark and applicable empty/loading/error states. Keep each state paired at the same text scale and viewport. |
| **Responsive layout and safe zones** | Current note evidence is desktop-sized. Pair a narrow viewport and bottom/overlay/scroll states with actual Notion Web; record viewport, zoom, focus, and keyboard state. | Current Home pair covers portrait, font 1, and 3-button only. Pair portrait/landscape, gesture/3-button navigation, font 2, IME open/closed, and scrolled-to-end toolbar/sheet clearance against the actual Notion Android state. The UI37 selection capture proves one rail-above-IME state, not the full matrix. Actual iOS notch/Dynamic Island/Home Indicator evidence remains unavailable. |

## Prioritized capture order

1. **After UI38 is packaged:** recapture only Android Home/list. Use the same
   two destinations and same recent cards; measure the title ink and anchored
   avatar menu against the direct Notion state. Exclude system UI and the
   52.5 px LOCAL DEV strip consistently.
2. **Web paired baseline:** capture shell/list, Search with one identical
   synthetic query/result, and the same open note with labels, note-level file
   metadata, and sync visible. Include light/dark states where the view
   supports them.
3. **Native editor pair:** capture the same open note and Basic-block menu;
   retain the current UI37 selection/Cut/Undo state if its dependencies remain
   unchanged, then document exact pair alignment.
4. **Close the remaining state coverage:** verify the actual password form if
   not already represented, then capture the missing empty/loading/error and
   responsive/safe-zone states. Keep existing Settings/Share evidence unless
   those surfaces changed.

No blanket recapture is required for unchanged Settings/Share paths. No
whole-platform result should be reported until every required state above has
current paired evidence and the remaining visible gaps are resolved or
explicitly treated as approved adaptations.
