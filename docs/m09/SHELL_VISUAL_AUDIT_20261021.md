# M09 shell, Home, Search and Notes visual audit

**Date:** 21 October 2026
**Scope:** visual review only; no source, test, build, Git or emulator changes.

## Evidence reviewed

- Actual Notion Android references: `output/m09/notion13-home.png` and
  `output/m09/notion-native-search-oct19.png`.
- NoteFlow Android runtime captures: `p6-parallel14-native-home.png`,
  `p6-parallel14-native-search.png`, and `p6-parallel12-native-notes.png`.
- NoteFlow Chrome captures: `output/playwright/p6-parallel14-web-home.png` and
  `p6-parallel13-web-search.png`.
- The live Notion Web measurements recorded in `CURRENT_WORK.md`: viewport
  1480x668, sidebar270px, top header44px, Search600px wide/top60px without the
  highlight pane. This audit did not take a new live browser capture.
- Source reviewed directly: `dashboard_content.dart`,
  `dashboard_search_sections.dart`, `dashboard_search_dock.dart`,
  `dashboard_recent_rail.dart`, `dashboard_note_card.dart`,
  `notes_list_panel.dart`, `notes_query_panel.dart`, and `workspace_shell.dart`.

The graph is indexed at 2026-10-18, before the current source14/15 changes.
`check_index_coverage` and `search_code` both returned `Transport closed`; I
used bounded reads of the current source files and treated graph findings as
stale. P14 native captures are hot-reloaded source14 UI, not a packaged
source14 APK. The p14 Home and p13 Search Web images are historical captures;
they do not identify the current served artifact. The lead reports that Web
now serves package15 (PID32248) and source16 is unbuilt. This conflicts with
the older runtime note in `CURRENT_WORK.md`, which should be refreshed before
using its runtime provenance. Capture the current Web artifact again before
pairing it with source16 or drawing a similarity conclusion.

## Findings

| Priority | Evidence and visible gap | Next UI action |
| --- | --- | --- |
| — | The earlier nominal18dp-vs16dp Search-title concern is not supported by ink measurement and is withdrawn. At threshold RGB<150, Notion ink bounds are x56..281/y208..263; NoteFlow source14 is x55..278/y261..316. Subtracting the documented52.5px dev strip gives NoteFlow y208.5..263.5: same height and only2px narrower. The results16/preview13 typography therefore looks calibrated in this state. | Keep16dp for now. Do not raise it based only on a nominal text-style value; remeasure current-source pixels if a newer capture shows a real mismatch. |
| P2 | Search groups pinned notes under a visible `Pinned` heading before date groups (`dashboard_search_sections.dart`). Notion's inspected search sample is grouped by Today/month and contains no pinned group. The current screenshots have three pinned synthetic notes, so content state differs and this is not a confirmed layout defect. | Compare equivalent synthetic content with the same pin state first. Keep NoteFlow's pin order/semantics unchanged; if the heading remains visually heavy after matching data, refine presentation only. |
| P2 | The Notes route (`p6-parallel12-native-notes.png`) adds NoteFlow-only Owned/Shared tabs, sync indicator, search, label controls and a large32dp `Notes` heading. Notion Home instead shows Recents and a simpler Private list. | Keep every existing NoteFlow operation. Reduce competing emphasis in this route and align list title/preview rhythm with the reference; retain clear affordances for sharing, labels and sync. This screen needs a matched-state pair before a similarity estimate. |
| P2 | Home card geometry is already close: current compact cards are132dp high/wide,12dp radius and16dp apart; sampled Home background is exactly RGB249,248,247 in both app and reference. | Preserve this calibrated geometry. Compare the remaining heading/icon placement and the All notes controls separately; those controls represent existing NoteFlow features absent from Notion. |
| P2 | The native shell has two workspace destinations plus the account control, while Notion's native Home shows four navigation destinations. The extra Notion destinations are not existing NoteFlow features. | Match capsule size, selection wash and spacing for the existing destinations only. Do not add navigation destinations to imitate Notion. |
| P2 | The debug identity strip appears above the app in both native and Web captures. On the native device it contributes about52.5 physical pixels; after removing that capture-only offset, Search title ink is already close to the actual reference (recorded in `CURRENT_WORK.md`). | Continue documenting the offset consistently, or capture a product-only view when available. Never count the debug strip as app chrome or silently compare unadjusted coordinates. |
| P3 | Current native Home/Search screenshots show gesture navigation. They do not establish the same layout under Android 3-button navigation, landscape, or larger text. Earlier 3-button editor evidence is from a different source round. | Re-capture the current source in gesture and 3-button modes, then check bottom controls, IME and text scaling. Keep iOS safe-area evidence open. |

## Recommended next sequence

1. Keep the measured16dp native Search title; recheck only if a fresh current
   source capture contradicts these matching ink bounds.
2. Use equivalent synthetic search content (same pin state, density and dates)
   before judging group/row resemblance. Keep pin ordering unchanged.
3. Refine the Notes route's visual hierarchy while preserving all existing
   controls and permissions.
4. Replace the stale Web package with the current source before collecting the
   next Web pair. Record source/build, viewport/theme and dev-strip offset.
5. Revisit current-source Android gesture/3-button and landscape states.

**Decision:** this bounded shell/list audit identifies refinements and missing
matched states only. It establishes no Web or Android similarity percentage;
both >=95% gates remain unverified. It is not functional acceptance.
