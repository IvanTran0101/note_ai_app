# M09 UI36 evidence coverage audit — 22 October 2026

## Decision

Neither platform has current evidence for a ≥95% similarity claim. The withdrawn
96.2 ratings and retired 57.2/60 point calculation remain invalid. Current
evidence covers a few components and interactions; it does not cover the required
screen/state matrix on either platform. Keep broad functional QA behind both
visual gates.

This is a documentation audit. It does not report a new live Notion inspection,
build, or UI capture.

## Evidence freshness

| Platform | Latest credible app evidence | What it establishes | Limit |
| --- | --- | --- | --- |
| Web | Packaged Web31 dark note capture paired with the direct Notion Web31 capture at 1280×720: [`p6-parallel31-web-rich-dark-top-stable.png`](../../output/playwright/p6-parallel31-web-rich-dark-top-stable.png) and [`notion31-web-file-reference.png`](../../output/m09/notion31-web-file-reference.png). | One static note state with matching synthetic title/body, headings, paragraph, list, task and quote. The text widths and list spacing are close in this pair. | The app capture predates the reported content-start, quote inset/accent and renderer-theme changes. It has the sidebar closed and does not show active selection, settings, search, or safe-zone variants. It is not a UI36 package. |
| Native Android | Packaged diagnostic APK33 is the latest documented package. Source34 was hot-restarted on it; it is not a packaged34 build. The UI36 report records the focused slow-drag capture [`app36-shell-slow-drag.png`](../../output/m09/app36-shell-slow-drag.png). | The current source36 slow 850 ms handle drag reaches the child pan, extends the selection, restores the formatting rail, and does not switch pages. This supersedes the older failed-drag observation for that focused interaction. | The capture is not a complete current Notion/app pair and the report does not identify a packaged UI36 build. Clipboard toolbar integration and the theme renderer fix are still awaiting package/current visual capture. |

The Web31 review specifically says its screenshot predates the current renderer
fix. The Web geometry calibration and current theme change therefore need fresh
captures. Native31/33 diagnostics are useful history for the selection issue, but
their failed drag result must not be applied to the verified UI36 interaction.

## Web checklist

| Required state | Evidence in hand | Remaining evidence needed |
| --- | --- | --- |
| Shell, navigation, home/list | Web35 pair is a note with sidebar closed. No current shell/list pair is recorded. | Pair current app and actual Notion shell, navigation and note list states, including the existing sidebar control state. |
| Search, results and filters | Direct Notion Web search measurements are recorded in `VISUAL_REVIEW.md`; no current same-query app pair is recorded. | Capture the same query/result and comparable filter state on both sides. Keep NoteFlow's existing label filter adaptation. |
| Open note: title, body, metadata and sync | Web31 gives a useful static content pair only. Its app capture predates the current geometry/theme changes and omits label/file metadata and sync states. | Recapture the matched note on the current package, including existing note-level labels/files and the visible sync state. Files remain note metadata; do not add inline file blocks. |
| Basic blocks, Add block and history | UI28 records real Web interactions and the current existing Add block/More behavior; there is no current matched menu pair. | Capture the existing Basic-block menu and history menu in matched focus/hover states. Keep the existing 13 Basic blocks and Undo/Redo scope. |
| Selection and formatting | No current Web app/reference pair for an active selected range is recorded. | Pair a selected-text state with the existing formatting/font-size controls and clipboard affordance after the current source is packaged. |
| Settings, share and password surfaces | Direct Web Preferences observations exist, but no current equivalent app pairs are recorded. | Pair each existing NoteFlow surface against the directly inspected applicable Notion state; record product-specific adaptations. |
| Light/dark, empty/loading/error | Web31/earlier31 exercise recorded a same-iframe theme switch and file viewer behavior. The current renderer fix is not visually verified in a package; no complete empty/loading/error pairs are recorded. | Capture both themes and applicable empty, loading and error surfaces on the current package. |
| Narrow layout and safe areas | The only current pair is 1280×720 with the sidebar closed. | Capture a narrow viewport and bottom/scroll/overlay states on the current app and actual Notion. Record viewport, zoom, focus and keyboard state. |

## Native Android checklist

| Required state | Evidence in hand | Remaining evidence needed |
| --- | --- | --- |
| Shell, navigation, home/list | UI37 now has a current actual-Notion/app home pair at 1080×2400, font scale 1, light theme and 3-button navigation. The older Android24 pair remains unmatched. | The pair covers only this portrait home/list state; selection, search, menus, other themes and alternate safe-zone states remain open. See the bounded UI37 update below. |
| Search, results and filters | Android25 shows the same result title, but the query text and surrounding filter/query hierarchy differ. This is old evidence. | Use identical synthetic query/result content and capture the current app, actual Notion, IME and filter presentation together. |
| Open note: title, body, metadata and sync | Android23 has a partial light/gesture title-body pair; it compares different lower content and app metadata. Older typography captures are not current-package evidence. | Recapture a current matched note including the same visible content, existing labels/files metadata and sync state. Keep labels minimal and neutral; keep files at note level. |
| Basic blocks and Add block | Older direct references cover Notion's Basic-block grid; no current matched app/reference menu pair is recorded. | Capture the full existing Basic-block menu and applicable note-level file presentation. Exclude Page/Link to page and other absent capabilities. |
| Selection, clipboard and formatting | Actual Notion `notion33-selection-current.png` shows the Cut/Copy OS bubble. Old app23 lacked visible handles/bubble; app31 showed handles but its drag failed. UI36 now verifies the slow-drag interaction in one focused capture. | After packaging the integrated source, capture the same selected text on both apps with handles, drag result, OS Cut/Copy bubble, formatting rail and IME. The new clipboard widget is not yet evidence of an integrated app surface. |
| Settings, share and password surfaces | Android23 has a stale Theme component pair. Native Settings evidence that showed a spinner is explicitly invalid as visual evidence; older Share references have no current app pair. | Use visible, directly inspected Notion states and current app captures for each existing surface. Do not infer Settings appearance from hidden accessibility text. |
| Light/dark, empty/loading/error | The old Theme pair is light-only and predates the renderer change. No current full-state pairs are recorded. | Capture both themes and applicable empty/loading/error states on the current package. |
| Responsive layout and safe zones | Old screenshots give partial portrait, IME, gesture and three-button observations only. They do not cover the full current screen matrix. | On both current Notion Android and NoteFlow, capture portrait/landscape, gesture/3-button navigation, keyboard open/closed, enlarged text, final scroll content, bottom actions, dialogs/sheets, and check for overlap or double insets. |

Keep iOS status-bar/notch/Dynamic Island and Home Indicator checks explicitly
unverified until an actual iOS environment is available; Android screenshots do
not establish them.

## Next captures, in priority order

1. **Establish one clean current artifact per platform.** Finish review/integration,
   remove temporary `M09_HANDLE` diagnostics before packaging, then record the
   exact Web and native package/source identity and capture settings. A hot
   restart or focused UI36 screenshot is not a packaged UI36 receipt.
2. **Refresh the core note pair on both platforms.** Use the same synthetic title,
   body and content density, viewport/theme, and current app builds. Include the
   current quote appearance and note-level label/file metadata. This closes the
   most stale pair and checks the latest Web geometry/theme work.
3. **Capture the active editor state on both platforms.** For Android, include
   the verified slow drag, final selected range, clipboard bubble and formatting
   rail above the IME. For Web, include selected text and the existing toolbar.
   Pair each with the corresponding directly inspected Notion state.
4. **Run a compact breadth pass for the still-missing states:** shell/list,
   search, Basic-block menu, existing settings/share/password surfaces, both
   themes, applicable empty/loading/error states, and responsive/safe-zone
   variants. Log a separate paired result for every state; do not carry a score
   across builds or state changes.

Only after every required state has current paired evidence and visible gaps are
documented should Web and native Android receive separate, reasoned similarity
estimates. No old score, isolated component match, test result, or interaction
can substitute for that evidence.

## Documents reviewed

- `MUST_REMEMBER.md`
- `docs/m09/VISUAL_REVIEW.md`
- `docs/m09/CURRENT_WORK.md` (the current-work file is under `docs/m09/`; no root-level `CURRENT_WORK.md` exists)
- `docs/m09/WEB35_CURRENT_PAIR_REVIEW.md`
- `docs/m09/ANDROID23_VISUAL_REVIEW_20261021.md`
- `docs/m09/PRIORITY_UI28.md`

## UI37 native Home pair — bounded measured update

**Pair and build.** Inspected [`app37-home.png`](../../output/m09/app37-home.png)
against [`notion37-home.png`](../../output/m09/notion37-home.png). Both are
1080×2400, font scale 1, light theme and Android 3-button navigation. The current
packaged37 native app is installed; its device SHA256 is
`66260050a0f22b697bc8aadf9d1f3f12e463ce84118586ba48a1fb0d41cd0ef8`. For visual
anchors, exclude status/nav system UI and the app's 52.5px `LOCAL DEV` strip.
Measurements below are approximate image-space bounds; title ink bounds use a
grayscale threshold below 120.

| Shared anchor | App37 | Actual Notion | Read |
| --- | --- | --- | --- |
| Avatar and destination row | Avatar is about 100×100px. Existing Home and Notes/document capsules are about 168×105px each; after removing the strip, their top is about y=139. | Avatar is about 100×100px. Home capsule is about 197×105px at y≈139; additional destinations are visible in Notion. | Avatar size and vertical placement align. NoteFlow's two existing destinations are its approved mapping; do not add Notion-only Chat, Meeting or Inbox destinations. The app Home capsule is about 29px narrower than Notion's Home capsule; the Notes/document capsule has no direct counterpart. |
| Recents heading and cards | Heading top is about y=386; after strip adjustment, y≈333.5. Cards start at y≈459 (adjusted y≈406.5) and are about 346px tall. | Heading top is about y=333. Cards start at y≈411 and are about 347px tall. | Heading aligns within about 1px after adjustment; card top/bottom align within about 5–7px. The second visible card begins at x≈442 in both captures and is about 346px wide. The first visible tile begins at different x positions (app≈53, Notion≈21), and its title differs; normalize carousel position/content before treating that first-tile width as a product gap. Card surfaces and corner radii look close. |
| Section heading and list rows | `All notes` begins around y=882; adjusted y≈829.5. The label-filter/Manage labels row follows; the first note row begins around y=1144 (adjusted y≈1091.5). | `Private` begins around y=828; first note row around y=932. | Section-heading baselines are close. NoteFlow's existing label filters add a visible row and move its first note lower by roughly 160px after strip adjustment. This is an existing label adaptation, not a missing Notion hierarchy feature. Notion's disclosure, More and Add affordances are not a request to add child pages or hierarchy. |
| Shared synthetic note-row title | Ink bounds about 611×46px at x≈168 in the app capture. | Same synthetic title ink bounds about 522×39px at x≈236. | App title ink is about 17% wider and 18% taller in this matched row, a concrete typography/density gap. Its left edge is about 68px earlier because Notion reserves a disclosure-chevron gutter; compare font size/weight independently of that indentation. |
| Bottom controls and safe zone | Three-control group bounds: left x≈42–168, center x≈200–880, right x≈912–1038; y≈2127–2253. | Bounds: left x≈42–168, center x≈200–881, right x≈913–1038; y≈2137–2260. | Horizontal geometry is effectively the same. The app group is about 10px higher; both remain above the shared visible 3-button navbar icons (top y≈2316), with about 63px app / 56px Notion clearance to the icon bounds. No overlap appears in this single portrait capture. App `Ask notes` and Notion `Ask AI` are different existing actions; retain the NoteFlow label and capability. |
| Light surfaces and icons | Sampled page background is RGB(249,248,247); card fill RGB(240,239,237). App document/pin icons read darker. | Sampled page background is RGB(249,247,246); card fill RGB(240,239,237). Some Notion row controls/icons are lighter outlines. | Background differs by at most 1 channel level in the sample; card fill matches. Icon/action sets differ, so preserve existing NoteFlow pin and note controls rather than adding Notion row actions. |

**Coverage update.** This is a current paired home/list reference and a useful
safe-zone observation for light portrait at font scale 1 with 3-button
navigation. It does not establish an Android whole-platform score or cover
gesture navigation, landscape, IME, enlarged text, scroll-to-end, other themes,
or dialogs/sheets. Note titles and remaining list contents are not identical;
the comparison is limited to shared layout anchors and the one shared synthetic
row title.

**Change impact.** This home update does not invalidate app36 Settings/Share
captures where their rendered code paths are unchanged in package37. Likewise,
a localized Web bullet-gap or native capsule-color change does not require a
blanket recapture of unrelated screens. Revalidate a saved capture when its
rendered code or asset dependencies change; keep this home pair scoped to Home.
