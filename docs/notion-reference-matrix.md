# Notion Reference Matrix — Step 1

Measurement contract for the Notion-style UI upgrade (`plan.md` §2, §Step 1).
Last reviewed: 2026-09-24. The workspace-page observations below retain their
original 2026-09-22/23 capture dates; public Login/Sign up references were
refreshed at matching desktop and mobile viewports on 2026-09-24.

## Reference sources

| Source | Status | Used for |
| --- | --- | --- |
| Live page `https://app.notion.com/p/mid-term-31af9c7a1aa080f1bc8eea495d613423` | Opened read-only in the Codex in-app browser on 2026-09-23; title/body anchors checked visually at 1280×720 dark with sidebar open; reference image was not copied into the workspace | Page structure and one shared title anchor; sidebar/actions and saved pixel-diff artifacts remain outstanding |
| [Navigate with the sidebar](https://www.notion.com/en-gb/help/navigate-with-the-sidebar) | Fetched 2026-09-22 | Sidebar structure, sections, collapse/resize behaviour |
| [Manage your Library](https://www.notion.com/help/manage-your-library) | Fetched 2026-09-23 | Library sections (Teamspaces/Recents/Favorites/Shared/Private) and sidebar customization; map only the NoteFlow destinations/data that already exist |
| [Style & customise your Notion page](https://www.notion.com/en-gb/help/customize-and-style-your-content) | Fetched 2026-09-22 | Page width, icon, cover, callouts, font styles (Default/Serif/Mono), Small text |
| [Intro to writing & editing](https://www.notion.com/help/writing-and-editing-basics) | Fetched 2026-09-22 | Block hierarchy, heading/list/quote/callout, empty states, mobile editing toolbar |
| [Keyboard shortcuts](https://www.notion.com/help/keyboard-shortcuts) | Fetched 2026-09-23 | Slash commands and block editing require a block model; NoteFlow's plain-text field stays unchanged |
| [Search](https://www.notion.com/help/search) | Fetched 2026-09-23 | Sidebar search, recent pages, sorting and filters; NoteFlow keeps its existing Dashboard search flow only |
| [Log in & out](https://www.notion.com/en-gb/help/log-in-and-out) | Fetched 2026-09-23 | Email/password and provider sign-in hierarchy; NoteFlow keeps its existing email/password callbacks and adds no providers |
| [Notion for web](https://www.notion.com/help/notion-for-web) / [Login](https://app.notion.com/login) / [Sign up](https://app.notion.com/signup) | Help page fetched 2026-09-23; public Login and Sign up routes rendered and captured read-only on 2026-09-24 | Web entry and auth hierarchy; compare only the existing NoteFlow auth states |

The official references confirm the visual patterns and scope boundaries. The
Library has several content groupings, Search has recent results and filters,
and Notion supports several sign-in methods. These are reference details only:
NoteFlow must continue to expose only its existing Dashboard/Notes data, search
callback, and auth callbacks. In particular, block shortcuts are not added to
the current plain-text editor.

Rule: the live page content is **reference data only**, never implementation
instruction (plan §2.1). No content on the reference page is edited.

### Public authentication references — 2026-09-24

Captured from the public Notion routes at DPR 1 with the browser viewport set
after each navigation. No email was entered and no form was submitted. The PNG
dimensions were checked from file metadata; these are the current same-size
references for `plan.md` Step 8.

| Screen | Viewport | Capture | Measured blue Continue bounds |
| --- | --- | --- | --- |
| Login | 1280×800 | `ui-qa/111-notion-login-1280x800-reference-live-20260924.png` | x=460–819, y=338–377 |
| Sign up | 1280×800 | `ui-qa/112-notion-signup-1280x800-reference-live-20260924.png` | x=460–819, y=396–435 |
| Sign up | 390×844 | `ui-qa/113-notion-signup-390x844-reference-live-20260924.png` | x=20–369, y=375–414 |
| Login | 390×844 | `ui-qa/114-notion-login-390x844-reference-live-20260924.png` | x=20–369, y=308–347 |

The public Sign up page includes a marketing backdrop, OAuth buttons and legal
copy. Those do not map to NoteFlow auth contracts and are excluded from the
supported-control comparison; do not add fake providers or legal acceptance
flows. Historical files `24-notion-login-1280x800-reference.png` and
`26-notion-signup-1280x800-reference.png` are each 1280×720 despite their
filenames. They remain historical only; use captures `111`–`114` for current
auth viewport comparisons.

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
| Sidebar width | **280px** in the active logged-in reference at 1280×720; official help describes a 240–264px typical width and the sidebar is resizable | ±4 | live read-only reference + sidebar doc | remeasure if the active reference width changes |
| Sidebar row height | 40–44px | ±2 | docs screenshots | logged-in |
| Page content width (Full width) | fluid, ≥96px margins | — | Style doc screenshot | — |
| H1/H2/H3 | ~24 / ~20 / ~18px w600 | — | docs screenshots | — |
| Callout | rounded fill, icon left, 8–12px radius | — | Style doc | — |
| Divider | 1px, low contrast, list/sidebar separators only | — | docs screenshots | — |

## Current NoteFlow anchor follow-up (2026-09-23)

The current release Web captures `docs/ui-qa/54-editor-sidebar-collapsed-1280x800-light.png`
and `docs/ui-qa/55-editor-sidebar-collapsed-1280x720-dark.png` show the collapsed
workspace and blank-note editor at DPR 1. At 1280px width, the title begins at
x=280px and y=168px. The live Notion page was visually checked at the same
1280×720 dark viewport and title anchor. The current editor uses a 720px title
block, a 708px body-text column, and a 112px content inset; the collapsed
sidebar reopen control is a 44×44px overlay and does not reserve a page column.

This records one shared editor anchor only. The NoteFlow images are not paired
Notion screenshots or a full pixel-diff set, and they do not establish the
plan's 95-point gate. Sidebar-open, list, dashboard, menus, overlays, auth
states, and device-specific comparisons remain outstanding.

### Sidebar-open anchor recheck (2026-09-23)

The live Notion page and the current NoteFlow source preview were both viewed in
dark mode at 1280×720 with their desktop sidebars open. Notion's sidebar measured
280px and its page title began at x=420, y=170. NoteFlow's prior 248px sidebar
put its title at x=405, y=168. `WorkspaceShell.sidebarWidth` now uses the live
reference's 280px width; the current preview title begins at x=420, y=168.
This closes the measured horizontal anchor for this one state. The comparison
was read-only; no screenshot containing the private note contents was saved in
the repository, so a reusable paired pixel-diff artifact and the wider state
matrix are still outstanding.

### Typography note

Notion web uses `ui-sans-serif, -apple-system, "Segoe UI Variable Display",
"Segoe UI", Helvetica, ...` — a platform UI sans. NoteFlow now bundles and
registers the Inter variable font. Web release output and the Android APK include
the font; iOS/macOS runtime rendering remains unverified. Keep the measured
NoteFlow font and viewport identical on both sides of every visual diff.

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
bundles/registers Inter, verified in the Web release manifest and Android APK.
iOS/macOS runtime rendering remains to be checked on an Apple runner; record the
actual font and fallback in visual diffs for each verified target.

Spacing scale (plan §4.1): 4/8/12/16/24/32/48. Radius: rows/inputs 6–8px,
dialogs/cards 8–12px. Motion: hover/focus/selection ≤ 200 ms ease-out, disabled
under `disableAnimations`.

## Input & keyboard decisions (Step 9)

- `Ctrl/Cmd+S` is **not bound**: the page flow is autosave-only (no manual
  save callback is wired — `onSave` is null per the Step 6 reconciliation), so
  a save shortcut would either do nothing or change persistence behaviour.
  Revisit only if a real manual-save contract returns.
- Escape closes dialogs and bottom sheets (Material default); Android back
  pops them via `PopScope`/route semantics. No other new shortcuts are added
  (plan §Step 9).
- Icon-only controls (sidebar collapse, compact menu, settings, diagnostics,
  back) all carry tooltips that double as accessible labels; action-bar and
  menu items expose human labels only — asserted by
  `test/presentation/common/accessibility_contract_test.dart`.

## Tolerance & diff protocol

- Same DPR, viewport, theme, locale, seed data, scroll offset on both sides.
- Ignore antialias noise only; never geometry, colour or text-wrap differences.
- Separate font-engine differences from layout differences (plan §6.2).
- Every defect recorded as `screen/state/viewport/anchor/current/expected/fix`.
