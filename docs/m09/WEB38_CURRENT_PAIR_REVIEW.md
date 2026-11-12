# Web38 current pair review

## Evidence and scope

- Actual Notion Web capture: [`notion38-web-note-dark.png`](../../output/m09/notion38-web-note-dark.png).
- NoteFlow Web37 capture: [`p6-parallel37-web-note-current-dark.png`](../../output/playwright/p6-parallel37-web-note-current-dark.png).
- Both are 1280×720, dark theme, sidebar closed. The app crop already excludes its 20px local-dev strip. This is a static PNG comparison only; the Notion capture has a transient `Ctrl+\` tooltip over part of its breadcrumb, which is not treated as a design target.
- Notion shows the 67B file row between paragraph and list. The approved app adaptation keeps attachments as note-level metadata below the document, so that row's vertical displacement is excluded from core layout findings. No inline file block is recommended.

## Measured differences

| Area | Notion38 | NoteFlow Web37 | Finding |
| --- | --- | --- | --- |
| Column and title | Content begins at x≈280; title ink x283–934/y166–205. | Content begins at x≈280; title x282–931/y166–203. | Title top aligns. App title is about 3px narrower and 2px shorter; weight looks close. No global type or column adjustment is justified. |
| Body and headings | Local body y234–249; H1 y301–329; H2 y374–397; H3 y436–455; paragraph x281–779/y478–493. | Local body y232–247; H1 y302–329; H2 y376–398; H3 y439–457; paragraph x280–777/y480–494. | The body line is about 2px higher in the app; H1 begins 1px lower, H2/H3 about 2–3px lower, and paragraph about 2px lower. Paragraph width differs by only ~3px. These are small baseline/rhythm differences; avoid global font scaling. |
| Bullets and task | Bullet text begins x≈312; task label x311–373/y619–629. | Bullet text begins x≈313; task label x310–376/y616–627. | The earlier ~5–6px-tight marker/label gap is resolved: bullet text now starts within 1px and task text within 1px of the reference. App bullet glyph runs are about 1–2px wider; task label about 4px wider. Treat the latter as a minor local typography difference, not a reason to change body sizing. Absolute list/task y is about 2–3px higher; exclude that difference because the approved inline attachment row is absent. The bullet row step remains 30px. |
| Quote | Bar x≈281/y652–675, #F0F0F0; text x306–378/y659–671. | Bar x≈281/y653–676, RGB(244,244,241); text x306–378/y655–669. | The previous horizontal inset gap is resolved. Bar color and height are a close match, with the app bar 1px lower. Quote text remains about 3–4px too high; a small downward alignment change is the clearest remaining content adjustment. |
| Header and controls | Hamburger at about x16/y16; no visible bottom rule on the bar. | Hamburger at about x15/y17; 44px top bar has a thin rule at y43. | Sidebar-toggle placement now matches closely. The app's header rule is a minor chrome difference. The reference's notification badge and extra page actions are product-specific states, not requests to add app features. Add block remains visible below the quote while the reference shows a bottom rule; compare matched hover states before changing that existing control. |

## Previous review items resolved

Compared with Web36, Web37 resolves the title-stack offset (title now starts at the same y), the list/task text inset (within about 1px), and the quote's horizontal inset. The light quote bar is visible and close to the reference color. The quote text's vertical position remains the clearest residual difference; heading/body baselines differ by only about 1–3px.

## Decision

This pair supports only small, local refinements: lower quote text by roughly 3–4px if desired, then recheck the minor task-label width and the header-rule/hover state. Attachment placement is an approved adaptation and is excluded from core geometry. No whole-platform percentage or M09 pass is assigned.
