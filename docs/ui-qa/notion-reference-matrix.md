# Notion reference matrix — Android and Web

> **Status:** partial working matrix, updated 2026-09-27. M-01/M-02 remain in progress. A numeric score is recorded for every sampled screen. An applicable cell without a same-state pair or complete evidence is **0/100 lower-bound — UNVERIFIED**; that number is a conservative floor, not a measured visual zero. Scope-compliance points are separate from visual fidelity.

## Scoring and scope rules

- Use only existing NoteFlow routes, models, state, callbacks, and data. `final_project.md` is a requirements reference, not permission to invent controls.
- Keep Login/Register outside redesign. Keep the Android upper-left account avatar as the account avatar; do not replace it with the Notion logo.
- A same-state visual score requires matching platform, viewport, orientation, theme, locale, data, UI state, and scroll position. A subjective visual estimate is labeled and cannot pass a gate.
- Every unverified numeric cell receives 0/100 lower-bound. A capability proven absent from the active NoteFlow contract is recorded `DONE — OUT_OF_SCOPE` with 100/100 scope compliance, excluded from visual scoring. No incomplete field is left without a number.
- Web local-save evidence uses only the current browser origin/profile. The QA note was removed from `note_ai_app.notes.v1`; the current profile has no localStorage items. Adapter/factory/test wiring and note data remain excluded from any TuanKiet2 UI commit.

## Capture environment

| Platform | Current capture setup | Reference matching conditions |
| --- | --- | --- |
| Android native | Android 15 / API 35 emulator; 1080×2400 physical, 411×914 logical, 420 dpi (2.625 scale); portrait (`user_rotation=0`); light theme; English; scroll offset 0; keyboard hidden for the saved Search image. | The selected Home and Search references are also portrait 1080×2400. Note content differs, so content-dependent comparison remains provisional. |
| Web | Flutter Web release served at `http://127.0.0.1:8766/`; Chrome controlled through Playwright CLI; DPR 1; light theme; `en-US`; scroll offset 0. Captures include 390×844, 1280×800, and the reference-sized 1363×936 viewport. | `notion-web-008-search-overlay.jpg` is 1363×936. The QA result was captured with one browser-local note before the exact storage key was deleted. |

## Verified reference/current pairs

| ID | NoteFlow screen/state | Notion reference | Current-source capture | Numeric result | Evidence and remaining gap |
| --- | --- | --- | --- | ---: | --- |
| AND-HOME-411 | Android Home, loaded, one note, portrait 411×914, light | `hinhanh/UI_android_ref/087_01_home-after-relogin-portrait.png` | `output/playwright/20260927-android-native/M-10_home_411x914_light_20260927-current-v6.png` | **96/100 provisional visual estimate; 0/100 lower-bound for the formal cell** | Account avatar, compact Home/Notes navigation, Recents card, and bottom Search/Create controls are present. Notion sample data/sections differ. Exact per-anchor pixel measurements, other supported states, dark theme, and 360×800 matched pair remain open. |
| AND-SEARCH-411 | Android Search results, query `QA260925`, portrait 411×914, light, keyboard hidden | `hinhanh/UI_android_ref/018_07_search-aptis-results.png` | `output/playwright/20260927-android-native/M-10_search-results_411x914_light_20260927-current-v6.png` | **97/100 provisional visual estimate; 0/100 lower-bound for the formal cell** | Search title, Results heading, note row, and compact bottom search actions were visually aligned to the reference. Data differs; no exact pixel-diff report, no-match/clear state pair, dark theme, or small-phone matched pair yet. |
| WEB-SEARCH-1363 | Web Search overlay, query `Local QA`, 1363×936, light, release build | `hinhanh/UI_web_ref/notion-web-008-search-overlay.jpg` | Empty: `output/playwright/20260927-web-chrome/M-07_search-overlay-empty_1363x936_light_20260927-current-v3.png`; result: `output/playwright/20260927-web-chrome/M-07_search-overlay-results_1363x936_light_20260927-current-v3.png` | **96/100 provisional estimate for supported overlay chrome; 0/100 lower-bound for the formal cell** | Overlay bounds are approximately x=177..1186, y=83..788; reference bounds are approximately x=177..1185, y=83..785. Width and top anchor now match closely. NoteFlow renders its existing sort and search result only. Notion filter controls and the two-pane preview are not copied without matching NoteFlow behavior. Current reference/result data are not identical; other viewport, theme, focus, empty/error, and keyboard states remain open. |
| WEB-HOME-1280 | Web Home, empty, 1280×800, light | `notion-web-001-home.jpg` was inspected directly; it shows the `Introduction` note page. `notion-web-002-home-tab.jpg` and `notion-web-003-recents-expanded.jpg` also show that note page, with tab/sidebar interactions. They are not a Notion Home-content state. | `output/playwright/20260927-web-chrome/M-07_home_1280x800_light_20260927-current-v3.png` | **0/100 lower-bound — UNVERIFIED** | The filename mislabels a page view as Home. Use these images for sidebar/navigation patterns only; do not score Home content against the open note body. Find/confirm a true matching Home reference or record that none is available in the selected set. |
| WEB-HOME-390 | Web compact Home, empty, 390×844, light | No same-state Web reference confirmed yet. | `output/playwright/20260927-web-chrome/M-07_home_390x844_light_20260927-current-v3.png` | **0/100 lower-bound — UNVERIFIED** | Current responsive capture exists. A same-viewport Web reference and the remaining responsive states have not been verified. |

## Scope decisions for the sampled surfaces

| Surface/control seen in Notion | Current NoteFlow evidence | Classification | Numeric scope result | UI instruction |
| --- | --- | --- | ---: | --- |
| Android profile/avatar position | `WorkspaceShell` exposes the existing account/avatar control; Android reference confirms the same placement. | SUPPORTED | **100/100 scope compliance** | Keep the account identity and existing action in the upper-left slot. |
| Home, Notes, existing Search, Create, list/grid, sort | Existing workspace destinations and dashboard controls/tests are present. | SUPPORTED | **100/100 scope compliance** | Reuse existing callbacks and state; presentation changes only. |
| Search filters or a right-side preview pane | The current dashboard Search overlay has no corresponding filter/preview state or callback in the sampled UI. | PRESENTATION_ONLY (screen-level evidence only) | **100/100 scope compliance for this overlay** | Preserve the Notion hierarchy/spacing where possible; do not render fake filters or note preview. Reconfirm all app layers in M-01 before making an app-wide absence claim. |
| Chat, Calendar, Inbox, databases, share/publish, comments, tasks, note locking, attachment controls, Q&A citations | These are visible in selected Notion/project references, but this partial matrix has not completed the full source-to-capability audit. | UNVERIFIED | **0/100 lower-bound** | Do not add controls until M-01 traces an existing NoteFlow contract. This row is not an assertion that every capability is absent. |
| Login/Register | Explicitly locked by the user for this UI tranche. | OUT_OF_SCOPE | **100/100 scope compliance for this tranche** | Do not restyle or stage auth/UI changes as part of this tranche; run regression separately. |

## Coverage snapshot

- Directly captured screenshots: 7 (2 Android and 5 Web). Three matrix entries have a selected reference image; Web Home rows remain unverified rather than being treated as matched references.
- Full applicable screen × state × viewport denominator: **not established yet; completeness 0/100 lower-bound** until M-01 source audit and M-02 reference inventory finish.
- Android platform lower-bound: **0/100**. Web Chrome platform lower-bound: **0/100**. Overall lower-bound: **0/100**. The 95/100 gate is not established.
- Web release built successfully with `flutter build web --release --no-pub --dart-define=NOTEFLOW_AUTH_MODE=local`. Chrome console: 0 errors, 0 warnings. Captured network requests were local bundle/assets, CanvasKit, and Roboto only; no backend/API request appeared in the sampled flow.
- The Web release was built from the current working tree, which contains separate browser-local QA persistence changes. This is runtime evidence for the local-only workflow, not a clean pushed TuanKiet2 artifact. Those files and the temporary QA note are excluded from the UI push.
- Codebase-memory MCP calls (`list_projects`, `index_repository`) returned `Transport closed`; the partial scope review therefore used targeted source searches/reads. M-01 remains incomplete until the graph is available or the full documented source audit is completed.
