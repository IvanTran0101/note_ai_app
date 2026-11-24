# Web35 current pair review

## Evidence and scope

- Actual Notion Web reference: [`notion31-web-file-reference.png`](../../output/m09/notion31-web-file-reference.png).
- NoteFlow packaged Web31: [`p6-parallel31-web-rich-dark-top-stable.png`](../../output/playwright/p6-parallel31-web-rich-dark-top-stable.png).
- Both captures are 1280×720, dark theme, sidebar closed, with the same synthetic title, body, H1–H3, paragraph, bullets, task and quote. Review is limited to this static pair. Pixel bounds below are approximate visible-ink bounds in the supplied PNGs.
- The app capture predates the current renderer/theme fix. This pair cannot verify that fix in current Web output.

## Findings

| Area | Observed pair | Review |
| --- | --- | --- |
| Reading column and type | Both begin at x≈280. Title ink is about x283–934/y166–205 in Notion and x282–931/y160–197 in NoteFlow. The paragraph ink widths are effectively equal (about 499px vs 498px); H2/H3 widths are also within a few pixels. | Strong match. Do not widen the column or globally increase font size based on this pair. The app's text stack starts roughly 3–8px higher: title 6px, body 8px, H1 5px, H2/H3 3px, paragraph 5px. If adjusting, first try a small +4–6px content-start calibration, then recheck the lower blocks. |
| Heading/body weight | Title and heading weights look close. H1 is at most ~3px narrower in the app; H2/H3 are nearly the same width. | No weight or size change is justified by these images. |
| Lists and task | Bullet/task left edges match within ~2px. Both bullet rows have a 30px vertical step; app rows begin about 8px higher. | Keep current row density and indentation. The displacement follows the slightly high content stack; reassess after any top calibration. |
| Attachment | Notion renders `m09-ui-sample.txt` (67 B) inline between paragraph and bullets. The app image has no inline file row. | This is the approved standalone-note adaptation: attachments remain note-level metadata below the document. Do not add an inline file block. Overall paragraph-to-list spacing remains close in this pair. |
| Quote accent and inset | Notion's left bar is light gray (#F0F0F0 at the sampled pixel, y≈652–676). NoteFlow's is dark gray (#252525 at the sampled pixel, y≈648–666) against the shared #191919 canvas. App quote text starts about 6px farther left and about 10px higher. | Confirmed visual defect in this Web31 capture: the dark bar is barely distinguishable. Keep the quote accent theme-aware and increase the text inset by roughly 6px; verify bar height and quote baseline in a fresh current Web capture. The lead reports a source fix and focused VM pass, but this old screenshot does not validate them. |
| Shell/icons and state | NoteFlow has a 44px top bar with back, sync, sharing and more icons, plus a separate collapsed-sidebar chevron around x16/y66. Notion uses a breadcrumb/action bar with its menu at x14/y15. The app also shows its Add block affordance below the quote while the reference shows a bottom rule. | The separate sidebar-toggle row is the clearest existing-control placement gap; consider placing the existing toggle in the top bar while preserving the closed state. Other action sets are product-specific mappings; this image does not authorize adding Notion-only actions. Add block visibility is state-sensitive, so compare matched hover states before changing it. |

## Decision

This pair supports small geometry refinements only: content start by about 4–6px and quote inset by about 6px, plus the theme-aware quote bar already being addressed. Typography and column width are already close. The attachment difference is an approved adaptation. No Web similarity percentage or M09 pass is assigned from this single state.

## Web36 follow-up — packaged pair, 22 October 2026

- Compared the same Notion reference PNG with packaged [`p6-parallel36-web-note-dark.png`](../../output/playwright/p6-parallel36-web-note-dark.png). The lead reports reopening actual Notion Web on 22 October and seeing the same reference state; this review inspected the supplied PNGs only.
- Web36 includes the reported +6px content shift, top-row sidebar toggle, quote inset and light quote-bar changes. This comparison verifies their visible effect in the Web36 artifact.

| Area | Notion reference | Packaged Web36 | Remaining difference |
| --- | --- | --- | --- |
| Reading start/type | Title ink x283–934/y166–205; paragraph x281–779/y479–493. | Title x282–931/y166–203; paragraph x280–777/y480–494. | The title now starts at the same y; title width is ~2–3px narrower and paragraph is ~1px lower/~2px shorter horizontally. This is close; no global font or column change indicated. H1 top is ~1px lower, H2/H3 ~2–3px lower; paragraph ~1px lower. |
| List/task text inset | Bullet labels begin x≈312; task label x≈311. | Bullet labels begin x≈307; task label x≈305. | Marker/checkbox-to-text gap remains ~5–6px too tight. Increase the existing label inset about 5px while keeping marker positions and the 30px bullet-row step. The app's bullet/task content is about 2–3px higher vertically. |
| Quote | Bar at x≈281, y≈652–675, #F0F0F0; text x305–378/y659–671. | Bar at x≈281, y≈653–676, RGB(244,244,241); text x303–376/y655–669. | Bar contrast/color is now a close match and its 24px height is right; it sits 1px lower. Quote text is ~2px left and ~3–4px high. A small +2px inset and +3px vertical alignment adjustment would close the remaining gap. |
| Header/sidebar | Menu icon is in the top bar around x16/y16. | Existing chevron is now in the top bar around x17/y16; 44px app header retains a bottom rule at y43. | Toggle placement now aligns. Header action sets remain different product mappings; no new Notion actions are implied. The app rule is a minor visible chrome difference. |
| Attachment/footer state | Inline file row remains between paragraph and bullets; bottom rule at y690. | No inline attachment (approved note-level adaptation); existing Add block plus is visible near x293/y703. | Attachment adaptation remains approved; no file-block change. The Add block/footer difference is state-sensitive, so only compare after matching hover state. |

### Current pair decision

Web36 visually resolves the title-stack offset and the quote-bar contrast defect from Web31. Remaining actionable geometry is the list/task text inset (~5–6px) and quote text position (~2px right, ~3–4px down); heading/list vertical differences are otherwise within about 1–3px. This is a bounded single-screen review, not a whole-platform similarity score or M09 acceptance.
