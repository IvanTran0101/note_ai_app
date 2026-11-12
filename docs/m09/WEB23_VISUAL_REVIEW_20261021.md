# Web 23 visual review — 21 October 2026

## Evidence reviewed

Reviewed the seven current Chrome captures in `output/playwright/`:
`p6-parallel23-web-{rich,slash,selection,size,settings,share,password-form}-product.png`.
They show a 1480×668 dark-mode NoteFlow viewport, with the 20 px development
strip excluded from the captured page. The running source/build identity is
recorded in `CURRENT_WORK.md` as source835,
`0b75eff7ad1c211d08a9a95c3d966f85c906d58714242c4784219e16d9fd4ed0`.

The comparison anchors below come from the recorded direct Notion Web
inspection in `VISUAL_REVIEW.md` and `CURRENT_WORK.md`: sidebar270 px, header44,
reading column about720, title40–48/body16–24; direct text anchors title
x515/y166, body238, H1 302, H2 375, H3 438, paragraph479, list step30; slash
324×267 with33 px rows; selection192 px painted width with224 px outer region
(16 px transparent margin); Settings900 px with60/64 px content gutters and
150×28 selectors; Share458 px wide at y44.

The local `hinhanh/UI_web_ref` images were used only as supporting references.
They are historical captures and do not replace the direct Notion measurements.
This review is screenshot-only: it did not operate the browser, inspect live
DOM, test interactions, or verify other viewports/states.

## Component-level visual estimates

These are provisional ranges for the pictured component only, not an aggregate
Web score or M09 gate decision. Ranges reflect the limits of comparing the
current app screenshots to recorded Notion dimensions without a paired current
Notion screenshot for every state.

| Component | Estimate | Evidence and visible gap |
| --- | --- | --- |
| Shell and navigation | 88–93% (low confidence) | Sidebar width is270 px, matching the direct reference. The app's blue focus outline around Notes and its header action cluster look stronger/denser than the quiet row and breadcrumb treatment in the supporting Web reference. The available direct notes do not include a paired dark-mode pixel capture for these details. |
| Note title, body and visible blocks | 92–96% (medium confidence) | In the rich capture, title and reading-column alignment are close to the recorded x515/y166 anchor; H1–H3, paragraph and ~30 px list rhythm also appear close. The body line begins visibly above the y238 reference anchor, while the title is nearly aligned. This one viewport does not show the full document or every approved block. |
| Slash menu | 94–97% (medium confidence) | Captured menu is about324×267, matching the direct geometry; visible rows are about33 px. Only the first entries are visible in this screenshot, so the lower menu and full scroll extent are not reviewed here. |
| Selection toolbar | 93–96% (medium confidence) | The painted panel is192 px wide and starts about16 px after the selected text, matching the recorded Notion geometry. The screenshot shows the existing format controls and size affordance; this is not a paired capture of all Notion controls, and AI/comment actions are intentionally outside NoteFlow scope. |
| Font-size menu | — (no direct equivalent) | The capture shows the approved 12–32 presets, custom12–48 and reset actions. The available Notion evidence does not give a matched popup geometry for this app-specific size control, so no resemblance percentage is assigned. |
| Settings | 85–90% (low confidence) | The dialog is900 px wide with60/64 px content gutters, matching the recorded dimensions. The selectors appear roughly150×24 px versus the150×28 reference; the title/helper hierarchy also reads larger and the content is more vertically spread. A red “No network connection” message is visible beneath Ask-notes permission; this is the captured unavailable state, so it should not be scored as normal-settings styling. |
| Share panel | 96–99% (medium confidence) | The panel is about456 px wide at y44, within2 px of the recorded458 px reference and at the same top anchor. The invite field, role and Share action form a compact panel. No recipient state and NoteFlow's existing permission controls are app-specific state/content differences. |
| Password form | — (no direct equivalent) | The app-specific protection dialog is clearly laid out, but no paired direct Notion Web password-form reference is recorded. |

## Main remaining visual gap

Among the pictured states with a recorded direct counterpart, Settings has the
clearest visible refinement opportunity: the chooser height and text hierarchy
do not match the measured150×28 selector and smaller helper treatment as closely
as the note, slash, selection and Share geometry do. Recheck it in the normal
permission state after the current visual pass; preserve the honest disconnected
state without using it as the normal-state comparison. The blue Notes focus
outline and the body vertical offset are smaller shell/editor refinements.

No whole-Web percentage is assigned. These crops do not establish the full
screen-state matrix, light mode, narrow layouts, interactions, accessibility,
or safe-zone behavior, and they are not evidence that Web or Android has
reached95%. Both UI gates remain open pending the lead's complete paired review.
