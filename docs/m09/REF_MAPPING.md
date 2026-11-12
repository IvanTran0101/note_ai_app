# M09 reference mapping

Status updated 19 October 2026: UI similarity NOT ACCEPTED. Open actual
Notion Web AND the actual Notion Android app and compare the matching screens/
states before further UI refinement. The mappings below are supporting local
references, not substitutes for that direct inspection. Target >=95% similarity
on EACH platform before functional regression/acceptance. Prior96.2 ratings
are withdrawn; current similarity remains unverified. See VISUAL_REVIEW.md.
Reviewed local images on 2026-10-14. Inventory: 200 Web / 218 Android.
Names are lookup keys, not proof of what a capture contains: Web001/002 show
an editor/sidebar; Android003/040 show loading only and are excluded as final
Settings references. Android013 is a home capture despite its search filename;
use the actually inspected Android215 for search. Private text/accounts in the
refs are not demo content.

## Screen and behavior mapping

| NoteFlow state | Web reference in UI_web_ref | Android reference in UI_android_ref | Apply |
| --- | --- | --- | --- |
| Workspace and note list | notion-web-001-home.jpg (sidebar/list hierarchy only) | 001_01_home_recents-favorites-private.png | Quiet background, grouped sections, outline document icons, current-row highlight, real note data. Android list/card density and safe bottom navigation. |
| Open note | notion-web-007-page-view.jpg | 014_06_recent-final-page.png | Slim top actions, generous centered document column, strong title, neutral body. Independent notes; ref child-page rows do not add nesting. |
| Rich blocks | notion-web-011-share-panel.jpg (underlying headings/callout) | 109_07_comment-editor-formatting-toolbar-portrait.png | Heading hierarchy, list/todo/toggle spacing, callout surface. Only approved13 blocks. |
| Search | notion-web-008-search-overlay.jpg | 215_search-landing-recent-pages-portrait.png | Search input, result rows, dismiss/focus behavior. Only existing keyword/labels/filter semantics; no invented database filters or ref account text. The left floating rail is Android IME UI. |
| Sharing | notion-web-011-share-panel.jpg | 106_07_share-settings-default-portrait.png | Compact invite form/member permissions; anchored desktop panel, native sheet. Owner/Editor/Viewer contract unchanged; no public Publish tab. |
| Selection toolbar | user's approved selection-toolbar capture + document visual tokens above | 109_07_comment-editor-formatting-toolbar-portrait.png | Selection-aware format controls; desktop bubble, Android bottom rail/sheet above keyboard. Add approved size12–48 and inline math. No extra AI/media commands. |
| Settings | typography/dialog tokens from document/share refs | 103_08_settings-language-offline-privacy-portrait.png | Section headings, dividers, labels/supporting text, named switches and true app settings. No new calendar/SSO/subscription flow. |
| Protection/sync/conflict/file states | document top actions + share-panel form tokens | document top actions + share sheet/Settings tokens | Compact sync status in header, discreet protection badge/action; transient details in panel/sheet. Locked content masked. Retry/errors/drafts remain visible when relevant. |
| Auth/profile/AI/diagnostics | shared typography, spacing and form tokens | shared typography, spacing and form tokens | Preserve existing functional scope and honest unavailable states; do not fabricate provider setup. |

## Geometry and tokens to implement

- Desktop: sidebar about270–280 logical px; header44–48; readable column704–720,
  title40/w700, default body16/24, H1/H2/H3/H4 about30/24/20/18 with clear weight.
  Reference1363x936 editor title begins aroundx460/y164 with sidebar open.
- Android: references1080x2400 pixels; compare logical geometry only after device
  DPR/insets are recorded. Outer gutter about20–24dp, header56dp, touch targets
  >=48dp. Title32dp; default body16dp, scalable. Avoid judging resized thumbnails.
- Light: paper white, sidebar/settings warm neutral, dark text, restrained gray
  separators, blue primary actions. Dark palette must preserve hierarchy/contrast.
- Sync: one compact header status/action. Large persistent `All synced` cards
  cannot occupy the document body. Per-note Saved follows successful local commit.
- Protection: owner actions grouped in a menu/sheet; password dialogs labeled,
  keyboard-safe and dismissible. Lock/unavailable screen replaces private content.
- Mobile editor rail respects viewInsets and safe-area without duplicate padding.
  Long tables scroll horizontally; toolbar/sheets flip/scroll rather than overflow.
- Android bottom safe zone must cover gesture AND 3-button system navigation,
  with keyboard open/closed, portrait/landscape and final scroll controls visible.
- iOS top safe zone avoids status bar/notch/Dynamic Island; retain bottom Home
  Indicator clearance. Do not claim iOS validation without an actual environment.

## Evidence and similarity (%)

For each compared state: record build, platform/device/DPR, viewport, insets,
locale, theme, text scale, keyboard/selection, actual Notion inspection time/
screen and paired NoteFlow capture; add local ref filename where helpful.
Compare layout, typography/hierarchy, spacing, colors, icons and UI states.
Use synthetic NoteFlow content; reference private text/accounts are not demos.
If a reference has no matching product function, document applicable styling
and the adaptation, preserving existing functionality. No new feature is
authorized by a reference. Missing evidence stays unverified (—).

Use similarity percentages with concrete gap/evidence explanations, not the
retired0–5 weighted points rubric. Do not convert old scores or test counts
into similarity. Both Web>=95% AND Android>=95% are required; averaging must
not hide a platform or mandatory screen still visibly different. Until BOTH
have evidence, continue reference UI work and leave functional acceptance
queued. Later functional testing still must catch data loss, permission bypass
or broken required editing; a visual gate does not certify those contracts.
