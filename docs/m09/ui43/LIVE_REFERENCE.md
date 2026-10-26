# UI43 — current direct reference and permitted adaptations

26 October 2026. Lead opened the real authenticated Notion Web synthetic note at `https://app.notion.com/p/3fdf9c7a1aa081e4abc9c8066d02a314`. This is current UI observation, not a similarity score. Android inspection is in progress and will be appended. Supporting checked-in refs are mapped in **docs/m09/REF_MAPPING.md** (not inside ui43).

## Web observed now

- 1280x720 viewport, paper-white document, quiet 44px top breadcrumb/actions strip. Sidebar starts collapsed; no large floating status card in the content.
- Content left approximately280, title top160, width about720. Large bold title around40px, normal body16px. Heading1/2/3 visibly30/24/20; dark neutral text, muted secondary metadata. The synthetic note contains an empty block between H1/H2; do not copy its accidental blank line as universal heading spacing.
- File is a plain inline row: small file glyph, filename16px, lighter smaller `67 B` on the same line. No decorative card. Lists/tasks/quote align to the document column; quote has a thin dark leading rule. Keep established UI42 gutter/toggle/removal contracts.
- Selecting paragraph text opens a narrow white elevated rounded popup to its upper-right. First row Normal Text with chevron; divider; second row color/B/I/U/clear; third row link/strike/code/equation/more. Comment/AI follow below in Notion, but are NOT authorized additions to NoteFlow. Preserve NoteFlow's approved size12-48 control within the existing format rows and all existing callbacks.

## Implementation release and adaptation boundary

Workers may now implement grounded changes in their OWN files based on these current document/popup tokens and the mapped platform refs. Further direct Home/Search/Settings/Share/Android observations will follow; do not invent measurements or claim a match for a screen not inspected.

- Labels have no standalone Notion feature equivalent in this flow. Keep existing label capabilities and below-title placement, neutral compact chips, legible selected state, native safe targets. Fix narrow/IME/text-scale layout using existing content/callbacks; no new label identity/permission feature.
- Profile/password/RAG/summary have no like-for-like Notion document workflow. Adapt the observed quiet white surface, muted supporting text, light separators, restrained blue primary action and clear hierarchy to existing fields/actions/states. Do not wait for a nonexistent matching Notion password/RAG page; explicitly report adaptation, not parity. Prefer an evidenced layout/accessibility fix over gratuitous numeric styling changes.
- Menus/dialogs: preserve existing actions/order/keys/semantics and root callback ownership. Respect available height after safe insets and IME, scroll on constrained screens, let text scale. Native touch targets48dp; preserve UI42 separate narrow toggle hit region.
- Search group helper owner only audits/tests existing grouping semantics and sends visual heading recommendations to lead; actual card rows belong to cards43 and composition headings to root. Do not change date grouping merely for style.
- Shared Flutter/Chrome/build/analyze/Git/Notion/ADB remain ROOT ONLY. Workers may write their own test/report and format only their files. Finish a concrete owned patch and report; no overall PASS or >=95% claim.

## Gates

Web >=95% and Android >=95% remain UNVERIFIED. Current observations release implementation; they are not acceptance. Lead must review all20 results and the combined runtime before publication.

## Current Android and additional Web observations

Real Notion native `Notion_API35_PlayStore`, 1080x2400, inspected after unlocking on26Oct. Current theme dark. Capture labels under ignored output/m09: ui43-notion-home-current, ui43-notion-native-note-settled, ui43-notion-native-search, ui43-notion-native-search-ready. Screenshots/XML may span a loading transition; the settled Home/note/Search screenshots were visually opened and inspected, not inferred from XML alone.

- Android Home: warm near-black surface, round avatar; pill destination controls below status area, centered icons. Recents is a horizontal carousel with neutral thumbnail top, document glyph crossing its lower boundary, two-line semibold title; Private list uses muted icons and clear titles, quiet section captions. Bottom search circle / Ask pill / compose circle remain above3-button navigation. Preserve NoteFlow's own destinations only.
- Android note: near-black document, back/share/actions header, large32ish title on2lines, body16ish, inline filename+smaller gray size without card. Bottom persistent action row remains above system navigation. Existing empty H2 placeholder is muted; don't mistake a placeholder for a filled heading's color.
- Android Search with IME: large Search heading, muted date-section labels, document glyph + two-line title/context rows. Search/sort share one rounded long field; separate circular close; both immediately above the keyboard. No large extra vertical dock gap. The keyboard's accessory strip is OS UI, not app content. Preserve existing NoteFlow query/sort/scope behavior; do not add Notion Chat or global page tree.
- Web expanded sidebar: width270, warm-white, thin quiet boundary, compact search field and small muted section labels; selected row neutral wash. Existing NoteFlow destinations remain.
- Web Share popup: top-right anchored white rounded elevated surface approximately456px wide. Compact header/rule, invite input and blue action on one row; recipient name14 over muted secondary12, permission on right13. Footer separated by subtle rule. Preserve existing Editor/Viewer control as an extra necessary NoteFlow element; no Publish/public-link/general-access/avatar feature additions.

These observations supplement the initial release and remain visual implementation evidence only. Direct native Share/block palette and selected-text toolbar inspection and the combined NoteFlow runtime checks are still pending.

- Native avatar menu was opened and visually inspected: dark elevated popup below avatar, about288dp wide, icon/label rows about48dp and a quiet divider after its first workspace-switch action. That action is not a NoteFlow feature and must not be added.
- Native Settings was opened and settled: centered semibold Settings header/back at left, quiet divider; bold section headings,16ish setting labels with14ish multiline muted descriptions, controls at right and separators between rows, content above3-button navigation. Source captures ui43-notion-native-avatar and ui43-notion-native-settings-ready.
- Web slash was opened in the synthetic note and visually inspected: about324wide/290high popup,33ish rows, muted12px Basic blocks caption,14px label and small glyph, neutral rounded selected fill, Media separator and Close menu/esc footer. Type to search is inline after the slash. Extra Suggested/Page/Link to page/database/media entries in Notion remain excluded from NoteFlow's approved13 Basic+File boundary.
