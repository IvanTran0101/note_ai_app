# UI audit scorecard and historical evidence archive

## Current score snapshot

**Snapshot date:** 2026-09-27. UI-only commits `ac5e27b`, `1056ef2`, and M-13 interim auth-layout commit `9e00265` are pushed to `origin/TuanKiet2`; documentation/scorecard commits `3fe9e9c` and the current score update are pushed separately. Current runtime screenshots/build use the working tree, which also has separate uncommitted browser-local QA wiring excluded from the UI commits.

| Platform/runtime | Numeric score | Current evidence and interpretation |
| --- | ---: | --- |
| Android native, portrait — Home 411×914 | **96/100 provisional visual estimate; 0/100 formal lower-bound** | Current capture v6 paired to Android ref 087. Home/Notes shell, avatar, Recents card, and Search/Create controls align as a supported visual slice. Data and remaining states differ. |
| Android native, portrait — Search 411×914 | **97/100 provisional visual estimate; 0/100 formal lower-bound** | Current capture v6 paired to Android ref 018. Main title/results/result-row anchors align closely; no exact pixel-diff or full same-data matrix. |
| Android native, portrait — existing-note editor 411×914 | **94/100 provisional estimate; 0/100 formal lower-bound** | Current M-06 capture v5 paired only to page-hierarchy ref 014. The reference has child rows rather than the same editable title/content state; debug ribbon is not part of app UI. |
| Android native — platform lower-bound | **0/100** | Applicable state × viewport × theme coverage is incomplete; unverified cells contribute zero. This is a conservative floor, not a measured zero similarity for the sampled screens. |
| Web Chrome — Search overlay 1363×936 | **96/100 supported-overlay estimate; 0/100 formal lower-bound** | Current release screenshot v3 has modal top y≈83px and width≈1009px, close to ref 008 (top y≈83px, width≈1008px). Notion-only filter/preview behavior is not fabricated. |
| Web Chrome — existing-note editor 1280×800 | **92/100 provisional chrome estimate; 0/100 formal lower-bound** | Current release capture compared visually with page ref 007. Current title x≈420px vs ref x≈465px; viewport/content/state do not match, so this is a follow-up alignment finding, not a gate score. |
| Web Chrome — existing-note editor 1920×906 | **95/100 provisional geometry estimate; 0/100 formal lower-bound** | Wide-Web layout now allows a 1200px editor column and 1188px text column. At 1920px with the 280px workspace sidebar, constraints predict title x≈500px, near x≈526px in the user screenshot. Release build and targeted analysis pass; UI-only commit `1056ef2` is pushed to `origin/TuanKiet2`. Post-fix screenshot awaits Web sign-in after reload returned to Login. |
| Web — Login 1920×906 | **0/100 lower-bound — UNVERIFIED** | Current release capture `.playwright-cli/page-2026-09-27T07-09-12-530Z.png` shows the unboxed form centered in the full viewport. The selected Notion Login ref is 1280×800, so this is not a matched viewport/state pair. |
| Web — Register desktop | **0/100 lower-bound — UNVERIFIED** | Computer Use visually checked the compact route. The full auth widget suite passed 23/23, including the desktop panel/footer geometry assertion, via the existing test-only package-root shim; a current-source desktop screenshot and matched reference measurement are still unavailable. |
| Android native — Login/Register portrait | **0/100 lower-bound — UNVERIFIED** | The current change is guarded to desktop layout, and the compact branch was visually viewed in the Web preview at 397×675. That preview is not a native Android capture. |
| Web Chrome — existing-note editor 390×844 | **0/100 lower-bound — UNVERIFIED** | Current responsive capture exists; no Web reference with a matched compact editor state/viewport is in the selected matrix. |
| Web Chrome — Home 1280×800 | **0/100 lower-bound — UNVERIFIED** | Ref `notion-web-001-home.jpg` was inspected and is actually an open note page; 002–003 show that same note page with sidebar/tab changes. No valid Home content pair is established. |
| Web Chrome — platform lower-bound | **0/100** | Web renders in Chrome, but Home ref mapping and the required viewport/state/theme matrix are incomplete. |
| M-01 capability/scope audit | **0/100 lower-bound** | The source-to-feature matrix is partial. Confirmed screen-level scope decisions are separate and cannot be used as the overall audit score. |
| M-02 reference/capture coverage | **0/100 lower-bound** | Seven screenshots are logged; three entries have selected reference images. The full applicable denominator and Web Home reference remain unresolved. |
| **Overall platform lower-bound** | **0/100** | Minimum of Android and Web platform floors. The 95/100 platform gate is not established. |

**Numeric scoring rule:** every current screen and platform has a number. An applicable cell without complete current evidence is **0/100 lower-bound — UNVERIFIED**. Provisional visual estimates are shown separately and never count as a gate pass. `N/A` is reserved for a capability proven absent from the active contract. Scope-compliance 100/100 is not a visual score. See `plan.md` §4.3.

### Latest implementation evidence — 2026-09-27

| Platform/state | Reference | Current-source evidence | Numeric score | Status / limitation |
| --- | --- | --- | ---: | --- |
| Android Home, 411×914 portrait, light | `hinhanh/UI_android_ref/087_01_home-after-relogin-portrait.png` | `output/playwright/20260927-android-native/M-10_home_411x914_light_20260927-current-v6.png` | **96 estimate; formal 0/100** | Avatar remains profile identity. Current one-note content differs from Notion sample; full platform matrix incomplete. |
| Android Search results, 411×914 portrait, light | `hinhanh/UI_android_ref/018_07_search-aptis-results.png` | `output/playwright/20260927-android-native/M-10_search-results_411x914_light_20260927-current-v6.png` | **97 estimate; formal 0/100** | Search `QA260925`; portrait, keyboard hidden. Estimate only, not a measured full cell. |
| Android existing-note editor, 411×914 portrait, light | `hinhanh/UI_android_ref/014_06_recent-final-page.png` (page-hierarchy anchor only) | `output/playwright/20260927-android-native/M-06_editor-existing-note_411x914_light_20260927-current-v5.png` | **94 estimate; formal 0/100** | Same portrait dimensions; reference is a page with child rows, not an equivalent editable note. Ignore the Flutter debug ribbon when judging app UI. M-06 focused suites: workspace shell 23/23, Notes workspace 29/29, detail page 14/14, action bar 7/7, detail surface 29/29. |
| Web Search overlay empty, 1363×936, light | `hinhanh/UI_web_ref/notion-web-008-search-overlay.jpg` | `output/playwright/20260927-web-chrome/M-07_search-overlay-empty_1363x936_light_20260927-current-v3.png` | **96 supported-chrome estimate; formal 0/100** | Bounds align closely; internal controls differ where NoteFlow has no confirmed equivalent. |
| Web Search overlay result, 1363×936, light | `hinhanh/UI_web_ref/notion-web-008-search-overlay.jpg` | `output/playwright/20260927-web-chrome/M-07_search-overlay-results_1363x936_light_20260927-current-v3.png` | **96 supported-chrome estimate; formal 0/100** | One local QA note was present during capture; cleared afterward. Ref data differs and preview pane is not in NoteFlow Search. |
| Web existing-note editor, 1280×800, light | `hinhanh/UI_web_ref/notion-web-007-page-view.jpg` (page-canvas anchor; not same viewport/data) | `output/playwright/20260927-web-chrome/M-08_editor-existing-note_1280x800_light_20260927-current-v1.png` | **92 estimate; formal 0/100** | Current note title x≈420px; ref title x≈465px. Re-measure with same viewport/data and adjust content column in M-08 if the gap remains. |
| Web existing-note editor, 1920×906, light | User screenshot in the 2026-09-27 request | Post-fix capture pending; release build contains the new responsive width bounds (editor 1200px, text 1188px at this viewport) | **95 provisional geometry estimate; formal 0/100** | Expected title x≈500px with current 280px sidebar, against x≈526px in the supplied screenshot. UI-only commit `1056ef2` was pushed. Browser reload redirected to Login because the prior in-memory auth session did not persist; capture and measured score still require sign-in. |
| Web existing-note editor, 390×844, light | No same-state compact Web ref confirmed | `output/playwright/20260927-web-chrome/M-08_editor-existing-note_390x844_light_20260927-current-v1.png` | **0/100 lower-bound** | Current compact note title/body render and remain after same-origin reload; numeric floor is zero until a matching reference pair exists. |
| Web Home empty, 1280×800, light | `notion-web-001-home.jpg` (mismatch: open Introduction page) | `output/playwright/20260927-web-chrome/M-07_home_1280x800_light_20260927-current-v3.png` | **0/100 lower-bound** | No same-state Home reference. |
| Web Home empty, 390×844, light | No matching Web ref confirmed | `output/playwright/20260927-web-chrome/M-07_home_390x844_light_20260927-current-v3.png` | **0/100 lower-bound** | Current responsive capture only. |
| Web Home at 1363×936 with local QA note | `notion-web-003-recents-expanded.jpg` used only for sidebar/Recents pattern | `output/playwright/20260927-web-chrome/M-07_home_1363x936_light_20260927-current-v3.png` | **0/100 lower-bound** | Reference content remains an open note page; data differs. |
| Web Login, full desktop viewport 1920×906 | Notion Login ref `111-notion-login-1280x800-reference-live-20260924.png` | `.playwright-cli/page-2026-09-27T07-09-12-530Z.png` | **0/100 lower-bound — UNVERIFIED** | Computer Use preview at 397×675 separately showed the compact Login route. The desktop capture confirms the full-width viewport and centered unboxed form, but viewport differs from reference; no fidelity pass is claimed. |
| Web Register, compact preview 397×675 | Notion signup ref `112-notion-signup-1280x800-reference-live-20260924.png` | Computer Use preview, `http://127.0.0.1:8768/#/register` | **0/100 lower-bound — UNVERIFIED** | Compact layout was visually present. This is an in-app Web viewport, not native Android; desktop Register remains uncaptured. |
| Android auth, portrait | Android ref `077–083` | No current-source native capture for this tranche | **0/100 lower-bound — UNVERIFIED** | Compact layout branch is unchanged by M-13; native Android runtime was not used to award visual points. |

### Verification and evidence boundaries

- Dashboard tests: **44/44 pass**. Workspace shell tests: **22/22 pass**. Targeted `flutter analyze --no-pub`: **no issues**. Dart format check: **pass**. Targeted `git diff --check`: **pass**. `.dart_tool/package_config.json` restored to SHA-256 `BB1F5D5C8F88BED214DF461A6D8B4B7F62CAB1F38829E65E05C4FEA9C9D73025` after test-only shim runs.
- M-06 focused UI suites: **102/102 pass** across workspace shell (23), Notes workspace (29), detail page (14), detail action bar (7), and detail surface (29). The tests compile the changed UI. A later broad targeted analyzer run stayed at `Analyzing...` and was stopped; the most recent pre-style targeted analyzer result remains the earlier clean result, so record this analyzer attempt as unverified for the final small style adjustments. `.dart_tool/package_config.json` restored to SHA-256 `BB1F5D5C8F88BED214DF461A6D8B4B7F62CAB1F38829E65E05C4FEA9C9D73025` after test-only shim runs.
- `flutter build web --release --no-pub --dart-define=NOTEFLOW_AUTH_MODE=local`: **pass, latest rebuild 101.3s**. Chrome rendered Home, Search, and editor at 390×844, 1280×800, and Search ref-sized 1363×936. Console: **0 errors, 0 warnings**. Sampled requests were app bundle/assets, Roboto, and CanvasKit; no backend/API request appeared in the sampled browser flow.
- Browser-local QA created, autosaved, reopened, and reloaded one note in the same origin/profile. After screenshots, only `note_ai_app.notes.v1` was deleted; `localstorage-list` returned empty. This verifies the local-only QA flow, not remote sync. Adapter, factory, tests, and data remain excluded from the TuanKiet2 push.
- Android recaptured from the running debug emulator after hot reload. `user_rotation=0`; captures are portrait only. The Search-to-Home tap accidentally returned to the launcher once; the app was reopened via its package and a fresh Home capture was made. No landscape image was produced.
- M-13 auth presentation follow-up: interim UI commit `9e00265` is pushed to `origin/TuanKiet2`. Computer Use reopened the just-built preview and visibly checked Login and Register at its available 397×675 viewport in the persisted dark theme. The 1920×906 Web Login release capture shows the full-width viewport and centered unboxed form; desktop Register and native Android captures remain outstanding. `flutter analyze --no-pub lib/presentation/auth/auth_pages.dart test/presentation/auth/auth_pages_test.dart` passed with no issues in 41.2s; `flutter build web --release --no-pub --no-wasm-dry-run` passed in 108s. The entire auth widget suite passed 23/23 using the existing test-only package-root shim, which bypasses the unrelated corrupt native hook; `.dart_tool/package_config.json` was restored to SHA-256 `BB1F5D5C8F88BED214DF461A6D8B4B7F62CAB1F38829E65E05C4FEA9C9D73025`. Android auth and both Web auth fidelity cells remain numeric `0/100 lower-bound — UNVERIFIED` until current-source reference/current pairs cover each runtime, viewport and state; no `>=95/100` claim is made.
- Codebase-memory MCP `list_projects` and `index_repository` both returned `Transport closed`; the partial capability review used targeted source search/read and must not be represented as a complete M-01 audit. Seven reference anchors were opened directly in this plan revision; the 218/200 image inventories are still not fully audited.

### Active numeric evidence ledger

| Platform/browser | Viewport | Screen/state | Reference/current anchor | Numeric score / evidence status | Remaining gap |
| --- | --- | --- | --- | --- | --- |
| Android | 411×914 portrait, light | Home, one note | Ref `087_01_home-after-relogin-portrait.png`; current v6 | **96/100 estimate; formal 0/100 lower-bound — UNVERIFIED** | Data differs; exact measurements, 360×800, dark, empty/error/loading and accessibility not audited. |
| Android | 411×914 portrait, light | Search result | Ref `018_07_search-aptis-results.png`; current v6 | **97/100 estimate; formal 0/100 lower-bound — UNVERIFIED** | Query/data differ; no-results/clear/list variants and dark theme remain. |
| Android | 411×914 portrait, light | Existing-note editor | Ref `014_06_recent-final-page.png` as page hierarchy only; current M-06 v5 | **94/100 provisional; formal 0/100 lower-bound — UNVERIFIED** | Not an equivalent editable-note state; dark, 360×800 and autosave/error matched cells remain. |
| Web Chrome | 1363×936, DPR 1, light | Search empty/results overlay | Ref `notion-web-008-search-overlay.jpg`; current v3 | **96/100 estimate for supported shell; formal 0/100 lower-bound — UNVERIFIED** | Geometry close. Filters/preview are not implemented in NoteFlow; additional viewport, keyboard/focus and matched data states remain. |
| Web Chrome | 1280×800, DPR 1, light | Existing-note editor | Ref `notion-web-007-page-view.jpg` (viewport/state differs); current M-08 v1 | **92/100 provisional; formal 0/100 lower-bound — UNVERIFIED** | Current title x≈420px vs ref x≈465px; remeasure same viewport before changing gutter. |
| Web Chrome | 390×844, DPR 1, light | Existing-note editor | No matching compact editor ref confirmed; current M-08 v1 | **0/100 lower-bound — UNVERIFIED** | Current capture only; matched ref, dark and keyboard/focus cells remain. |
| Web Chrome | 1280×800, light | Home empty | `notion-web-001-home.jpg` inspected as an open note page; current Home v3 | **0/100 lower-bound — UNVERIFIED** | Wrong reference state. Do not reuse the 89 estimate from old scorecard. |
| Web Chrome | 390×844, light | Home empty | No matching reference confirmed; current Home v3 | **0/100 lower-bound — UNVERIFIED** | No paired Web reference; tablet and 1440×900 captures also remain. |

Coverage denominator for each platform: **not established**. Android lower-bound **0/100**, Web lower-bound **0/100**, Overall **0/100**. The target **95/100 is not passed or established** by the provisional screen estimates.

---

## Historical evidence archive

The records below were moved from plan.md beginning at the former implementation checklist. Earlier unscored labels have been normalized to numeric `0/100 (lower-bound)` values so every score stays numeric; these historical lower-bounds indicate missing evidence, not measured zero visual similarity. The records remain historical unless independently confirmed against the current source.

---

### Re-review 2026-09-23 — corrective audit

Execution checkout: branch `TuanKiet2`, committed base `926b590` before the auth email-first tranche.
The previous table's `DONE` labels for Steps 0–9 and its `95/100` claim are
withdrawn. The checklists in Sections 5 and 6 were still unchecked, the stored
captures were not paired with same-state Notion captures for every viewport,
and the current browser cannot load a persisted note. The old score therefore
does not prove the plan's `>=95` gate. Treat every step below as incomplete
until its stated evidence is captured against the active checkout.

This corrective UI pass now includes neutral Notion-matched theme tokens, a
720px title block with 708px body-text width, a 112px editor content inset, a
page header with the existing back/dirty-confirmation path, full-page
list/editor navigation on medium and wide layouts, and explicit load-error
states that do not claim the collection is empty. The collapsed desktop sidebar
now uses a 44×44px reopen overlay and reserves no permanent content column.
Current NoteFlow captures show the title anchor at x=280, y=168 for 1280px
width when the desktop sidebar is collapsed. A same-state live comparison at
1280×720 dark with both sidebars open measured the Notion title at x=420, y=170;
the current source preview after matching the sidebar width measured NoteFlow
at x=420, y=168. This is one paired anchor check, not a saved pixel-diff or a
full-page score. Captures 54–55 record the collapsed NoteFlow state only. The sidebar, list,
dashboard, auth, and other states still need paired review. Earlier targeted
analyzer, presentation tests, web release build, and Android release APK build
passed; the Android build used JDK 17. The latest targeted widget run after the
editor and collapsed-sidebar adjustments did not reach assertions because the
`local_llm_bridge` native-asset hook encountered a corrupt `.obj` file. The full
repository run with the test shim reports 600 passed and two AI infrastructure
tests unable to load; a direct test without the shim confirms native asset
compilation stops at `llama-kv-cache-dsv4.obj : fatal error LNK1136: invalid or
corrupt file`.
The current Web preview explicitly reports that it cannot load or save notes;
there is no persisted-note state to compare in the browser. Persistence and the
full visual score remain unverified; no score of 95 or higher is claimed.

Auth follow-up on 2026-09-23: captures 29–32 record the earlier Login/Register
layout and are historical. Captures 66–69 recorded Login and Register at
1280×800 and 390×844, paired by viewport with reference captures 24, 26, 20,
and 22. Login captures 66/69 remain current; Register captures 67/68 predate
the email-first and panel-top refinements. The side-by-side review finds the
brand/header placement,
form width, and core surfaces close, while the auth flows still differ in
hierarchy and content: NoteFlow keeps its supported password Login and
four-field registration; Notion's references show an email-first step and
provider controls. No auth provider or backend behavior is added to imitate
those unsupported controls. This is a qualitative visual review only, not a
rubric score: the four captures do not cover all auth states, accessibility,
or target platforms, so no auth or app-wide numeric score is assigned. The
available evidence does not establish the `>=95/100` gate.

Typography follow-up on 2026-09-23 (Inter experiment; later superseded): the app theme requested the `Inter` family,
but the checkout contained no Inter font asset or pubspec font registration.
The UI-only asset pass bundles the Inter variable font and OFL license and
registers the family in `pubspec.yaml`; it adds no package and changes no auth,
note, route, or data flow. FontTools confirms the `opsz` 14–32 and `wght`
100–900 axes and Vietnamese glyph coverage (font SHA-256
`29160A80FF49DDCAB2C97711247E08B1FAB27A484A329CE8B813D820DC559031`).
`flutter analyze --no-pub lib` passes, and the current presentation suite passes
191/191 with the temporary test-only `local_llm_bridge` shim and restored
package-config hash below. The Web release build passes (Flutter 3.47.5,
399.1s); `FontManifest.json`, the font, and OFL file are present in its output.
The Android release APK also passes (92,217,544 bytes; 1,758.1s), and its
archive contains the same font and license. Capture 86 shows the bundled font
rendered in the 1280×720 light Web Home; this page displays the existing Web
storage limitation and contains no loaded or persisted note. The unfiltered
`flutter analyze --no-pub` still reports 42 existing issues in the unrelated
`local_llm_bridge` tests and temporary output shim; no files in those areas are
part of this asset change. iOS/macOS builds and device rendering remain
unverified because this Windows environment lists only Windows, Chrome, and
Edge in `flutter devices --machine`. These checks close the Web/Android font
packaging gap only; they do not establish full cross-platform typography or the
95-point visual gate.

Current Login uses 38px compact/72px desktop top padding. Register starts with
Email, followed by Display name, Password, and Confirm password; it uses 76px
compact/42px desktop top padding and a 496px desktop panel, with the existing
32px fallback for short viewports. `_AuthFormScaffold` now keeps its selected
page background painted through the available viewport while preserving scroll
when content is taller. The auth widget suite passes 11/11 with the temporary
test-only `local_llm_bridge` package-root shim. Coverage checks the background
at 360×800, 393×852, 768×1024, 1280×550, 1280×800, and 1440×900 for both Login
and Register, plus 200% text-scale submit reachability at 360×800.
`.dart_tool/package_config.json` was restored to SHA-256
`BB1F5D5C8F88BED214DF461A6D8B4B7F62CAB1F38829E65E05C4FEA9C9D73025`.
Widget assertions cover the Email/Display name order and 393×852, 1280×800,
and 768×1024 layout bounds; the desktop registration panel top is constrained
to 28–36px around the 32px Notion reference anchor. Captures 67–68
predate these changes. Capture 85 shows the current source at 1280×800 in a
signed-out debug Web run; the Flutter debug ribbon is visible and excluded
from fidelity scoring. The local-auth release preview rendered Home after
navigation to `/register`; I did not override auth state. A
previous current-source presentation run passed 189/189 using a temporary
test-only package-root shim for the unrelated native `local_llm_bridge` hook.
After adding the text-scale and viewport-background checks, the full
current-source presentation suite passed 191/191 and the auth page suite passed
11/11. The package config was
restored byte-for-byte to SHA-256
`BB1F5D5C8F88BED214DF461A6D8B4B7F62CAB1F38829E65E05C4FEA9C9D73025`. An
earlier run had hit a transient disk-full error and stalled; it is superseded
by this completed presentation-suite run.

Web warning follow-up on 2026-09-23: the editor keeps the explicit notice that
draft changes cannot be saved and will be lost when leaving, but uses a muted
cloud-off icon and neutral surface for unsupported storage. The page-header
status and Home limitation notice now use the same muted icon; ordinary
save/load errors remain errors. Captures 47–48 record the 1280×800 Web states.
Targeted `flutter analyze` and the Web release build pass. The focused
note-detail widget test stops before assertions because native linking reports
53 unresolved GGML/llama symbols in `local_llm_bridge.dll`. This remains a test
environment blocker; paired Notion comparisons and device visual QA are still
incomplete, so this does not establish the 95-point gate.

Responsive editor recheck on 2026-09-23: captures 49–50 from an earlier release
preview appeared to show the title resetting after resize. A fresh release
build from the current source, served from a distinct output directory and
port, retained the same title and body through 1280×800 → 390×844 → 768×1024 →
1280×800, including after the Web storage-unavailable notice appeared. Treat
49–50 as superseded observations; the original discrepancy is unresolved and
must not be described as a confirmed current regression. The fresh run exposed
a separate compact-width title clipping issue. `NoteDetailEditorForm` now lets
long titles wrap, keeping its existing controller, key, focus node, and
callbacks. The latest Web release build renders the title across multiple
lines at 390×844 and retains the dirty draft at 768×1024 and 1280×800 (captures
51–53). Targeted analyzer passes. The focused widget test remained in the
`local_llm_bridge` native-asset hook for 90 seconds and was interrupted before
assertions. This closes only the observed Web wrap/resize checks; it does not
verify successful persistence or the overall 95-point gate.

The Web dirty-back flow was also checked in the release browser at 390×844:
after entering a temporary title and navigating back, capture 56 shows the
existing unsaved-changes dialog with the explicit Web draft-loss message and
Cancel/Discard actions; it does not offer Save. This verifies the presentation
of that one limitation state only, not persistence, the remaining overlays, or
the overall 95-point gate.

The same browser flow revealed that discarding a Web draft cleared the notes
load error and displayed the empty collection state. The presentation state now
retains the load error on discard/cancel and clears it after save/delete;
capture 57 confirms the Web storage-unavailable state remains visible after
discard. The regression in
`test/presentation/notes/notes_workspace_page_test.dart` passed as part of the
37-test focused workspace suite using a temporary test-only
`local_llm_bridge` shim. The original `.dart_tool/package_config.json` was
restored byte-for-byte (SHA-256
`BB1F5D5C8F88BED214DF461A6D8B4B7F62CAB1F38829E65E05C4FEA9C9D73025`). This
checks state retention only; it does not verify Web persistence or the overall
95-point visual gate.

Auth email-first presentation follow-up on 2026-09-23: Login now presents Email
before the existing Password field; Register presents Email before the existing
Display name, Password, and Confirm password fields. Continue only advances
local presentation state; the final action still calls the existing controller
with the existing `LoginInput` or `RegisterInput`. No auth controller, route,
domain, application, infrastructure, or persistence file changed. The complete
presentation suite passed 193/193 using the temporary test-only
`local_llm_bridge` shim; `.dart_tool/package_config.json` was restored to SHA-256
`BB1F5D5C8F88BED214DF461A6D8B4B7F62CAB1F38829E65E05C4FEA9C9D73025`. Targeted
`flutter analyze --no-pub` on the two auth sources and two auth test files found
no issues, and `git diff --check` passed. No release/browser capture of these
new auth steps has been made, so no auth or app-wide numeric visual score is
assigned and the `>=95/100` gate remains unproven.

Auth visual recheck on 2026-09-24 (historical Inter-era capture; superseded by
the platform-font recapture below): the live public Notion Login and Sign up
pages were captured at 1280×800 and 390×844 (references 111–114), with no form
submission. Historical references 24 and 26 are 1280×720 despite their
filenames. NoteFlow captures 104–110 cover the earlier Inter-rendered
Login/Register states; their CTA measurements apply only to that source and
must not be used as current geometry. The current source measurements and
screenshots are in the later Platform-font and Register recapture entry. No
auth controller, route, DTO, service, or persistence file changed. Neither the
historical captures nor the current auth pair establish the app-wide
`>=95/100` release gate.

Shared navigation focus follow-up on 2026-09-24: `NoteFlowSidebarRow` now
renders the existing theme `focusRing` token as a 2dp outline while focused.
Keyboard Tab traversal, focus loss, and light/dark token colors are covered in
the primitive widget test; callbacks, selected semantics, labels, and hit area
remain unchanged. The full presentation suite passes 200/200 using a temporary
test-only `local_llm_bridge` package-root shim; direct test startup still hits
the unrelated `llama-vocab.obj` `LNK1136` hook failure. The package config was
restored to SHA-256
`BB1F5D5C8F88BED214DF461A6D8B4B7F62CAB1F38829E65E05C4FEA9C9D73025`.
`flutter analyze --no-pub lib/main.dart lib/presentation` and
`dart format --output=none --set-exit-if-changed lib test` pass, as does
`git diff --check`. Web
release builds in 72.5s and Android release APK builds at 88.0 MB in 58.5s.
The 2026-09-23 runtime discovery found only Windows, Chrome, and Edge, with no
Android AVD. A later Android 15/API 35 Login/Register runtime check is recorded
below; iOS/macOS runtime/build checks remain unavailable on this Windows host.
The focus treatment and compile checks do not assign a numeric app-wide score;
the `>=95/100` gate remains unproven.

Dashboard density follow-up on 2026-09-24: on available width >=840dp the
existing Home collection now defaults to a compact card grid; below that
breakpoint it defaults to the existing single-column List. The existing
List/Grid control still overrides that default. Wide grid columns are sized
from a 136dp minimum card width, capped at six; grid cards use the existing
note title, preview, updated date, page icon, theme surfaces, semantics and
open-note callback. List cards and all controller/data contracts are unchanged.
The dashboard widget suite passes 39/39, including 200% desktop text scale, and
the full presentation suite passes 202/202 with the temporary test-only bridge
package root; both restore
`.dart_tool/package_config.json` to SHA-256
`BB1F5D5C8F88BED214DF461A6D8B4B7F62CAB1F38829E65E05C4FEA9C9D73025`.
Targeted analyze reports no issues; Web release build passes in 53.5s and
Android release APK builds at 88.0MB in 68.0s. These are compile checks only.
Current Home screenshots predate this layout change; the Web runtime still
cannot load a persisted note, so widget fixtures do not substitute for native
data or same-state Notion captures. No numeric fidelity score is assigned and
the `>=95/100` gate remains unproven.

Android Home/editor/autosave runtime follow-up on 2026-09-24: a temporary
release APK built from `e0b6181` with the existing
`NOTEFLOW_AUTH_MODE=local` build define installed on the Android 15/API 35 AVD
using `adb install -r`; the signing certificate matched the backed-up Cognito
release. Captures 128–129 record the actual empty Home and blank editor at
1080×2400. A note entered through the existing UI appeared in the Home list,
remained after force-stop/relaunch, and reopened with the existing “Note saved.”
status. The exact QA note was deleted through the existing More → Delete flow;
Home returned to “No notes yet.” The original Cognito release APK was restored
byte-for-byte (SHA-256
`5E0480792576BC417B497EF61548FBD2F24B642F1AEAADD5E30BA0D563988339`) and
reinstalled; app data was not cleared. This verifies Android local-mode UI and
autosave behavior only. It does not change the Web persistence limitation or
provide a matched Notion visual pair. No numeric fidelity score is assigned;
the `>=95/100` gate remains unproven.

Dashboard empty-state presentation tranche — 2026-09-24: on the `TuanKiet2`
checkout based on `c162b4a`, `DashboardEmptyView` removes its tinted bordered
surface so the existing empty message and create action sit directly on the
page canvas, aligned with the Home content gutter. The semantics container,
label, keys, `onCreateNote` callback, note data and all application contracts
are unchanged. `flutter analyze --no-pub` on the Dashboard source/test passes;
`dashboard_page_test.dart` passes 39/39 using the existing temporary test-only
`local_llm_bridge` package root and restores `.dart_tool/package_config.json` to
SHA-256 `BB1F5D5C8F88BED214DF461A6D8B4B7F62CAB1F38829E65E05C4FEA9C9D73025`.
The Android release QA APK builds in 72.7s at 87.2MB. Capture 130 shows the
empty Home at 1080×2400 on the Android 15/API 35 AVD; tapping the existing CTA
opens the new-note editor, and backing out of the clean draft returns to the
empty Home without creating a note. The previous Cognito release APK and its
SHA-1 sidecar were restored; the APK SHA-256 remains
`5E0480792576BC417B497EF61548FBD2F24B642F1AEAADD5E30BA0D563988339`.
`flutter build web --release --no-pub --dart-define=NOTEFLOW_AUTH_MODE=local`
passes in 86.5s, and a 1280×720 dark Web runtime check displays the existing
storage-unavailable message; the empty state is not reachable on Web. iOS and
macOS builds/runtime remain unavailable on this Windows host. This tranche
does not provide a same-state Notion pair or a 95-point score; the score stays
unassigned and Step 4's visual comparison gate remains open.

Home reference-anchor correction — 2026-09-24: a same-viewport Web 1280×720
dark comparison with both sidebars open showed the Home title at x≈325/y≈117,
while the live Notion page title anchor was x≈420/y≈168. The desktop Home
content now uses a 768px outer column, 24px internal gutters (720px usable
width), and 116px top inset; the measured title is x≈420/y≈169. The existing
wide Grid sizes cards from 136px minimum width and caps at four columns to fit
that measured content width; existing List/Grid selection and note callbacks
remain intact. Capture 135 records the NoteFlow Web runtime at the matched
viewport/theme, including its existing storage-unavailable message; no private
Notion page screenshot or content was saved. Capture 136 records the Android
15/API 35 empty Home at 1080×2400. `dashboard_page_test.dart` passes 39/39 with
the temporary test-only bridge package root, targeted analyze and format pass,
Web release build passes in 87.5s, and Android x64 local-auth release build
passes in 62.1s at 35.7MB. The original Cognito APK was restored byte-for-byte
and its SHA-256 remains
`5E0480792576BC417B497EF61548FBD2F24B642F1AEAADD5E30BA0D563988339`; Android
Login was verified after reinstall. The direct Windows test invocation still
fails before tests at the native hook linker (`llama-vocab.obj`, `LNK1136`);
the test-only shim run passed and `.dart_tool/package_config.json` was restored
to SHA-256 `BB1F5D5C8F88BED214DF461A6D8B4B7F62CAB1F38829E65E05C4FEA9C9D73025`.
This improves one desktop Home anchor and adds Android empty-state evidence;
other Home states, page workflows, theme/platform pairs, and accessibility
remain open. No overall fidelity score is assigned and the `>=95/100` gate
remains unproven.

Register CTA alignment follow-up — 2026-09-24 (widget-only historical estimate; superseded by browser measurements below): the existing email-first
Register step now uses the 12dp compact gap and 16dp desktop gap before its
existing Continue action; the details-step gap remains unchanged. The shared
auth submit button is 44dp high to retain the plan's minimum touch target. The
widget test constrains the mobile CTA top to y=372–378 against the live Notion
reference y=375, and desktop to y=392–400 against y=396. These are current
widget-geometry checks, not a release screenshot or pixel-diff result. The auth
page and navigation integration suites pass 18/18 using the temporary test-only
`local_llm_bridge` package root; the original package-config SHA-256 is restored
to `BB1F5D5C8F88BED214DF461A6D8B4B7F62CAB1F38829E65E05C4FEA9C9D73025`.
Targeted analysis and formatting pass. Only `lib/presentation/auth/auth_pages.dart`
and its presentation test changed; auth controllers, routes, DTOs, services,
domain, application, infrastructure, persistence and backend remain untouched.
Desktop Register details and validation/busy/error/success/change-password
states remain to verify. Step 8 remains in progress; no numeric auth or overall
fidelity score is assigned, and the `>=95/100` gate is still unproven.

Register mobile heading alignment follow-up — 2026-09-24 (superseded and
incorrect): the 10dp brand/title gap, 52dp content gap, and y=108–112 heading
claim came from widget-test font metrics after changing the font setup; they did
not represent the Web runtime. Do not use those values as current evidence. The
replacement platform-font and browser measurements are recorded below.

Platform-font and Register recapture — 2026-09-24: NoteFlow no longer forces
Inter; `fontFamily` is unset and the Inter/OFL registration was removed from
`pubspec.yaml`. The Web `FontManifest.json` contains only MaterialIcons and
CupertinoIcons, and the fresh Android ARM64 release APK contains no Inter asset.
The Register email step uses the browser-measured layout values: 34dp compact
brand/title gap, 28dp content gap, 20dp compact Continue gap, 42dp desktop
panel top padding, and a 48dp auth submit minimum. Fresh release Web captures [138](docs/ui-qa/138-noteflow-register-platform-font-390x844-current-20260924.png)
and [139](docs/ui-qa/139-noteflow-register-platform-font-1280x800-current-20260924.png)
show the blank, focused email field at 390×844 and 1280×800. Against Notion
references 113 and 112, the blue CTA bounds are y=375–414 on mobile and
y=396–435 on desktop, matching the reference's 40px visible height and top
anchors. The desktop card top aligns at y≈43. Its lower content remains shorter
because Notion's provider/legal actions have no NoteFlow contract and are not
fabricated. The auth suite passes 34/34 and the complete presentation suite
passes 209/209; scoped analysis and Web release plus Android ARM64 release
builds pass.
`.dart_tool/package_config.json` was restored to SHA-256
`BB1F5D5C8F88BED214DF461A6D8B4B7F62CAB1F38829E65E05C4FEA9C9D73025`. Only
theme/font selection and unused font assets, auth presentation spacing/touch
target, its widget test, and QA documentation changed; auth callbacks/routes
and domain, application, infrastructure, persistence, and backend code remain
untouched. Android font
runtime plus iOS/macOS rendering remain unverified. This evidence covers only
the existing Register email state in Web; no numeric auth/app score is assigned
and the `>=95/100` gate remains unproven.

Login system-font recapture — 2026-09-24: fresh blank, focused email-state Web
captures [140](docs/ui-qa/140-noteflow-login-platform-font-390x844-current-20260924.png)
and [141](docs/ui-qa/141-noteflow-login-platform-font-1280x800-current-20260924.png)
pair with Notion refs 114 and 111. The mobile CTA is within 1px of the reference
at y=309–348 vs y=308–347; the desktop CTA is 5px high at y=333–372 vs
y=338–377. The desktop heading/field group also begins roughly 8–10px early,
and the existing recovery hint wraps to two lines. Notion provider/legal actions
are omitted because NoteFlow has no matching callbacks. The auth suite passes
34/34 and the full presentation suite passes 209/209 after the responsive spacing
edit; scoped analysis and Web/Android ARM64 release builds pass. This adds Web
evidence only; Login states after Continue, password, validation, recovery and
errors plus Android/iOS/macOS visual pairs remain open.

Compact editor title scale follow-up (superseded by the 40dp remeasurement
below) — 2026-09-24: `NoteDetailEditorForm` now
uses a 36dp page-title style below the existing 600dp compact breakpoint and
retains 40dp at wider widths. The adjustment follows a visual review of the
open Notion page at a 567px-wide browser viewport; no page content was changed
or saved. Widget tests verify compact typography at 390px and 567px, desktop
typography at 1024px, and long-title wrapping. The complete Notes presentation
suite passes 86/86 with the test-only `local_llm_bridge` package root; targeted
analysis, format, and diff checks pass, and the original package-config SHA-256
is restored. Follow-up runtime QA on Android 15/API 35 used a temporary
local-auth release APK: capture 137 records the blank compact editor at
1080×2400, with its existing Back action, title, and content fields visible.
No text was entered and no note was created. A local-auth Web release build
also passed; at 1280×720 dark, the blank editor retained its existing “Saving
unavailable on Web” state. That browser review was not saved as a screenshot,
and neither runtime is a matched Notion pixel pair. The original Cognito APK
was reinstalled and its Login screen restored; its original SHA-256 remains
verified. The full presentation suite passes 203/203 and targeted editor
analysis passes. A full-repository analyzer run reports 42 issues in the
temporary `output/test-shim` and `packages/local_llm_bridge/test` dependency
resolution; it does not pass the Step 11 full-analysis gate. Autosave, editor
state, and all application/backend contracts remain unchanged. Step 6 remains
in progress; no overall score is assigned and the `>=95/100` gate remains
unproven.

Editor breadcrumb de-duplication follow-up — 2026-09-24: the editor breadcrumb
now displays the page title without repeating `NoteFlow`, which is already
visible in the persistent app shell. The page-title breadcrumb, navigation,
actions, autosave and data contracts remain in place. The focused editor surface
suite passes 24/24 with the temporary test-only `local_llm_bridge` package root;
targeted analysis/formatting, Web release build (81.5s) and Android ARM64
release APK build (34.2MB, 69.7s) pass. `.dart_tool/package_config.json` was
restored byte-for-byte to SHA-256
`BB1F5D5C8F88BED214DF461A6D8B4B7F62CAB1F38829E65E05C4FEA9C9D73025`. Capture
137 predates this source change and is not current visual evidence. iOS/macOS
runtime and matched Notion editor comparisons remain open; Step 6 remains in
progress and no numeric score or `>=95/100` result is claimed.

Notes list loading/title follow-up — 2026-09-24: the active workspace app bar now
uses the Notes destination label without repeating the product name already
shown by the shell. The Notes loading screen follows the real list hierarchy
with a static, token-based title/action/row skeleton, while retaining the
existing `notes-workspace-loading` live-region label and keeping placeholder
rows outside the semantics tree. It adds no note data, search/action callback,
or backend behavior. The Notes workspace test passes 20/20, the full
`test/presentation/notes` suite passes 93/93 with the temporary test-only
`local_llm_bridge` package root, scoped presentation analysis reports no issues,
and the edited Dart files pass formatting. Web release builds in 84.2s and
Android ARM64 release APK builds in 53.7s at 34.2MB. The package config was
restored to SHA-256
`BB1F5D5C8F88BED214DF461A6D8B4B7F62CAB1F38829E65E05C4FEA9C9D73025`.
`flutter devices --machine` currently lists Android 15/API 35 x86_64 emulator,
Windows host, Chrome and Edge; the repo has no `windows/` or `linux/` runner,
and this Windows host has no `xcodebuild`, so iOS/macOS runtime/build checks are
unavailable here. Captures 71–76 and 131 predate this follow-up; there is no
current runtime screenshot or matched Notion pair for the updated Notes list.
Step 5 and the overall visual score remain open.

Android current-source autosave/delete follow-up — 2026-09-24: captures
142–151 (listed in [the QA capture inventory](docs/ui-qa/README.md)) were made from checkout `b900fec` on the
Android 15/API 35 x86_64 AVD using the existing local-auth build define. The
workflow created a synthetic note, displayed “Note saved.”, showed the note in
the Notes list, retained it after force-stop/relaunch, reopened it, and deleted
it through the existing More → Delete flow. Home returned to “No notes yet.”
The system keyboard, bottom sheet, and confirmation are visible in captures
144–145 and 149–150. No app data was cleared. The original Cognito APK was
restored byte-for-byte and its installed copy was pulled from the AVD to verify
SHA-256 `5E0480792576BC417B497EF61548FBD2F24B642F1AEAADD5E30BA0D563988339`;
capture 152 shows its Login screen. The previous ARM64 release artifact was
also restored byte-for-byte. This confirms Android workflow behavior only:
same-state Notion pairs, other platform runtime checks, and the rubric score
remain open. The latest phone Home/editor images show substantial empty space;
they do not support claiming `>=95/100`.

Compact editor title remeasurement — 2026-09-24: the live Notion page in the
in-app browser computes its page-title style as 40px font size, 48px line height
and weight 700 at both 390×844 and 567×694; the title wraps at 390px. The
browser viewport was restored to 567×694 after measurement. `NoteDetailEditorForm`
now uses 40dp at compact and wider widths, replacing the previous 36dp compact
value. Capture 153 records the current blank Android editor at 1080×2400
(360dp). `note_detail_surface_test.dart` passes 24/24; the complete
`test/presentation/notes` suite passes 92/92 using the temporary test-only
package root, and `.dart_tool/package_config.json` was restored to SHA-256
`BB1F5D5C8F88BED214DF461A6D8B4B7F62CAB1F38829E65E05C4FEA9C9D73025`.
Targeted analysis and formatting pass. The Android x64 local-auth release build
passes at 35.2MB. The original Cognito APK was restored and verified against
SHA-256 `5E0480792576BC417B497EF61548FBD2F24B642F1AEAADD5E30BA0D563988339`;
the earlier ARM64 release artifact was restored with SHA-256
`349C005D2025F3CEAB09C0C79C48A4FC137A3FF99C664FB6DB2C3E9B1812C8BE`. This
tranche changes only editor presentation and its existing widget expectation;
callbacks, autosave, routes and data flow are unchanged. Other editor states and
same-state Notion pairs remain open, so it does not establish `>=95/100`.

Compact mobile content-alignment follow-up — 2026-09-24: the read-only live Notion
workspace page was measured at 390×844 (DPR 1); its title block starts at x=96,
y=212 with 40px/48px/700 typography and wraps to two lines. At 567×694 the title
starts at x=96, y=156 and uses the same typography. No private page text or
reference screenshot was saved. Current NoteFlow Web capture 154 at 390×844 dark
shows the Home title glyph at x≈99, y≈213; this checks one anchor in the existing
Web storage-limitation state, not an equivalent Home data state. Compact
Dashboard, state, list and editor surfaces now share the x=96 page inset at
390dp. The inset tapers to 16dp at 320dp to preserve narrow-width and large-text
layout. Editor content accounts for the existing shell and page-header bars;
safe-area adjustment stays within presentation layout. Focused Dashboard/editor
tests pass 65/65 and the full presentation suite passes 212/212, including
320–1440dp and up to 2.0x text scale; scoped analysis reports no issues; Web
release and Android x64 local-auth release builds pass.
Current Web blank-editor capture 155 at 390×844 measures the title ink at
x=96/y=157, 55px above the live Notion phone anchor at x=96/y=212. Current
Android blank-editor capture 156 measures x≈96.8/y≈214.9dp at 411×914 logical
pixels; this is close but not an exact viewport pair. The x64 APK was installed
temporarily and the blank editor opened without entering content. The original
Cognito APK and both generated APK outputs were restored byte-for-byte; app data
was not cleared. `.dart_tool/package_config.json` was restored after the
test-only `local_llm_bridge` package-root shim. No backend, application, domain,
infrastructure, auth-controller or route contract changed. The Web editor
anchor, loaded/list/editor states, light theme, Apple runtime, full same-state
pairs and the app-wide score remain open; no `>=95/100` score is assigned.

| Step | Evidence rechecked | Status | Remaining gate |
| --- | --- | --- | --- |
| 0. Baseline | Current checkout and Web load/error states inspected; Android 15/API 35 current-source local-auth QA captures 142–151 verify create, autosave, list, relaunch, reopen and delete; capture 152 verifies the restored Cognito Login screen. Browser persistence and the complete auth/session/error baseline remain unverified. | `PARTIAL` | Record remaining actual behavior on targets that support it, without changing the backend; capture all specified baseline states |
| 1. Reference matrix | Live workspace-page observations retained with their original dates; public Login/Sign up captures 111–114 are same-size 1280×800 and 390×844; old files 24/26 are actually 1280×720; one editor anchor is paired, but workspace surface states still lack complete same-state diffs | `PARTIAL` | Pair shell, Home, list/editor, menus and overlays at supported viewports; keep auth comparison limited to supported controls |
| 2. Tokens/primitives | Theme leaves `fontFamily` unset; Inter/OFL packaging removed. Web manifest contains MaterialIcons/CupertinoIcons only; Android ARM64 release APK contains no Inter asset. Shared sidebar focus outline uses existing light/dark `focusRing` tokens and is verified by keyboard test. Web Register captures 138–139 show platform-default rendering; Android font-to-reference comparison and iOS/macOS runtime remain unverified | `IN_PROGRESS` | Verify actual font rendering on Android/iOS/macOS; recheck light/dark screenshots, text contrast, and all shared components after final styling |
| 3. Shell/sidebar | Release Web captures 115–121 cover Home/Notes selected, expanded 280px sidebar, labeled Settings/Diagnostics footer, collapsed overlay, compact menu/header, 768px rail, and 1024px expanded layout. Captures 133–134 verify the revised compact header and navigation sheet on Android 15/API 35; `workspace_shell_test.dart` passes 19/19, including each moved action's existing callback. Shared row focus tests pass 9/9. | `IN_PROGRESS` | Pair current shell screenshots with Notion references, verify dark/light and long localized labels visually, test Android navigation/back and run Apple device checks; no Favorites/profile/workspace-switching controls |
| 4. Dashboard/Recents | Capture 154 records dark Home at 390×844; current light Chrome captures 167–168 show Home at 390×844 and 567×694. Title glyphs are near x≈99/y≈213 and x≈96/y≈157 against Notion title blocks x=96/y=212 and x=96/y=156. These remain storage-limitation states, not equivalent Home data states. Dashboard tests pass 40/40. Grid, loading, search, selected states, equivalent Home data state and broader same-state pairs remain open. | `PARTIAL` | Capture remaining supported states; pair equivalent Home data states with Notion and score every required anchor |
| 5. Notes list/detail frame | Current Chrome captures 165–166 and Edge captures 169–170 show the storage-unavailable Notes state at 390×844 and 567×694. The title glyph anchors are within 1px of the measured Notion title blocks; New note remains visible and the warning wraps without clipping. `notes_workspace_page_test.dart` passes 44/44, including loading at 320/360/390/768/1280dp, compact/detail/back, create, error/retry and dirty-state cases. Loaded/list/selected/loading pairs and an equivalent Notion list pair remain missing. | `IN_PROGRESS` | Capture loaded/selected/loading states with controlled data and pair them against Notion; verify compact dirty-back and destination retention on native runtime |
| 6. Page editor | Compact title typography is 40dp. Historical Web capture 155 is superseded at the two compact anchors by current Chrome/Edge captures 157–160: title glyph bounds x=104/y=225–256 at 390×844 and x=104/y=169–200 at 567×694, DPR 1. The 567px glyph matches the live Notion observation; the 390px glyph y≈225 is inferred from its measured x=96/y=212 title box and the observed 13px glyph offset. Android capture 156 remains a blank editor at 411×914 logical, not a matched pair. Full presentation suite passes 213/213. | `IN_PROGRESS` | Capture desktop, keyboard, save/error/summary states and exact same-state Notion pairs; complete visual review |
| 7. Menus/overlays/status | More is anchored at ≥600dp and uses a bottom sheet below 600dp. Delete/dirty-back surfaces and callbacks have widget coverage; current-source Android captures 149–150 show the existing More → Delete sheet and “Delete note?” confirmation while removing only the temporary QA note. Full overlay/theme and paired visual states remain unverified. | `PARTIAL` | Capture same-state menu/dialog pairs and verify focus, keyboard, barrier/system-back behavior on supported targets |
| 8. Auth UI | Captures 138–141 are fresh system-font Web Register/Login email states at 390×844 and 1280×800, paired with public Notion refs 111–114. Register CTA bounds align at y=375–414 mobile and y=396–435 desktop after increasing the auth-only minimum to 48dp. Login is within 1px on mobile and 5px above Notion on desktop; its desktop heading/fields begin about 8–10px early. Unsupported provider/legal controls remain absent. The earlier widget-derived y=108–112 heading claim is superseded. Auth suites pass 34/34 and the full presentation suite passes 209/209 after the responsive spacing edit. | `IN_PROGRESS` | Capture Login and Register details plus supported validation/busy/error/success/change-password states; finish accessibility/localization checks and supported-state pairs |
| 9. Accessibility/localization | Login/Register test checks submit reachability at 200% text scale in a 360×800 viewport; Android API 35 capture 127 visually confirms the Login brand and heading remain separated at system font scale 2.0; page background fills six phone/tablet/desktop dimensions for both auth forms; existing semantics and locale tests cover only tested widgets; shared sidebar row Tab focus/blur is verified in light and dark themes | `PARTIAL` | Re-run focus, semantics, EN/VI, 1.0/1.3/2.0 scale, keyboard and touch-target gates across all final UI surfaces |
| 10. Device visual QA | Repo targets are Android/iOS/Web/macOS; there are no Windows/Linux runners. Web Chrome captures 165–168 and Edge captures 169–170 verify Notes warning layout and compact Home/Notes title anchors at 390×844 and 567×694, DPR 1. Earlier captures 157–160 verify blank-editor anchors. Android API 35 emulator is available, but no current-source runtime capture was made; tablet/rotation, other screens, Apple runtime and same-state pairs remain open. | `PARTIAL` | Capture loaded Home/list/menus on available targets; verify tablet/rotation/accessibility; run iOS/macOS checks on an Apple runner |
| 11. Regression/build/handoff | Focused `notes_workspace_page_test.dart` passes 44/44 with the temporary test-only package-root shim and restored package-config hash; scoped analysis and current-source Web release build pass. Current Chrome/Edge Notes/Home evidence is recorded in 165–170. Android x64 debug build did not finish after >4 minutes in the `local_llm_bridge` NDK/llama.cpp hook and was stopped before APK creation or install. Full presentation/repository regression, remaining runtime matrix and Apple checks are open. | `IN_PROGRESS` | Run required regression gates and audit the allowlisted diff before each push; retry Android only through the project's supported test dependency setup |

---

## 8. Rollback protocol

1. Dừng ngay ở step đang fail.
2. Lưu screenshot, test output và `git diff` của step đó.
3. Revert đúng commit của step hiện tại; không revert các step đã được duyệt.
4. Không apply hoặc drop stash cũ nếu không có yêu cầu riêng.
5. Nếu lỗi liên quan save/backend, trả về commit trước step UI đó và kiểm tra lại `canSave`, `onSave`, dirty state và controller call.
6. Chỉ tiếp tục sau khi baseline regression trở lại pass.

---

## 9. Definition of Done

Kế hoạch chỉ được đánh dấu hoàn tất khi tất cả điều kiện sau đúng:

- [ ] UI NoteFlow đạt `>= 95/100` ở mọi viewport bắt buộc; mục tiêu tốt nhất là 98–100.
- [ ] Sidebar, page header, list/detail, editor, action menu, overlays, auth và dark/light cùng một design system.
- [ ] Save note, create, edit, delete, summarize, search, auth và routing giữ đúng behavior trên từng target mà baseline hỗ trợ; Web giữ nguyên limitation persistence và hiển thị trạng thái không lưu được.
- [ ] Không có thay đổi trong domain/application/infrastructure/backend/persistence/auth controller.
- [ ] Không có critical fail, overflow, mất focus, mất dirty state hoặc CTA bị che.
- [ ] `dart format`, `flutter analyze`, presentation/auth tests và build target phù hợp đã chạy; output được ghi lại.
- [ ] Diff cuối cùng đã được review theo allowlist và từng step có thể rollback độc lập.

---

## 10. Historical per-platform scorecard — 2026-09-24

`0/100 (lower-bound)` is a numeric evidence floor used when required evidence is
incomplete; it is not a measured zero visual-similarity result and does not
imply a pass. The anchor results below are tranche results only.

| Platform/runtime | Evidence available to date | Current status | Remaining evidence before numeric scoring |
| --- | --- | --- | --- |
| Android | Existing API 35 phone workflow captures 142–153; blank editor at 411×914 logical in 156 | `0/100 (lower-bound)` | Exact matched reference states; tablet portrait/landscape; other screens, themes, accessibility and full workflow matrix |
| iOS | No Apple runtime available on this host | `0/100 (lower-bound) (UNVERIFIED)` | iPhone and iPad required viewport, workflow and visual captures |
| Web — Chrome | Editor anchor 157–158; Login email CTA 161–162; compact Notes/Home anchors and Web warning layout 165–168 | `0/100 (lower-bound)` | All other screens/states; matched Notion pairs; keyboard, loaded/error/summary, theme, locale and accessibility checks |
| Web — Edge | Editor anchor 159–160; Login email CTA 163–164; compact Notes warning state 169–170 | `0/100 (lower-bound)` | Same remaining Web matrix as Chrome; platform Web score is the lower browser score |
| macOS | No Apple runtime available on this host | `0/100 (lower-bound) (UNVERIFIED)` | Desktop workflow and visual captures on macOS |
| **Overall** | Required platform and workflow cells are incomplete | **`0/100 (lower-bound)` — 95% is not established** | Complete all applicable platform cells, then score using §6; keep unsupported capabilities `N/A` only when NoteFlow has no corresponding contract/callback |

Unsupported Notion-only controls are excluded from the visual-fidelity
denominator only where the existing NoteFlow contract does not support that
capability. After M-01 verifies the contract absence, record 100/100 on the
separate scope-compliance row. Supported but uncaptured states stay
`UNVERIFIED` and receive a 0/100 lower-bound until measured.

This tranche's Login email-first anchor result is `PASS`: the desktop Continue
bounds match live Notion at 1280×800 in Chrome and Edge; the 390×844 bounds are
1px lower in both. It is an anchor check, not a whole-screen score. Under the
current numeric lower-bound rule, the incomplete historical platform matrix is
0/100 until the remaining cells are verified. Login/Register are outside the
current visual scope. Android, iOS, macOS, remaining Web states and the full
workflow matrix were incomplete in this historical tranche.

## Historical compact-Web scorecard and evidence ledger — 2026-09-24

The overall historical lower-bound is 0/100. The measured Web anchors below
cover a small subset of the required matrix; they do not show that any platform
has reached 95/100.

| Platform/runtime | Current score | Evidence in this tranche | Missing evidence |
| --- | --- | --- | --- |
| Android | `0/100 (lower-bound)` | Historical API 35 workflow captures 142–153 are from checkout `b900fec`; capture 156 is one current-source editor anchor at 411×914 logical. No Android device/AVD was available in the 2026-09-24 platform audit (`adb devices` empty). | Final-source phone/tablet captures at required viewports, same-state Notion references, themes, keyboard/back, accessibility and the rest of the workflow matrix |
| iOS | `0/100 (lower-bound) (UNVERIFIED)` | No Apple runner on this Windows host | iPhone and iPad build/runtime captures for all applicable states |
| Web — Chrome | `0/100 (lower-bound)` | Captures 165–168: compact Notes/Home title anchors and existing storage-unavailable presentation at 390×844 and 567×694 | Loaded/list/editor/workflow pairs, other viewports, dark theme, locale, keyboard and accessibility cells |
| Web — Edge | `0/100 (lower-bound)` | Captures 169–170: compact Notes storage-unavailable state at 390×844 and 567×694 | Same remaining Web matrix; Web score is the lower of Chrome and Edge after all cells are scored |
| macOS | `0/100 (lower-bound) (UNVERIFIED)` | No Apple runner on this Windows host | macOS build/runtime captures for all applicable desktop states |
| **Overall** | **`0/100 (lower-bound)` — 95/100 is not established** | Required platform/browser × viewport × screen/state denominator remains incomplete | Complete every applicable cell, score with §6, and preserve behavior as a separate critical gate |

### Evidence ledger — compact Web tranche only

| platform/browser | viewport | screen/state | group/item/anchor | reference | current | measurement | status | reason |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Chrome | 390×844 | Home, Web storage unavailable | Page-title painted anchor | Live Notion title anchor x=96/y=212 | `docs/ui-qa/167-noteflow-home-storage-unavailable-390x844-light-chrome-current.png` | x≈99/y≈213; Δ≈(+3,+1)px | `PASS` — anchor only | Within the §6 ±4px positional tolerance; this is not a same-state Home comparison |
| Chrome | 567×694 | Home, Web storage unavailable | Page-title painted anchor | Live Notion title anchor x=96/y=156 | `docs/ui-qa/168-noteflow-home-storage-unavailable-567x694-light-chrome-current.png` | x≈96/y≈157; Δ≈(0,+1)px | `PASS` — anchor only | Within tolerance; storage-limitation Home state has no equivalent data-state pair |
| Chrome | 390×844 | Notes, Web storage unavailable | Warning card and New note CTA | No same-state Notion persistence-error reference | `docs/ui-qa/165-noteflow-notes-storage-unavailable-390x844-light-chrome-current.png` | Warning wraps to 3 lines; CTA visible; no clipping | `UNVERIFIED` | Layout is visible, but this backend limitation has no matched Notion error-state reference |
| Chrome | 567×694 | Notes, Web storage unavailable | Warning card and New note CTA | No same-state Notion persistence-error reference | `docs/ui-qa/166-noteflow-notes-storage-unavailable-567x694-light-chrome-current.png` | Warning wraps to 2 lines; CTA visible; no clipping | `UNVERIFIED` | Layout is visible, but this backend limitation has no matched Notion error-state reference |
| Edge | 390×844 | Notes, Web storage unavailable | Page-title anchor, warning card and CTA | Live Notion title anchor x=96/y=212; no equivalent persistence-error state | `docs/ui-qa/169-noteflow-notes-storage-unavailable-390x844-light-edge-current.png` | Title glyph near x=96/y=213; warning 278.4×74px / 3 lines; New note visible | `PASS` for title anchor; `UNVERIFIED` for card | Title anchor is within tolerance; no matched Notion error-state reference for the card |
| Edge | 567×694 | Notes, Web storage unavailable | Page-title anchor, warning card and CTA | Live Notion title anchor x=96/y=156; no equivalent persistence-error state | `docs/ui-qa/170-noteflow-notes-storage-unavailable-567x694-light-edge-current.png` | Title glyph near x=96/y=157; warning 360×58px / 2 lines; New note visible | `PASS` for title anchor; `UNVERIFIED` for card | Title anchor is within tolerance; no matched Notion error-state reference for the card |
| Android | Required phone/tablet cells in Step 5/10 | Workflow screens | All applicable visual groups | Same-state Notion captures required | Selected earlier workflow captures 142–153 only | No complete matched-cell measurements | `UNVERIFIED` | Workflow behavior evidence does not score visual fidelity; latest debug build did not produce an APK |
| iOS | iPhone/iPad cells in Step 5/10 | Applicable workflows | All applicable visual groups | Same-state Notion captures required | No native runtime | No measurements | `UNVERIFIED` | No Apple runtime is available on this host |
| macOS | 1440×900 and required desktop states | Applicable workflows | All applicable visual groups | Same-state Notion captures required | No native runtime | No measurements | `UNVERIFIED` | No Apple runtime is available on this host |

All other supported browser/platform × viewport × screen/state cells remain
`UNVERIFIED` until their reference/current evidence is recorded. Only controls
mapped `OUT_OF_SCOPE` in the NoteFlow contract tables above may be `N/A`.

### Registration password-guidance tranche — 2026-09-24

This tranche ports the live missing-requirement feedback from `TanMinh2` into
the existing two-step Register form. The displayed rules match the password
policy already present in `lib/amplify_outputs.dart`. Changes are limited to
`lib/presentation/auth/auth_pages.dart`,
`lib/presentation/auth/auth_localizations.dart`, and the directly related auth
page tests. Domain, application, infrastructure, Cognito configuration,
auth-controller, API, and persistence files were not changed.

| Target | Verified evidence from this tranche | Visual score |
| --- | --- | --- |
| Android | Shared Flutter auth-page tests pass; no new Android runtime capture | `0/100 (lower-bound)` |
| iOS | Shared Flutter auth-page tests pass; no Apple runtime capture | `0/100 (lower-bound) (UNVERIFIED)` |
| Web — Chrome | Shared Flutter auth-page tests pass; no browser capture of the password checklist | `0/100 (lower-bound)` |
| Web — Edge | Shared Flutter auth-page tests pass; no browser capture of the password checklist | `0/100 (lower-bound)` |
| macOS | Shared Flutter auth-page tests pass; no Apple runtime capture | `0/100 (lower-bound) (UNVERIFIED)` |
| **Overall** | Behavior/localization verified by widget tests; this is not a visual reference comparison | **`0/100 (lower-bound)` — 95/100 remains unestablished** |

The focused `flutter test` run needed a temporary `.dart_tool` package-root
shim because the existing `local_llm_bridge` native hook failed with
`LNK1136: invalid or corrupt file` for `llama-vocab.obj`. The shim and temporary
package-config edit were restored after the passing 16/16 run. Scoped Dart
analysis reported no issues.

### Notes error announcement accessibility tranche — 2026-09-24

The expanded and compact Notes load-error states had an explicit live-region
label as well as a child Text semantics label. A semantics-tree regression test
reproduced the warning twice in one accessible label. The presentation now
excludes only the duplicate Text semantics while retaining the live-region
announcement and the Retry action. No data, callback, route, persistence,
application, domain, infrastructure, or backend behavior changed.

The new semantics check covers 1024×700 and 390×844. The complete
`notes_workspace_page_test.dart` and `workspace_shell_test.dart` run passed via
the existing temporary test-only package shim; `.dart_tool/package_config.json`
was restored to SHA-256 `BB1F5D5C8F88BED214DF461A6D8B4B7F62CAB1F38829E65E05C4FEA9C9D73025`.
Scoped `dart analyze` on the changed UI/test files and `git diff --check` passed.
This is an accessibility regression repair, not a matched visual comparison;
it does not add points to the visual score.

## Authoritative platform scorecard and evidence ledger — 2026-09-24

This final section supersedes earlier scorecard snapshots in this plan.
`0/100 (lower-bound)` is the numeric floor while the required denominator has
supported but unverified cells; it is not measured similarity and does not
mean the rendered UI itself scored zero. No platform or overall score can
currently be stated as `>=95/100`.

| Platform/runtime | Current score | Confirmed evidence from the audit | Missing evidence before numeric scoring |
| --- | --- | --- | --- |
| Android | `0/100 (lower-bound)` | AVD `NoteFlow_API35` is booted as `emulator-5554` (Android 15/API 35). The current working-tree release APK (87.7 MB) built successfully, installed with `adb install -r`, and launched. Capture 171 records Login/email-first at 411×914 logical (1080×2400 px, 420 dpi); it does not verify the authenticated editor lifecycle. Captures 142–153 are older workflow evidence, and capture 156 is a single 411×914 editor anchor. | Matched Notion reference pairs and current runtime captures for every required phone/tablet workflow/state/theme/locale; editor autosave and notes round-trip; keyboard/back, text scale and accessibility; complete the 412×915 pilot in Step 5 |
| iOS | `0/100 (lower-bound) (UNVERIFIED)` | No Apple runtime or `xcodebuild` on this Windows host. iPhone landscape is supported by the runner and is now an explicit required cell in §4.4. | iPhone portrait/landscape and iPad portrait/landscape captures for supported workflows, safe areas, keyboard, accessibility and matched references |
| Web — Chrome | `0/100 (lower-bound)` | The current working-tree Web release build succeeded and rendered the email-first Login screen in an IAB/Playwright-managed Chromium runner at 567×694; capture `output/playwright/20260924-current-web-tranche/172-noteflow-login-email-567x694-web-chromium-current-20260924.png`. This is Chromium smoke evidence, not proof of the required installed Chrome cell or a matched Notion pair. Older captures 157–158, 161–162 and 165–168 remain limited anchors/states. | Installed Chrome current-source runtime at 1280×800, 1440×900, 390×844 and 567×694; loaded supported note states, all auth/workflow states, same-state pairs, theme, locale, keyboard and accessibility |
| Web — Edge | `0/100 (lower-bound)` | Captures 159–164 and 169–170 cover only editor/Login anchors and compact storage-unavailable Notes states. Served bundle predates current HEAD; no fresh Edge browser runtime was available through CUA. | Same current-source, viewport and workflow matrix as Chrome; Web score is the lower of the two browser scores |
| macOS | `0/100 (lower-bound) (UNVERIFIED)` | No Mac runtime, `xcodebuild`, or macOS capture on this host. | Current build and matched captures at 1440×900 for supported desktop workflows, title bar/menu, hover/focus, keyboard, themes and locale |
| **Overall** | **`0/100 (lower-bound)` — 95/100 is not established** | Every platform has at least one supported state without a current matched visual measurement; Apple runtimes are absent. | Complete and score every applicable cell using §6; keep supported-but-unverified items in the denominator and use `N/A` only for capabilities absent from NoteFlow contracts |

### Latest narrow visual evidence — Login Continue button

The following rows score only the Continue-button anchor, not the Login screen or
platform. Login states, password checklist, error/busy/verification states and
all other supported controls remain unverified until current-source pairs are
captured.

| platform/browser | viewport | screen/state | group/item/anchor | reference | current | measurement | status | reason |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Chrome | 1280×800 | Login, email-first | Continue button bounds | `docs/ui-qa/111-notion-login-1280x800-reference-live-20260924.png` — x=460–819, y=338–377 | `docs/ui-qa/161-noteflow-login-email-anchor-1280x800-chrome-current-20260924.png` | Δ≈(0,+1)px | `PASS` — anchor only | Within ±4px position tolerance; not a whole-screen score |
| Chrome | 390×844 | Login, email-first | Continue button bounds | `docs/ui-qa/114-notion-login-390x844-reference-live-20260924.png` — x=20–369, y=308–347 | `docs/ui-qa/162-noteflow-login-email-anchor-390x844-chrome-current-20260924.png` | Δ≈(0,+1)px | `PASS` — anchor only | Within ±4px position tolerance; not a whole-screen score |
| Edge | 1280×800 | Login, email-first | Continue button bounds | `docs/ui-qa/111-notion-login-1280x800-reference-live-20260924.png` — x=460–819, y=338–377 | `docs/ui-qa/163-noteflow-login-email-anchor-1280x800-edge-current-20260924.png` | Δ≈(0,+1)px | `PASS` — anchor only | Within ±4px position tolerance; not a whole-screen score |
| Edge | 390×844 | Login, email-first | Continue button bounds | `docs/ui-qa/114-notion-login-390x844-reference-live-20260924.png` — x=20–369, y=308–347 | `docs/ui-qa/164-noteflow-login-email-anchor-390x844-edge-current-20260924.png` | Δ≈(0,+1)px | `PASS` — anchor only | Within ±4px position tolerance; not a whole-screen score |

### Compact editor autosave-status tranche — 2026-09-24

The compact page header now reflects the existing editor lifecycle: an unsaved
draft uses an edit icon, pending changes use an upload icon, an active save uses
the existing progress indicator, save failure uses the error color/icon, and a
saved note uses the cloud-done icon. The Web storage-unavailable state keeps its
existing unavailable icon. Labels, autosave scheduling, callbacks, persistence,
and all non-presentation layers remain unchanged.

The regression test exercises these states at 390×844. The complete focused
`note_detail_surface_test.dart` suite passed 27/27 via the existing temporary
test-only package shim; scoped `dart analyze` and `git diff --check` passed.
Android API 35 is available and booted. The current working-tree release APK
built, installed with `adb install -r`, and launched. Capture
`docs/ui-qa/171-noteflow-login-email-411x914-android-current-20260924.png`
records the initial Login screen at 411×914 logical; the authenticated editor
was not reached, so this capture is not evidence that autosave status works at
runtime. The Web release build also succeeded and rendered the Login screen in
an IAB/Playwright-managed Chromium runner at 567×694; the capture is
`output/playwright/20260924-current-web-tranche/172-noteflow-login-email-567x694-web-chromium-current-20260924.png`.
The accessibility tree exposed the email field, Continue, and Create account.
This is a Web smoke check, not an installed Chrome/Edge score or a matched
Notion comparison. The Playwright-managed Chromium console reported zero
errors and zero warnings during this render.

| Android | 411×914 logical (1080×2400 px, 420 dpi) | Login/email-first initial state | Full screen and input anchors | No matched reference | `docs/ui-qa/171-noteflow-login-email-411x914-android-current-20260924.png` | Not measured | `UNVERIFIED` | Current runtime capture only; no paired reference or editor state |
| Web/Chromium runner | 567×694 CSS px | Login/email-first initial state, light theme | Full screen and input/control anchors | No matched reference | `output/playwright/20260924-current-web-tranche/172-noteflow-login-email-567x694-web-chromium-current-20260924.png` | Not measured | `UNVERIFIED` | Successful Web build and render; runner does not establish installed Chrome/Edge cells or visual parity |

| Target | Score after this iteration | Self-score evidence |
| --- | --- | --- |
| Android | `0/100 (lower-bound)` | Lifecycle states are regression-tested and the current APK Login screen was captured; authenticated editor runtime and matched Notion pairs remain outstanding. |
| Web — Chrome | `0/100 (lower-bound)` | Current Web build and Chromium-runner Login smoke capture verified; installed Chrome capture, matched reference, and required workflow/state cells remain outstanding. |
| Web — Edge | `0/100 (lower-bound)` | No current-source Edge capture or complete matched cell matrix in this iteration. |
| **Overall** | **`0/100 (lower-bound)`** | This presentation correction fixes a false-saved visual state; it does not establish a full-screen or platform visual score. |

## Login/Register secondary-link layout tranche — 2026-09-25

The compact Login `Create account` link stays near the Notion Login sign-up
anchor. Register's `Log in` link now uses the higher Sign up anchor on its email
step. The longer Register details form returns the link to natural scroll flow,
so it cannot cover or clip `Create account`. With a keyboard or a short viewport,
both pages continue using the existing scroll fallback. Existing navigation
callbacks, validators, controller calls, routes, and backend behavior are
unchanged.

Current-source Web release build passed in 115.1s. Installed Chrome and Edge
rendered the 390×844 Login and Register email states; capture files are
`docs/ui-qa/187-noteflow-login-email-390x844-{chrome,edge}-current-20260925.png`
and `docs/ui-qa/188-noteflow-register-email-390x844-{chrome,edge}-current-20260925.png`.
The Edge Register details capture `docs/ui-qa/190-noteflow-register-details-390x844-edge-current-20260925.png`
shows the complete Create account CTA with the login link below it. Both browser
console checks reported zero errors and zero warnings. The dummy email used to
advance to Register details was not submitted.

The current-source Android release APK built successfully (87.7 MB), installed
on `NoteFlow_API35` / Android 15, and restored the existing signed-in Home
session. No final-source Android auth screen was captured in this tranche.
`auth_pages_test.dart` passed 19/19 using the existing temporary test-only
package shim; `dart analyze` reported no issues. The exact original
`.dart_tool/package_config.json` was restored (SHA-256
`BB1F5D5C8F88BED214DF461A6D8B4B7F62CAB1F38829E65E05C4FEA9C9D73025`).

The Login footer is visually near the live Notion Login reference at
`docs/ui-qa/114-notion-login-390x844-reference-live-20260924.png`; the Register
email footer is visually near the live Notion Sign up reference at
`docs/ui-qa/113-notion-signup-390x844-reference-live-20260924.png`. These are
secondary-link anchor checks only; the Register details state has no matched
Notion password-form capture and is not assigned a numeric screen score.

| Target | Score after this iteration | Self-score evidence |
| --- | --- | --- |
| Android | `0/100 (lower-bound)` | Current APK build/install passed, but no final-source Android auth capture or complete auth/platform matrix was scored. |
| Web — Chrome | `0/100 (lower-bound)` | Current Login/Register email captures and browser console are verified; the full auth states, remaining viewports, and all inner-page cells remain incomplete. |
| Web — Edge | `0/100 (lower-bound)` | Current Login/Register email and Register details captures show the CTA remains usable; the full auth and inner-page matrix remains incomplete. |
| **Overall** | **`0/100 (lower-bound)` — 95/100 is not established** | This tranche adjusts secondary-link placement and prevents CTA overlap; it is not a whole-platform score. |

## Compact Android Notes-header CTA tranche — 2026-09-25

On compact layouts, the Notes header now keeps its title and create action on
one row by using a plus icon with the existing localized `New note` tooltip.
The `new-note` key, busy-state handling, and `onNewNote` callback are unchanged;
wide layouts keep the labeled button. This is a presentation-only adjustment.
No application, domain, infrastructure, route, persistence, API, or backend
code changed.

The focused `notes_workspace_page_test.dart` suite passed 27/27 with the
existing test-only package shim. Scoped `dart analyze` reported no issues and
`git diff --check` passed. The original `.dart_tool/package_config.json` was
restored and its SHA-256 verified as
`BB1F5D5C8F88BED214DF461A6D8B4B7F62CAB1F38829E65E05C4FEA9C9D73025`.

The Android release APK built successfully (87.7 MB), installed, and launched
on `NoteFlow_API35` / Android 15 at 411×914 logical (1080×2400 px, 420 dpi).
The current Notes capture is
`docs/ui-qa/192-noteflow-notes-list-411x914-android-current-20260925.png`.
On-device accessibility bounds confirm the Notes title and `New note` action
share the same row, and the saved note row remains visible. This verifies one
current Android state and the CTA affordance; it is not a matched Notion
comparison or a full workflow score.

The Web release build also succeeded (137.9s). The current local preview loaded
the Login screen after rebuild. The authenticated Notes screen was not reached
in this browser pass, so this is only a Web build/smoke result.

| Target | Score after this iteration | Self-score evidence |
| --- | --- | --- |
| Android | `0/100 (lower-bound)` | One 411×914 Notes-list runtime state and the compact header regression test pass; required matched Notion states, other viewports and workflow cells remain incomplete. |
| Web — Chrome | `0/100 (lower-bound)` | Current Web release built and loaded Login; no authenticated inner-page comparison was captured. |
| Web — Edge | `0/100 (lower-bound)` | No Edge runtime capture in this iteration. |
| **Overall** | **`0/100 (lower-bound)` — 95/100 is not established** | This tranche verifies a single compact Notes-header fix; the §6 platform/browser × viewport × state denominator remains incomplete. |

## Browser-local Web-note QA tranche — 2026-09-25

This tranche runs on `Test_Tuankiet`, based on `76385c4`. The user explicitly
approved browser-only note storage to make Web UI checks possible. A versioned
JSON envelope is stored under `note_ai_app.notes.v1` in `localStorage` for the
current origin and browser profile. It does not upload or synchronize notes.
The Web adapter and its factory wiring are QA-only changes in
`lib/infrastructure/notes`; this tranche did not change the domain model,
application/controller or route logic, auth service/controller/session, or
backend/API. Existing presentation-only auth edits are separate earlier
tranches in this working tree. Do not transfer the adapter, dependency, or
platform factory edits to `TuanKiet2`.

The existing three-second autosave and focus-loss behavior use the existing
controller and repository calls. The action-bar manual Save remains disabled
(`canSave: false`, `onSave: null`). Editor status copy now reflects that this
test branch can autosave in Web instead of claiming that all Web storage is
unavailable.

Verification on the current Web release build:

- `flutter build web --release` passed in 68.5 seconds. The English registration
  subtitle was verified in the rebuilt preview at 375×667; the Vietnamese
  translation now carries the same browser-local meaning.
- Scoped `dart analyze` over the Web adapter, repository factory, note editor,
  localizations, and Web persistence tests reported no issues. `git diff
  --check` passed.
- `.dart_tool/package_config.json` retained SHA-256
  `BB1F5D5C8F88BED214DF461A6D8B4B7F62CAB1F38829E65E05C4FEA9C9D73025`.
- In authenticated Chrome QA, created a note with Vietnamese, Japanese,
  emoji, and multiline content; waited for autosave; reloaded; reopened and
  edited it; reloaded again; then deleted it. The note survived each reload,
  and deletion left zero records in localStorage. During autosave, captured
  requests were limited to static font downloads; no app/backend request was
  made for the save.
- Current-source screenshots are in
  `output/playwright/20260925-browser-local-note/`. The final rebuild was
  checked at 390×844 and 1440×900. Responsive note/home checks also covered
  360×752, 412×891, 567×694, 768×1024, and 1024×768, with reload after each
  viewport change. No browser-layout overflow was observed. Browser emulation
  does not verify a native Android system navigation bar or iOS safe area.
- Chrome browser-local persistence is functionally verified, but this tranche
  does not pair every state with a same-state Notion reference and does not
  cover Edge or native release runtimes. It does not establish the `>=95/100`
  visual gate. The earlier Chrome-Web test-runner attempt remains blocked by
  the existing `llama-vocab.obj` `LNK1136` hook failure / stalled shim; the
  real-browser workflow above is the runtime evidence for this tranche.
- ADB had no attached device. `flutter build apk --release --no-pub` did not
  complete within four minutes while the `local_llm_bridge` hook runner was
  still live; it was interrupted without treating the existing APK as a new
  build result. No Android runtime score is assigned.

| Platform/runtime | Score after this tranche | Evidence and remaining work |
| --- | --- | --- |
| Android | `0/100 (lower-bound)` | APK build did not complete while the native hook runner remained live; ADB had no attached device, so current-branch reinstall/workflow and native bottom-navigation safe area are unverified. |
| iOS | `0/100 (lower-bound) (UNVERIFIED)` | No iOS simulator or macOS runner on this Windows host. |
| Web — Chrome | `0/100 (lower-bound)` | Current-source autosave/reload/edit/delete works at phone, compact, tablet, and desktop widths. Same-state Notion pairs and the full required screen/state denominator remain incomplete. |
| Web — Edge | `0/100 (lower-bound)` | No current-source Edge persistence or responsive workflow run in this tranche. |
| macOS | `0/100 (lower-bound) (UNVERIFIED)` | No macOS runner on this Windows host. |
| **Overall** | **`0/100 (lower-bound)` — 95/100 is not established** | This tranche verifies browser-local persistence and selected responsive states, not the complete platform × viewport × state visual matrix. |

## Notion page-surface refinement — 2026-09-25

This presentation-only pass makes two existing UI areas closer to Notion's
document-first layout. Recent cards now use the existing note body as a short
four-line preview instead of leaving the preview panel blank; empty notes keep
the document icon. Notes with no AI summary no longer show a placeholder line
between the title and body. The existing Summarize action and summary rendering
remain available. This pass changed only dashboard and note presentation files;
it did not alter application/domain logic, infrastructure, persistence, routes,
or backend/API behavior.

Verification on the current `Test_Tuankiet` Web build:

- `flutter build web --release --no-pub` passed in 84.2 seconds.
- Scoped `dart analyze` passed for the four changed Dart presentation files.
- Direct `flutter test` startup hit the existing `local_llm_bridge` native
  asset hook failure while linking `llama-vocab.obj` (`LNK1136`, invalid or
  corrupt file). Re-running through the existing test-only package-root shim
  passed `dashboard_page_test.dart` 41/41 and `note_detail_surface_test.dart`
  28/28. The shim restored `.dart_tool/package_config.json` to SHA-256
  `BB1F5D5C8F88BED214DF461A6D8B4B7F62CAB1F38829E65E05C4FEA9C9D73025`.
- In authenticated Chrome QA, the previously saved browser-local note remained
  present after reload. The editor still showed `Note saved.`, rendered the
  title/body directly, and omitted the empty-summary placeholder.
- Home was checked at 360×800, 390×844, 412×891, 768×1024, 1024×768, and
  1440×900; the editor was checked at 390×844 and 1440×900. Each viewport
  change was followed immediately by reload. The browser reported no
  horizontal overflow at the checked sizes. 412×891 is a reduced-height
  browser viewport used to approximate a phone with bottom system UI; it does
  not verify a native Android navigation bar or iOS safe area.
- Captures from this pass are in
  `output/playwright/20260925-notion-polish/`. The live Notion page reference
  used for desktop comparison is
  `output/playwright/notion-reference-1280x800-current.png`.

These samples do not cover every Notion-matched state or native platform, so
they do not establish a 95/100 visual score. Keep the prior browser-local Web
adapter and its test-only dependency changes confined to `Test_Tuankiet`.

| Platform/runtime | Score after this pass | Evidence and remaining work |
| --- | --- | --- |
| Android | `0/100 (lower-bound)` | Responsive browser checks only; no current native Android install/run or full matched-state matrix. |
| iOS | `0/100 (lower-bound) (UNVERIFIED)` | No iOS simulator/runtime on this host. |
| Web — Chrome | `0/100 (lower-bound)` | Current Home and Editor screenshots at compact and desktop sizes; other tested widths covered Home. A full state-by-state Notion comparison is incomplete. |
| Web — Edge | `0/100 (lower-bound)` | No current-source Edge run after this pass. |
| macOS | `0/100 (lower-bound) (UNVERIFIED)` | No macOS runner on this host. |
| **Overall** | **`0/100 (lower-bound)` — 95/100 is not established** | Current screenshots verify two refinements and selected responsive behavior, not the complete platform × viewport × state visual matrix. |

## Web browser-local Back/Save verification — 2026-09-25

The Web test branch keeps notes in this browser origin's `localStorage`; it does
not synchronize note data through the backend. In the existing authenticated
Chrome session at 360×800, reopened the QA note, changed its title, and pressed
Back. The app returned to the notes list with the changed title. After a full
page reload, the note remained visible and the browser-local store still
contained the changed title (`note_ai_app.notes.v1`, 320 characters). This
runtime flow saved as the editor lost focus; it did not display the dirty-back
confirmation dialog. The separate widget test for the Back → Save decision
passed.

Verification:

- `flutter build web --release --no-pub` passed after the Back behavior change
  (129.2 seconds).
- `dart analyze lib/presentation/notes/note_detail_page.dart` reported no
  issues; `git diff --check` passed.
- Scoped `note_detail_page_test.dart` passed 14/14, including “dirty back Save
  persists before leaving.” The Web adapter test was invoked on the default VM
  runner and skipped because it requires `flutter test --platform chrome`; the
  skip is not counted as a passing adapter test.
- A direct `flutter test --platform chrome
  test/infrastructure/notes/database_context_web_test.dart` attempt on
  2026-09-25 stopped before the tests started: the `local_llm_bridge` native
  asset hook failed linking generated `llama-vocab.obj` (`LNK1136: invalid or
  corrupt file`). This does not count as a Web adapter test result. The
  `.dart_tool/package_config.json` SHA-256 remained unchanged.
- Chrome reported zero console errors and zero warnings after reload. The
  password-input count was zero. Captures are in
  `output/playwright/20260925-browser-local-note-back-save/`.
- This confirms browser-local save/reload at one Chrome phone viewport. It
  does not establish the Notion visual score or native Android/iOS behavior;
  the platform scores remain `0/100 (lower-bound)` until the required matrix is complete.

## Compact auth system-inset follow-up — 2026-09-25

Compact auth headings now use a consistent 24dp size. The auth footer stays
anchored on tall compact screens without a system inset; with a bottom system
inset or reduced available height it returns to the scroll flow, keeping the
Continue action clear and tappable. This is a presentation-only change.

Verification:

- The auth widget suite passed 22/22 with the existing test-only
  `local_llm_bridge` package-root shim. The 360×800 test with a 48dp bottom
  inset tapped Continue and reached the registration details step without a
  hit-test warning. The compact signup-anchor test keeps a 56dp minimum gap in
  its widget-test theme; the live Web capture has more separation.
- `dart analyze lib/presentation/auth/auth_pages.dart
  test/presentation/auth/auth_pages_test.dart` passed.
- `flutter build web --release --no-pub` passed in 92.6 seconds.
- Current-source Register was checked in `@Browser` at 360×752, 390×844, and
  1280×800. Each viewport change was followed immediately by reload. The
  reduced-height view kept Continue visible and the footer below it; mobile
  and desktop panels remained unclipped.
- The test shim restored `.dart_tool/package_config.json` to SHA-256
  `BB1F5D5C8F88BED214DF461A6D8B4B7F62CAB1F38829E65E05C4FEA9C9D73025`.
- This iteration changed presentation and test files only; it did not change
  domain/application, infrastructure, backend, or API code. The browser-local
  notes adapter remains confined to `Test_Tuankiet`.

The Web sign-in request in `@Browser` remained busy after 15 seconds, so this
session could not repeat the authenticated note workflow. The previously
recorded browser-local Back/reload verification remains the persistence
evidence for this branch. No platform score is assigned here; the full
platform × viewport × state visual gate remains open and `>=95/100` is not
established.

## Web note workflow and responsive smoke test — 2026-09-25

- In the local-auth Web build, the browser-only QA note remained visible after
  a full page reload. Its title was edited through three versions, including
  leaving the editor before the autosave delay; the note list reflected the
  latest title. The note body retained Vietnamese, Japanese, and emoji text.
- Checked Home at 360×800, 390×844, 412×915, 768×1024, 1024×768, 1280×800,
  and 1440×900. Each explicit viewport change was followed immediately by a
  reload. No horizontal clipping was visible in these screenshots. The
  navigation stays compact through phone widths, is icon-only at 768px, and
  expands to the full sidebar at 1024px and wider.
- Opened the note editor at 412×915 and 1440×900. The title wraps on mobile
  and the body remains readable; neither view visibly clips. The title and
  body inputs have no visible box, so editor styling still needs a closer
  Notion comparison and this does not establish the requested visual score.
- Search matched the saved note, an unmatched partial query showed “No
  matching notes,” Clear search restored the note, and the Grid control was
  exercised. The connected browser reported no console errors or warnings.
- Only Codex In-app Browser was exposed in the computer-use browser inventory
  during this pass. No current Edge-specific run or matched-state capture set
  was produced. The screenshots from this pass were inspected live and were
  not saved as new image files.

## Browser-local note edge cases and responsive follow-up — 2026-09-25

The user confirmed that notes should be stored only in the browser. This branch
keeps local note data in this browser origin and does not synchronize it through
the backend.

- Reloaded immediately after setting each viewport. In the Codex In-app Browser,
  the saved QA note remained available at 375×667, 393×852, 567×694,
  852×393 (landscape), and 1366×1024; earlier current-build checks cover
  411×890 and 1440×900. The browser viewport override was reset and immediately
  reloaded at the end of the pass.
- The long title wraps over multiple lines in the mobile editor; the body remains
  visible, and the landscape editor showed `Note saved.` No horizontal clipping
  was visible in the stable screenshots. At 567×694 and 852×393 the first
  screenshot during reload caught an incomplete Flutter paint; a subsequent
  screenshot showed the complete app, so only the stable view was assessed.
- The title now stays borderless while idle and shows a subtle focus ring while
  focused. Its widget test passed as part of the focused note surface suite
  (29/29); targeted Dart analysis reported no issues, and the release Web build
  passed. `git diff --check` passed.
- Long mixed-script title/body persistence, empty title/body, search match and
  no-match, clearing search, grid control, and canceling the delete dialog were
  also exercised in the browser. The sample note remained after reload.
- A Chrome-platform test of
  `test/infrastructure/notes/database_context_web_test.dart` launched headless
  Chrome but produced no test result after more than ten minutes. It was
  interrupted and is **not** counted as a pass. The temporary package config was
  restored from the saved baseline; its SHA-256 is
  `BB1F5D5C8F88BED214DF461A6D8B4B7F62CAB1F38829E65E05C4FEA9C9D73025`.
- These viewport checks ran in Codex In-app Browser, not independent Chrome or
  Edge sessions. They do not cover native Android system bars, iOS, macOS, or
  every Notion-matched state, so they do not establish `>=95/100`.

## Current platform scorecard — 2026-09-25

| Platform/runtime | Score | Evidence and remaining work |
| --- | --- | --- |
| Android | `0/100 (lower-bound)` | Browser viewport checks include phone and landscape sizes, but current-branch native runtime, Android navigation-bar rendering, and the full visual matrix remain unverified. |
| iOS | `0/100 (lower-bound) (UNVERIFIED)` | No iOS simulator/runtime on this Windows host. |
| Web — Chrome | `0/100 (lower-bound)` | Browser-local save/reload and edge cases are verified in Codex In-app Browser across selected mobile, landscape, and desktop sizes; the title focus ring is covered by a 29/29 focused widget suite and the release Web build passes. The separate Chrome-targeted adapter test launched headless Chrome but was interrupted after more than ten minutes without a result. This is not an independent Chrome session or a complete Notion matched-state visual matrix. |
| Web — Edge | `0/100 (lower-bound)` | No Edge browser was exposed in the current computer-use browser inventory, so no current-source Edge run was made. |
| macOS | `0/100 (lower-bound) (UNVERIFIED)` | No macOS runner on this host. |
| **Overall** | **`0/100 (lower-bound)` — `>=95/100` is not established** | Native platform evidence and the complete platform × viewport × state matrix are still missing. |

## Android portrait Notes-list refinement — 2026-09-26

The compact Notes list now uses separate, unboxed rows and omits its explanatory
subtitle, closer to the supplied Notion Android reference. Note titles, content
previews, selection semantics, stable keys, and the existing note-selection
callback remain intact. Login/Register, domain/application, infrastructure, and
backend files were not part of this tranche.

Verification:

- `dart analyze` passed for `notes_list_panel.dart`,
  `notes_localizations.dart`, and `notes_workspace_page_test.dart`.
- The focused Notes workspace suite passed 27/27 using the existing
  test-only `local_llm_bridge` package-root shim. The harness verified and
  restored `.dart_tool/package_config.json` to SHA-256
  `BB1F5D5C8F88BED214DF461A6D8B4B7F62CAB1F38829E65E05C4FEA9C9D73025`.
- The ordinary Windows test runner could not start tests because its native
  `local_llm_bridge` hook failed to link llama.cpp objects. The Android debug
  APK build produced no artifact before it was stopped after several minutes
  without Gradle output. Therefore captures 001–015 in
  `output/playwright/20260926-android-native/` document the preceding installed
  UI and its portrait note create/autosave/list/reopen workflow; they do not
  prove the new unboxed rows visually on the emulator.
- `git diff --check` passed. The Android and overall visual-fidelity scores
  remain `0/100 (lower-bound)`; a current-source Android install, matched Notion states, and the
  required platform × viewport × state matrix are still outstanding. The
  `>=95/100` target is not established.
