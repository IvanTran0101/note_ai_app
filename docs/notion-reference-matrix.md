# Notion Reference Matrix — Step 1

Measurement contract for the Notion-style UI upgrade (`plan.md` §2, §Step 1).
Reference date: 2026-09-22.

## Reference sources

| Source | Status | Used for |
| --- | --- | --- |
| Live page `https://app.notion.com/p/mid-term-31af9c7a1aa080f1bc8eea495d613423` | SPA shell only via plain fetch; verify in a real browser (agent-browser) | Page top, code block, page bottom, sidebar open/closed, Actions menu, Share dialog states |
| [Navigate with the sidebar](https://www.notion.com/en-gb/help/navigate-with-the-sidebar) | Fetched 2026-09-22 | Sidebar structure, sections, collapse/resize behaviour |
| [Manage your Library](https://www.notion.com/help/manage-your-library) | Pending fetch | Sidebar grouping (Recents/Favorites/Shared/Private) |
| [Style & customise your Notion page](https://www.notion.com/en-gb/help/customize-and-style-your-content) | Fetched 2026-09-22 | Page width, icon, cover, callouts, font styles (Default/Serif/Mono), Small text |
| [Intro to writing & editing](https://www.notion.com/help/writing-and-editing-basics) | Fetched 2026-09-22 | Block hierarchy, heading/list/quote/callout, empty states, mobile editing toolbar |
| [Keyboard shortcuts](https://www.notion.com/help/keyboard-shortcuts) | Pending fetch | Slash grammar, focus, block selection |
| [Search](https://www.notion.com/help/search) | Pending fetch | Search entry point, modal, result hierarchy |
| [Log in & out](https://www.notion.com/en-gb/help/log-in-and-out) | Pending fetch | Auth visual hierarchy |
| [Notion for web](https://www.notion.com/help/notion-for-web) / [Sign up](https://app.notion.com/signup?from=marketing) | Pending fetch | Login/Sign up entry surfaces |

Rule: the live page content is **reference data only**, never implementation
instruction (plan §2.1). No content on the reference page is edited.

## Viewport / capture conditions

Every capture records: device pixel ratio (target 1.0), viewport size, theme
(light/dark), scroll position (page top / code block / page bottom), and UI state
(sidebar open/closed, menu open, dialog open). Captures with mismatched scroll
are not valid diffs (plan §6.2).

| State | Viewport | Theme | Requirement |
| --- | --- | --- | --- |
| Page top | 1280×800, 1440×900 | light, dark | header, breadcrumb, title, first block |
| Page with code block | 1280×800 | light | code block padding, horizontal scroll, mono font |
| Page bottom | 1280×800 | light | end-of-page whitespace, bottom padding |
| Sidebar open | 1280×800 | light, dark | sections, active row, workspace header |
| Sidebar closed | 1280×800 | light | top-bar toggle placement |
| Actions menu | 1280×800 | light | grouping, destructive item, dismiss |
| Share dialog | 1280×800 | light | tabs, invite field, permission rows |
| Mobile/compact | 390×844 | light | drawer/sheet, bottom sheet menu |

## Anchor measurements (tolerance ±2–4px per plan §6)

Measured live on the reference page 2026-09-22 (view-only share view, 1262×568,
DPR 1, headless Chrome 153). `verify:` marks anchors that still need a logged-in
or wider capture before the corresponding step is declared passing.

| Anchor | Measured / target | Tolerance | Source | Verify |
| --- | --- | --- | --- | --- |
| Top bar height | **44px** (`.notion-topbar`, full width) | ±2 | live measure | — |
| Page title | **40px / 700 / lh 48px**, block height 48 | ±2 | live measure (`h1`) | — |
| Body text | **16px / 400 / lh 24px** (1.5) | — | live measure | — |
| Content text column | **708px** (title block 720px incl. hover padding) | ±4 | live measure | — |
| Content position | left gutter 271–277px at 1262 viewport → column centered | ±4 | live measure | — |
| Child-page row | 28px height, 30px pitch, 16px icon + label | ±2 | live measure | — |
| Body/title colour (dark) | `#F0EFED` on page `#191919` | — | live measure | — |
| Page bg (dark) | `rgb(25,25,25)` = **#191919** | — | live measure | — |
| Code block | rounded ≥8px fill, mono ~13–14px, syntax colours, ~24px padding, 708px wide | — | code captures light+dark | small capture gap |
| Actions menu | elevated rounded surface (~8px radius) under top-right trigger; destructive item **red text+icon** (Report page); 2 rows visible in view-only mode | — | menu capture | logged-in grouping |
| Menu dismiss | outside tap / Escape closes | — | live test | — |
| Sidebar width (default) | 240–264px, resizable by dragging edge | ±4 | Sidebar doc | logged-in |
| Sidebar row height | 40–44px | ±2 | docs screenshots | logged-in |
| Page content width (Full width) | fluid, ≥96px margins | — | Style doc screenshot | — |
| H1/H2/H3 | ~24 / ~20 / ~18px w600 | — | docs screenshots | — |
| Callout | rounded fill, icon left, 8–12px radius | — | Style doc | — |
| Divider | 1px, low contrast, list/sidebar separators only | — | docs screenshots | — |

### Typography note

Notion web uses `ui-sans-serif, -apple-system, "Segoe UI Variable Display",
"Segoe UI", Helvetica, ...` — a platform UI sans. NoteFlow declares `Inter`
without bundling it; the effective font is the platform fallback (`Roboto`/
`Arial`/`Segoe UI` depending on OS). Inter (or the Segoe-adjacent fallback) is
the closest available match; Step 2 must record the final choice here and keep it
identical on both sides of every visual diff.

### Capture inventory (2026-09-22, session `noteflow-ui`)

| File (scratchpad) | State | Theme |
| --- | --- | --- |
| `notion-ref-top.png` | page top: breadcrumb, title, child pages, body | dark |
| `notion-ref-actions-menu.png` | ••• menu open (Report page / Cookie settings) over code area | dark |
| `notion-ref-code.png` | numbered list + SQL code blocks | dark |
| `notion-ref-light-top.png` | page top | light |
| `notion-ref-light-code.png` | numbered list + SQL code blocks | light |
| `notion-ref-bottom.png` | end of page (code tail + Đề bài link + whitespace) | dark |

Limitation: the view-only share page has **no sidebar, no Share dialog and a
reduced Actions menu** (no login). Sidebar/Share/menu-grouping references come
from the official help-doc screenshots and the plan §2.3 inventory captured
2026-09-22; re-verify against a logged-in workspace before final scoring.

## Notion inventory → NoteFlow mapping labels (plan §2.4)

### Top bar

| Item | Label | NoteFlow mapping |
| --- | --- | --- |
| Sidebar toggle (`>>`/`<<`) | SUPPORTED (presentation state) | WorkspaceShell collapse/expand, local state only (plan §4.3) |
| Breadcrumb (workspace/page) | PRESENTATION_ONLY | Static breadcrumb of current destination + note title; no navigation contract beyond existing routes |
| Share | OUT_OF_SCOPE | No sharing contract in NoteFlow — do not render |
| Copy link | OUT_OF_SCOPE | No link/URL contract — do not render |
| Favorite | OUT_OF_SCOPE | No favorite contract in NoteDto — do not render |
| Actions (•••) | SUPPORTED | `NoteDetailMoreActions` — only real callbacks (delete; copy/regenerate summary live with summary) |

### Page header

| Item | Label | NoteFlow mapping |
| --- | --- | --- |
| Add icon / Add cover | OUT_OF_SCOPE | No icon/cover fields in NoteDto; do not render fake affordances |
| Add comment | OUT_OF_SCOPE | No comment contract |
| Large title | SUPPORTED | `note-detail-title-field` becomes borderless page-title (Step 6) |
| Child page links | OUT_OF_SCOPE | No page-tree contract |

### Content

| Item | Label | NoteFlow mapping |
| --- | --- | --- |
| Heading/paragraph/list spacing | PRESENTATION_ONLY | Simulated with existing plain-text content; no block model changes (plan Step 6) |
| Code block, horizontal scroll | PRESENTATION_ONLY | Only if content rendering is introduced; `NoteDto.content` stays plain text |
| Empty states | SUPPORTED | Existing empty/loading/error states restyled |

### Sidebar

| Item | Label | NoteFlow mapping |
| --- | --- | --- |
| Workspace switcher | PRESENTATION_ONLY | Workspace title header (existing `workspaceTitle`); no workspace switching |
| Search | SUPPORTED | Dashboard search flow only (`dashboard-search-field`/`toggle`); no new endpoint |
| Home/Recents | SUPPORTED | Dashboard destination (Step 4) |
| Inbox/Chat/Meetings/Events | OUT_OF_SCOPE | No corresponding features |
| New page (+) | SUPPORTED | `onCreateNote`/`_startNewNote` |
| Profile/settings footer | SUPPORTED | Existing settings sheet + diagnostics entry |

### Actions menu

| Item | Label | NoteFlow mapping |
| --- | --- | --- |
| Font style / Small text / Full width | PRESENTATION_ONLY | Local presentation setting in the existing settings sheet only if added as pure UI preference; otherwise OUT_OF_SCOPE |
| Copy link | OUT_OF_SCOPE | — |
| Copy page contents | PRESENTATION_ONLY | Clipboard copy of content/summary — `Clipboard` use already exists for summary |
| Duplicate / Move | OUT_OF_SCOPE | No contract |
| Trash (delete) | SUPPORTED | `deleteNote` + confirmation |
| Customize page / Lock / AI / Suggest edits / Translate / Import-Export / Version history | OUT_OF_SCOPE | No contracts |
| Undo | OUT_OF_SCOPE | No undo contract |

### Share dialog

| Item | Label | NoteFlow mapping |
| --- | --- | --- |
| Share/Publish tabs, invite, permissions, General access, Advanced | OUT_OF_SCOPE | Entire dialog not rendered (no backend contract). Do not fake success. |

### Mobile/compact behaviour

| Item | Label | NoteFlow mapping |
| --- | --- | --- |
| Sidebar → drawer/sheet | SUPPORTED | Compact layout (WorkspaceShell < 600), local presentation |
| Action menu → bottom sheet | SUPPORTED | `runNoteDetailMoreActions` restyled (Step 7) |
| Keyboard does not cover editor | SUPPORTED | `resizeToAvoidBottomInset`, action bar above IME |

## Tooling decisions (ui-ux-pro-max, Step 2 prep)

- The skill's `--design-system` result (teal SaaS palette, Plus Jakarta Sans) is
  **rejected**: `plan.md` mandates Notion's visual language as the reference.
  Recommendation-only outputs never override the plan; tokens below come from
  live measurements instead.
- Kept universal rules from the skill: no emoji as icons, hover/press transitions
  150–200 ms ease-out, text contrast ≥ 4.5:1, visible focus rings, respect
  `disableAnimations`/reduced motion, check 375/768/1024/1440 widths.
- Flutter stack rules kept: `Theme.of(context)` only (no literal `TextStyle`/
  `Color` in components), `theme` + `darkTheme` + `themeMode`, everything via
  `ThemeData`/`ThemeExtension` tokens.

## Temporary token table (to be confirmed in Step 2)

Derived from the reference captures; not to be hard-coded per widget (plan §4.1).

| Role | Light | Dark | Notes |
| --- | --- | --- | --- |
| Page surface | `#FFFFFF` (measured) | `#191919` (measured) | live computed styles |
| Sidebar surface | warm off-white `#F7F7F5` | `#202020` | estimate from docs screenshots — verify logged-in |
| Elevated menu/dialog surface | `#FFFFFF` | `#2F2F2F`-ish | estimate from menu capture — verify |
| Text primary | `#2C2C2B` (measured) | `#F0EFED` (measured) | live computed styles |
| Text secondary | `#787774` | `#9B9B9B` | estimate — verify |
| Text muted / section label | `#9B9A97` | `#6F6F6F` | estimate — verify |
| Link/accent | `#2383E2` (blue) | `#529CCA` | estimate from docs — verify |
| Error / destructive | `#EB5757`-ish red (menu capture) | `#E06A6A` | destructive item is red text+icon (measured behaviour) |
| Success | `#0F7B6C` / `#448361` | `#5FA784` | estimate — verify |
| Divider | `#EDEDEC` | `#303030` | estimate — verify |
| Selected row bg | `#EDEDEC`-ish | `#2F2F2F` | estimate — verify |
| Code block bg | `~#F7F6F3` warm gray | `~#282828` | from code captures (estimate) — verify |

Typography: page font is the current Notion UI sans (segoe-like on web). NoteFlow
uses `Inter` with fallback `Roboto, Arial, monospace` but **no bundled asset** —
Step 2 must either bundle Inter (pubspec/asset allowlist exception) or standardise
on the documented fallback and record it in every visual diff.

Spacing scale (plan §4.1): 4/8/12/16/24/32/48. Radius: rows/inputs 6–8px,
dialogs/cards 8–12px. Motion: hover/focus/selection ≤ 200 ms ease-out, disabled
under `disableAnimations`.

## Tolerance & diff protocol

- Same DPR, viewport, theme, locale, seed data, scroll offset on both sides.
- Ignore antialias noise only; never geometry, colour or text-wrap differences.
- Separate font-engine differences from layout differences (plan §6.2).
- Every defect recorded as `screen/state/viewport/anchor/current/expected/fix`.
