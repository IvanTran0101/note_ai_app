# UI Visual QA — Step 10 (baseline 2026-09-22; follow-up 2026-09-24)

Captures run against the release web build at DPR 1. The 2026-09-22 baseline
used Chrome 153; the 2026-09-23 editor follow-up used Microsoft Edge for `03`–`05`
and `08`, and Playwright Chromium for `07`. Two builds were used:
`--dart-define=NOTEFLOW_AUTH_MODE=local` for workspace states and the default
Cognito build for auth states. Reference
anchors come from `docs/notion-reference-matrix.md` (live-measured
2026-09-22).

Follow-up on 2026-09-23: editor screenshots `03`, `04`, `05`, `07`, and `08`
were recaptured from the current release web build in a browser at DPR 1. The
viewports are 1440×900 (`03`–`05`), 768×1024 (`07`), and 393×852 (`08`). The old
captures showed the title using a small floating field label; current captures
show the 40px page title both empty and filled, with the body using its 16px
page style. `07` includes the medium navigation rail, empty notes list, and
blank editor. `04` and `05` show the dirty state in light/dark themes. For these
dirty-state captures, the browser was put offline before sample text was
entered, so no note was persisted. Other screenshots remain from the
2026-09-22 run; their states were not affected by the editor styling change.

## Capture inventory

| File | State | Viewport | Theme |
| --- | --- | --- | --- |
| `01-dashboard-empty-1440-light.png` | Historical first-load capture; superseded by fresh Web storage-unavailable state below, not current score evidence | 1440×900 | light |
| `02-notes-1440-light.png` | Historical capture combines load error and empty-state content; stale, not current score evidence | 1440×900 | light |
| `03-editor-new-1440-light.png` | new note editor (no Save, Summarize disabled) | 1440×900 | light |
| `04-editor-dirty-1440-light.png` | editor with title/content + dirty indicator | 1440×900 | light |
| `05-editor-dirty-1440-dark.png` | editor dirty | 1440×900 | dark |
| `06-dashboard-1440-dark.png` | dashboard | 1440×900 | dark |
| `07-notes-medium-768-light.png` | notes workspace with rail | 768×1024 | light |
| `08-compact-393-light.png` | compact single-surface | 393×852 | light |
| `09-dashboard-compact-393-light.png` | compact dashboard | 393×852 | light |
| `10-settings-sheet-1440-light.png` | appearance/settings bottom sheet | 1440×900 | light |
| `11-login-1440-light.png` | Login panel | 1440×900 | light |
| `12-register-1440-light.png` | Register panel | 1440×900 | light |
| `13-login-compact-393-light.png` | Login compact | 393×852 | light |
| `14-editor-new-full-page-1440-light.png` | Current full-page new-note editor, blank draft; not persisted | 1440×900 | light |
| `15-editor-new-autosave-1440-light.png` | Current standalone new-note editor with autosave status; blank draft | 1440×900 | light |
| `16-editor-new-autosave-390-light.png` | Current compact standalone new-note editor; blank draft | 390×844 | light |
| `17-editor-new-shell-768-dark.png` | Current editor inside workspace with tablet navigation rail; blank draft | 768×1024 | dark |
| `18-editor-new-shell-390-dark.png` | Current compact editor inside workspace shell; blank draft | 390×844 | dark |
| `19-noteflow-login-390x844-light.png` | Current NoteFlow Login after compact top-spacing fix | 390×844 | light |
| `20-notion-login-390x844-reference.png` | Live Notion Login reference | 390×844 | light |
| `21-noteflow-register-390x844-light.png` | Current NoteFlow Register after compact top-spacing fix | 390×844 | light |
| `22-notion-signup-390x844-reference.png` | Live Notion Sign up reference | 390×844 | light |
| `23-noteflow-login-1280x800-light.png` | Current NoteFlow Login | 1280×800 | light |
| `24-notion-login-1280x800-reference.png` | Historical Notion Login reference; actual image is 1280×720, so not a same-size desktop pair | 1280×720 | light |
| `25-noteflow-register-1280x800-light.png` | Current NoteFlow Register | 1280×800 | light |
| `26-notion-signup-1280x800-reference.png` | Historical Notion Sign up reference; actual image is 1280×720, so not a same-size desktop pair | 1280×720 | light |
| `27-editor-new-web-storage-unavailable-1440x900.png` | Fresh Web build, blank new-note draft; storage unavailable is explicit | 1440×900 | light |
| `28-editor-new-web-storage-unavailable-390x844.png` | Fresh Web build, compact blank draft; cloud-off status icon | 390×844 | light |
| `29-noteflow-login-390x844-light-current.png` | Current Login with external field labels and muted hints | 390×844 | light |
| `30-noteflow-register-390x844-light-current.png` | Current Register with external field labels and muted hints | 390×844 | light |
| `31-noteflow-login-1280x800-light-current.png` | Current Login with external field labels and muted hints | 1280×800 | light |
| `32-noteflow-register-1280x800-light-current.png` | Current Register with external field labels and muted hints | 1280×800 | light |
| `33-editor-fullscreen-360x800-light.png` | New-note editor opened from the global workspace action; shell is covered | 360×800 | light |
| `34-editor-fullscreen-375x667-light.png` | Same full-screen editor route | 375×667 | light |
| `35-editor-fullscreen-412x915-light.png` | Same full-screen editor route | 412×915 | light |
| `36-editor-fullscreen-768x1024-light.png` | Same full-screen editor route; navigation rail is covered | 768×1024 | light |
| `37-editor-fullscreen-1024x1366-light.png` | Same full-screen editor route | 1024×1366 | light |
| `38-editor-fullscreen-1280x800-light.png` | Same full-screen editor route; workspace sidebar is covered | 1280×800 | light |
| `39-editor-fullscreen-1440x900-light.png` | Same full-screen editor route | 1440×900 | light |
| `40-editor-workspace-shell-1280x800-light.png` | New-note editor opened from the Notes list; workspace sidebar stays visible | 1280×800 | light |
| `41-editor-workspace-shell-390x844-light.png` | Same embedded editor with compact workspace bar | 390×844 | light |
| `42-editor-global-create-1280x800-light.png` | Global New note now opens in the Notes workspace; sidebar stays visible | 1280×800 | light |
| `43-editor-global-create-768x1024-light.png` | Global New note with the tablet NavigationRail retained | 768×1024 | light |
| `44-editor-global-create-390x844-light.png` | Global New note with the compact workspace bar retained | 390×844 | light |
| `45-editor-global-create-1440x900-light.png` | Global New note with the desktop sidebar retained | 1440×900 | light |
| `46-editor-unsaved-web-draft-switch-guard-1280x800.png` | Dirty Web draft remains in place when another New note is requested | 1280×800 | light |
| `47-editor-web-storage-unavailable-informational-1280x800.png` | Dirty Web draft after unsupported autosave; storage warning uses neutral informational styling | 1280×800 | light |
| `48-home-web-storage-unavailable-informational-1280x800.png` | Home shows the Web storage limitation with the same muted cloud-off treatment | 1280×800 | light |
| `49-notes-draft-before-resize-1280x800.png` | Earlier embedded editor capture; retained for audit, superseded by fresh-build recheck below | 1280×800 | light |
| `50-notes-draft-after-resize-390x844.png` | Earlier capture appeared to show draft loss; conflicts with fresh-build recheck and is not current pass/fail evidence | 390×844 | light |
| `51-editor-long-title-wrap-390x844.png` | Fresh release build: long title wraps and body draft remains visible after compact resize | 390×844 | light |
| `52-editor-long-title-draft-768x1024.png` | Same dirty draft at tablet width after compact resize | 768×1024 | light |
| `53-editor-long-title-draft-1280x800.png` | Same dirty draft returned to desktop width after the autosave-unavailable notice | 1280×800 | light |
| `54-editor-sidebar-collapsed-1280x800-light.png` | Blank editor with collapsed sidebar; reopen overlay does not reserve a content column | 1280×800 | light |
| `55-editor-sidebar-collapsed-1280x720-dark.png` | Same collapsed editor in dark theme; title anchor visually checked against the live Notion page | 1280×720 | dark |
| `56-editor-web-unsaved-back-confirmation-390x844.png` | Web draft-loss confirmation; Cancel and Discard only | 390×844 | light |
| `57-notes-web-storage-unavailable-after-discard-390x844.png` | Notes page retains the explicit storage-unavailable state after discard | 390×844 | light |
| `66-noteflow-login-1280x800-final.png` | Current-source Login screen | 1280×800 | light |
| `67-noteflow-register-1280x800-final.png` | Register before the email-first and 32px panel-top refinements; historical capture | 1280×800 | light |
| `68-noteflow-register-390x844-final.png` | Register before the email-first refinement; historical capture | 390×844 | light |
| `69-noteflow-login-390x844-final.png` | Current-source Login screen | 390×844 | light |
| `70-noteflow-home-1440x900-current.png` | Current-source Home with Web storage limitation | 1440×900 | light |
| `71-noteflow-notes-1280x800-current.png` | Current-source Notes with Web storage limitation and desktop sidebar | 1280×800 | light |
| `72-noteflow-notes-1024x768-current.png` | Current-source Notes with desktop sidebar | 1024×768 | light |
| `73-noteflow-notes-768x1024-current.png` | Current-source Notes with NavigationRail | 768×1024 | light |
| `74-noteflow-notes-390x844-current.png` | Current-source compact Notes screen | 390×844 | light |
| `75-noteflow-notes-360x800-current.png` | Current-source compact Notes screen; limitation message wraps without overflow | 360×800 | light |
| `76-noteflow-notes-1440x900-current.png` | Current-source Notes with desktop sidebar | 1440×900 | light |
| `77-noteflow-compact-navigation-390x844-current.png` | Compact navigation sheet with Notes selected | 390×844 | light |
| `78-noteflow-home-390x844-current.png` | Current-source Home with Web storage limitation | 390×844 | light |
| `79-noteflow-forgot-password-1280x800-current.png` | Current-source reset-code request screen (heading: “Reset your password”) | 1280×800 | light |
| `80-noteflow-forgot-password-390x844-current.png` | Same reset-code request screen | 390×844 | light |
| `81-noteflow-reset-password-1280x800-current.png` | Current-source new-password form; demo email is supplied by the URL | 1280×800 | light |
| `82-noteflow-reset-password-390x844-current.png` | Same new-password form | 390×844 | light |
| `83-noteflow-verify-email-1280x800-current.png` | Current-source verify-email page while signed out; Login CTA shown | 1280×800 | light |
| `84-noteflow-verify-email-390x844-current.png` | Same signed-out verify-email page | 390×844 | light |
| `85-noteflow-register-1280x800-debug-current.png` | Current Register after email-first and 32px panel-top refinements; debug ribbon is visible and excluded from fidelity scoring | 1280×800 | light |
| `86-noteflow-home-1280x720-current-inter-font.png` | Current release Web Home after bundling Inter; explicit Web storage limitation; no note loaded | 1280×720 | light |
| `111-notion-login-1280x800-reference-live-20260924.png` | Fresh public Notion Login reference; live route, no form submitted | 1280×800 | light |
| `112-notion-signup-1280x800-reference-live-20260924.png` | Fresh public Notion Sign up reference; live route, no form submitted | 1280×800 | light |
| `113-notion-signup-390x844-reference-live-20260924.png` | Fresh public Notion Sign up reference; live route, no form submitted | 390×844 | light |
| `114-notion-login-390x844-reference-live-20260924.png` | Fresh public Notion Login reference; live route, no form submitted | 390×844 | light |
| `115-noteflow-home-1440x900-shell-current-20260924.png` | Current release Web Home, expanded sidebar with workspace identity and labeled footer actions | 1440×900 | light |
| `116-noteflow-notes-1440x900-shell-current-20260924.png` | Current release Web Notes destination with Notes active and the existing Web storage limitation | 1440×900 | light |
| `117-noteflow-sidebar-collapsed-1440x900-current-20260924.png` | Current release Web Home with the desktop sidebar collapsed | 1440×900 | light |
| `118-noteflow-sidebar-compact-menu-390x844-current-20260924.png` | Current release Web compact navigation bottom sheet | 390×844 | light |
| `119-noteflow-sidebar-compact-bar-390x844-current-20260924.png` | Current release Web compact workspace header | 390×844 | light |
| `120-noteflow-sidebar-medium-768x1024-current-20260924.png` | Current release Web medium-width NavigationRail | 768×1024 | light |
| `121-noteflow-sidebar-expanded-1024x768-current-20260924.png` | Current release Web expanded sidebar at a compact desktop viewport | 1024×768 | light |
| `128-noteflow-home-empty-1080x2400-android15-api35.png` | Android 15/API 35 AVD, current-source Home empty state under temporary local-auth QA build | 1080×2400 | light |
| `129-noteflow-editor-empty-1080x2400-android15-api35.png` | Android 15/API 35 AVD, current-source blank note editor under temporary local-auth QA build | 1080×2400 | light |

Image dimensions were read from the PNG files. Historical references `24` and
`26` are 1280×720 despite their filenames; use `111`–`114` for current
same-size authentication comparisons.

## Workspace shell tranche — 2026-09-24

The current source Web release build passed in 69.5s with local-auth preview
mode and was reviewed at DPR 1. Captures 115–121 show the updated workspace
identity mark, Workspace section label, Home/Notes destination states, labeled
Settings/Diagnostics footer rows, collapsed sidebar, medium NavigationRail,
compact header and compact navigation sheet. These captures validate NoteFlow
layout and responsiveness only; they are not pixel pairs against a Notion
sidebar screenshot and do not establish the 95-point score.

`flutter analyze --no-pub` on the shell/localization/test files passed. The
direct widget test command stopped before assertions because the unrelated
`local_llm_bridge` native hook failed on `llama-vocab.obj` (`LNK1136`). Rerunning
with a temporary test-only package root passed `workspace_shell_test.dart`
18/18; `.dart_tool/package_config.json` was restored to SHA-256
`BB1F5D5C8F88BED214DF461A6D8B4B7F62CAB1F38829E65E05C4FEA9C9D73025`. No
backend, domain, application, infrastructure, route, persistence, or auth
controller files were changed. Android/iOS/macOS runtime checks remain
outstanding; this tranche's screenshot captures are Web-only.

## Fresh Home/Notes responsive run — 2026-09-23

The current working tree was rebuilt as a release Web app with
`NOTEFLOW_AUTH_MODE=local`, served locally, and reviewed in Playwright at DPR 1.
These captures supersede screenshots `01` and `02` for the current Home/Notes
load-error state. The old images remain for history only.

| File | State | Viewport | Theme |
| --- | --- | --- | --- |
| `output/playwright/20260923-ui95-workflow-rerun/home-1440x900-current.png` | Home with explicit Web storage-unavailable message | 1440×900 | light |
| `output/playwright/20260923-ui95-workflow-rerun/notes-1440x900-current.png` | Notes list with explicit Web storage-unavailable state and New note action | 1440×900 | light |
| `output/playwright/20260923-ui95-workflow-rerun/notes-1024x768-current.png` | Notes list with expanded sidebar | 1024×768 | light |
| `output/playwright/20260923-ui95-workflow-rerun/notes-768x1024-current.png` | Notes list with labelled NavigationRail | 768×1024 | light |
| `output/playwright/20260923-ui95-workflow-rerun/notes-390x844-current.png` | Notes list with compact workspace bar | 390×844 | light |
| `output/playwright/20260923-ui95-workflow-rerun/notes-360x800-current.png` | Compact Notes; the header actions and message remain inside the viewport | 360×800 | light |

At 390/360 the shell uses the compact menu, at 768 the labelled rail, and at
1024/1440 the 248px sidebar. The title and New note action remain within the
content width at each captured size. This is a responsive Web check of the
current error state, not a saved-note flow, a native-device check, or a paired
Notion pixel diff; no note was written.

The capture inventory contains historical as well as current images. It does
not by itself prove that every Step 10 workflow is covered: loaded note data,
all menu/dialog states, auth errors, accessibility scales, dark/light pairs and
native-device behavior still require separate runtime or test evidence.
Summary ready/stale and model-provisioning states have widget-test coverage in
`note_detail_page_test` and `model_provisioning_status_panel_test`; consult the
verification notes below for whether the current test invocation reached its
assertions.

## Latest UI pass — 2026-09-23

After the screenshots above were captured, medium and wide Notes changed from a
list/detail split to separate full-page list and editor states. The wide editor
uses its page header for the existing back/unsaved-changes flow, a 112px content
inset, a 720px title block and a 708px body-text column. When collapsed, the
desktop sidebar reopens through a 44×44px overlay and no longer takes a
permanent 40px content column. Captures 54–55 record this latest layout at
1280×800 light and 1280×720 dark. The title anchor at x=280, y=168 was visually
checked against the live Notion page at 1280×720 dark. These are implementation
captures, not paired reference screenshots or a full visual diff. The Notes
preview still cannot load persisted notes from its current backend connection.

For a current visual review, `14-editor-new-full-page-1440-light.png` captures
the blank `New note` editor in the current release web preview at 1440×900. It
shows the full-page editor without split list/detail panes. This is an unsaved
draft; the screenshot does not verify persistence or the post-save state.

### Editor status follow-up — 2026-09-23

The current editor header uses the breadcrumb `NoteFlow / New note`. Native
builds show the existing autosave state; the Web build shows `Saving unavailable
on Web` with a cloud-off icon, and compact layouts use the icon with a tooltip.
The body no longer repeats the save hint, and Summarize remains
disabled for an unsaved note with its existing explanation available as a
tooltip. Captures `15`–`18` show the current web build at desktop, phone, and
tablet widths in light/dark themes. They are all blank drafts and do not prove
that a note was persisted. The Notes destination still shows a backend load
error in this browser, so a saved-note state is unavailable for comparison.
These editor-only captures also have no paired, same-state Notion screenshots;
they do not produce a fidelity score.

### Fresh Web storage-state verification — 2026-09-23

A fresh release Web build passed and was opened at 1440×900 and 390×844.
Home and Notes show that this Web build cannot load or save notes, without a
Retry action; a blank new-note draft shows `Saving unavailable on Web` on
desktop and the cloud-off icon on compact screens. Captures `27`–`28` record
these states. They confirm the UI no longer claims that a Web draft autosaved;
they do not demonstrate a persisted note or satisfy the 95-point gate.

### Web storage warning styling — 2026-09-23

The Web editor keeps the explicit message that a draft cannot be saved and will
be lost when leaving, but presents unsupported storage with a muted cloud-off
icon and neutral surface. The page-header status and Home limitation notice use
the same muted icon treatment; ordinary save/load errors remain red. Captures
`47`–`48` were taken from the fresh release build at 1280×800. This presentation
change does not add Web persistence or alter the save/controller contract.

### Auth spacing follow-up — 2026-09-23

The current release Web build adds page labels above auth fields, muted
localized hints, tighter input padding and responsive form spacing while
keeping the existing field keys, validators, autofill and controller calls.
Captures `29`–`32` compare Login/Register at 390×844 and 1280×800 with the live
Notion auth references. Unsupported provider choices were not added. These
initial-state captures improve the auth match but do not score validation,
busy/error, forgot/reset, verify or change-password states. At the time of this
capture, the focused auth test command stopped before execution on the corrupt
native bridge object; the later suite rerun is recorded below.

### Responsive editor matrix follow-up — 2026-09-23

A fresh local-auth Web release build (`.dart_tool/ui95_web_matrix_20260923_02`)
was opened at 360×800, 375×667, 390×844, 412×915, 768×1024, 1024×1366,
1280×800, and 1440×900. Captures `33`–`39` show the blank editor entered from
the global workspace New note action. The title and content remain visible at
each viewport, and the Web storage limitation is explicit. These screenshots
are responsive checks only; they are blank drafts without persistence or paired
Notion pixel diffs.

Captures `33`–`39` were taken before the workspace-entry alignment and show the
global action covering the shell. The current UI routes the global desktop and
compact New note actions and the Dashboard note callbacks into the existing
Notes workspace editor; captures `42`–`45` confirm the sidebar, tablet rail,
and compact workspace bar remain present. The Notes-list entry still uses that
same embedded editor (`40`–`41`). A dirty draft guard was manually checked at
1280×800: requesting another New note retained the current title and showed
the existing unsaved-changes message (`46`). The Web limitation remains
visible, and no note was persisted by this test. Widget tests for the new
workspace entry methods were added, but the test command aborts before test
execution on `llama-kv-cache-dsv4.obj : fatal error LNK1136`; targeted analyzer,
fresh Web release build, and Android release APK build pass. The APK is 87.5 MB
and was built with JDK 17; physical-device behavior remains unverified.

## Fidelity score — not yet verified

The previous `95/100` score is withdrawn. It was an estimate from implementation
screenshots and widget-state coverage, not a same-viewport, same-state comparison
against Notion for every group in plan §6. The current Web build cannot load or
save notes, so there is no persisted-note browser capture to score. The score
gate is **not met or claimed** until the final implementation is measured against
the reference matrix on each supported layout.

Current grading decision: **not passed; no defensible numeric score assigned**.
The latest editor anchor check is positive, but required visual groups and
device viewports remain unscored. This means there is not enough evidence to
claim `>=95`; it does not assert a measured score below 95.

## Known limitations (không che giấu)

1. Android 15/API 35 is an emulator capture, not a physical Android device.
   iPhone/iPad/macOS still need a compatible Apple runner. Safe-area/keyboard
   behavior must be checked on those real devices before release under plan
   §4.4.
2. The current browser run explicitly reports that the Web build cannot load
   or save notes, so a persisted-note page and actual browser save cannot be
   visually verified. Existing controller behavior is covered by
   presentation tests through its test seam; those tests do not prove the web
   persistence path. This UI task does not change that data layer.
3. **Sidebar/Share/menu đầy đủ của Notion** không chụp được từ trang reference
   (view-only); đối chiếu theo docs + inventory của plan §2.3 như đã ghi trong
   reference matrix.
4. An Android 15/API 35 emulator now covers Login/Register, Home, a blank note
   editor, autosave across force-stop/relaunch, reopen, and delete of the single
   QA note. iOS/macOS builds and runtime QA need a compatible Apple runner.

## Re-review verification (2026-09-23)

- `dart format --output=none --set-exit-if-changed lib test`: PASS, 167 files,
  0 changed.
- `flutter analyze lib/main.dart lib/presentation`: PASS, no issues.
- Plan regression gate (10 files): PASS, 104 tests.
- Full `flutter test --no-pub`: PASS, 587 passed, 1 skipped. Used the documented
  Windows shim for `local_llm_bridge`; the generated package config was restored.
- `flutter analyze`: 41 issues remain under `packages/local_llm_bridge/test/**`
  because that package does not declare `package:test`; presentation analyze is
  clean and the package was not changed.
- `flutter build web --release --dart-define=NOTEFLOW_AUTH_MODE=local`: PASS.
- `flutter build apk --release`: PASS, 87.5 MB; Gradle used JDK 17.
- Current release web preview: Home and Notes show the explicit storage-unavailable
  state; a blank editor shows that saving is unavailable on Web. This QA does
  not claim a saved note or real browser persistence flow was verified.

### Incremental editor-header verification — 2026-09-23

- `flutter test --no-pub test/presentation/notes/note_detail_action_bar_test.dart test/presentation/notes/note_detail_surface_test.dart`: PASS, 29 tests. The Windows test invocation used a temporary test-only `local_llm_bridge` shim; `.dart_tool/package_config.json` was restored byte-for-byte afterward.
- `flutter test --no-pub test/presentation`: PASS, 177 tests, using the same temporary test-only shim. The script and shim were removed, and `.dart_tool/package_config.json` SHA-256 was restored to `BB1F5D5C8F88BED214DF461A6D8B4B7F62CAB1F38829E65E05C4FEA9C9D73025`.
- `flutter test --no-pub test/presentation/auth/auth_pages_test.dart`: PASS, 8 tests, with a temporary empty `local_llm_bridge` package root to bypass the unrelated corrupt native asset; `.dart_tool/package_config.json` was restored to the same SHA-256.
- After the responsive Login/Register spacing change, `flutter test --no-pub test/presentation`: PASS, 178 tests, using the same temporary package-root shim; `.dart_tool/package_config.json` was restored to the same SHA-256.
- `flutter analyze --no-pub lib/presentation/auth/auth_pages.dart test/presentation/auth/auth_pages_test.dart`: PASS, no issues. `dart format --output=none --set-exit-if-changed` on the two touched Dart files: PASS.
- `flutter build web --release --no-pub --no-wasm-dry-run -o .dart_tool/auth_ui_preview`: PASS. The browser preview used the default Cognito mode; no auth form was submitted.
- Targeted `flutter analyze` of the six changed editor/header Dart files: PASS, no issues.
- `dart format --output=none --set-exit-if-changed` on the eight touched Dart files: PASS, no formatting changes required.
- `flutter build web --release --dart-define=NOTEFLOW_AUTH_MODE=local`: PASS.
- `flutter build apk --release`: PASS, 87.5 MB, Gradle/JDK 17, 76.5 seconds.
- Latest full `flutter test --no-pub --reporter compact` with the test-only shim: 601 passed, 2 could not load (`llm_worker_client_test.dart` and `local_model_smoke_test.dart`). A direct rerun of `llm_worker_client_test.dart` without the shim fails before tests start while building the native asset: `llama-kv-cache-dsv4.obj : fatal error LNK1136: invalid or corrupt file`. The presentation suite is clean; the full repository test gate remains unresolved because of this native build artifact.
- Captures `15`–`18` and `27`–`28` are blank drafts; real persistence remains unverified because the current Web build cannot load or save notes.

### Fresh responsive editor recheck — 2026-09-23

The earlier capture pair `49`–`50` appeared to show the title resetting after
resize. A fresh release build from the current source, served from a new output
directory and port, did not reproduce that reset. In Notes → New note, a long
title and body remained visible through 1280×800 → 390×844 → 768×1024 →
1280×800, including after the Web autosave attempt displayed the existing
storage-unavailable notice. Captures `51`–`53` record the wrapped title and the
same dirty draft at compact, tablet, and desktop widths. Treat `49`–`50` as
superseded observations; the earlier cause is unresolved, so the recheck does
not claim that a persisted note was saved.

The compact review exposed a real title-clipping issue. The title field now
wraps vertically at narrow widths while keeping its existing controller, key,
focus node, and save callbacks. The current release build uses this change.
`flutter analyze --no-pub lib/presentation/notes/note_detail_editor_form.dart
test/presentation/notes/note_detail_surface_test.dart` passes. The new focused
widget test could not reach assertions: Flutter remained in the existing
`local_llm_bridge` native-asset hook for 90 seconds and was interrupted. Browser
captures verify the visual wrap, but paired Notion comparison, native save
verification, and the overall `>=95/100` score remain incomplete.

- Fresh Web release build to `build/web_wrapped_title_20260923`: PASS.
- `flutter build apk --release --no-pub`: PASS, 87.5 MB.
- `flutter devices`: Windows, Chrome, and Edge only; no Android device or
  emulator is connected. iOS/macOS device review still requires an Apple runner.

### Collapsed-sidebar editor follow-up — 2026-09-23

The current release Web build was captured at DPR 1 with the workspace sidebar
collapsed: `54` at 1280×800 light and `55` at 1280×720 dark. The 44×44px reopen
overlay leaves the editor full-width. The title block is 720px wide, body text
is constrained to 708px, and the content inset is 112px. The title starts at
x=280px, y=168px; this anchor was visually checked against the live Notion page
at 1280×720 dark. It is a single-anchor review, not a paired pixel diff. The
targeted analyzer and fresh Web/Android release builds pass. The focused widget
test after this layout change did not reach assertions because the
`local_llm_bridge` native-asset hook stopped on a corrupt `.obj`; do not count
that attempt as a test pass. The overall score gate remains unverified.

### Web dirty-back confirmation — 2026-09-23

Capture `56-editor-web-unsaved-back-confirmation-390x844.png` records the
current release Web UI after entering a temporary `QA draft` title and using
the existing editor back action. At 390×844, the dialog explains that this Web
build cannot save notes and that the draft will be lost; it offers Cancel and
Discard and has no Save action. This was a browser-only, unsaved test draft; it
does not verify persistence or native behavior. At the time, the focused widget
test was blocked before assertions by the corrupt `local_llm_bridge` native
asset; the later suite rerun is recorded below. This screenshot is runtime
evidence for this one state, not a test pass or a 95-point score.

Capture `57-notes-web-storage-unavailable-after-discard-390x844.png` records
the Notes page immediately after choosing Discard. The explicit storage
unavailable message remains visible instead of the empty-state “No notes yet”.
This verifies the presentation state through a real Web release build; the
widget regression had not run successfully when this capture was first
recorded. It does not verify persistence or count toward a numeric fidelity
score by itself.

### Earlier regression and build verification — 2026-09-23

- `flutter test --no-pub test/presentation --reporter expanded`: PASS, 189/189.
  Windows required a temporary test-only `local_llm_bridge` package-root shim;
  `.dart_tool/package_config.json` was restored byte-for-byte to SHA-256
  `BB1F5D5C8F88BED214DF461A6D8B4B7F62CAB1F38829E65E05C4FEA9C9D73025`.
- `flutter analyze --no-pub lib/main.dart lib/presentation`: PASS, no issues.
- `dart format --output=none --set-exit-if-changed` on the four touched Dart
  files: PASS, 0 files changed. `git diff --check`: PASS with line-ending
  warnings only.
- Fresh Web release build: PASS at
  `output/playwright/20260923-ui95-postfix/web`.
- `flutter build apk --release --no-pub`: PASS, 87.5 MB at
  `build/app/outputs/flutter-apk/app-release.apk`.
- The unsupported-storage editor notice now keeps the neutral informational
  treatment when rendered from an `UnsupportedError`; controller/save behavior
  is unchanged. No persisted Web note was available for visual comparison.
- This regression/build pass does not satisfy the fidelity score gate. Same-
  state Notion comparisons for every required view, remaining auth/overlay
  states, and physical-device checks are still incomplete; no numeric score is
  assigned.

### Auth responsive follow-up — 2026-09-23

- Register now uses a 496px panel on widths of 600px and above; phone layout
  remains panel-free. Login uses 38px compact and 72px desktop top padding;
  Register puts Email first, followed by Display name, Password, and Confirm
  password. It uses 76px compact and 32px desktop top padding, with the existing
  32px fallback on short viewports. Its desktop panel top is constrained to
  28–36px by the auth widget test to match the Notion signup reference at 32px.
- `flutter test --no-pub test/presentation/auth/auth_pages_test.dart`: PASS,
  9/9. An earlier `test/presentation` run passed 189/189 before the final auth
  spacing refinement. Tests use a temporary test-only `local_llm_bridge` shim; the
  package-config file was restored byte-for-byte to SHA-256
  `BB1F5D5C8F88BED214DF461A6D8B4B7F62CAB1F38829E65E05C4FEA9C9D73025`.
- Widget checks cover phone 393×852 and desktop/tablet 1280×800 and 768×1024.
- Paired captures are `66` Login desktop, `67` Register desktop, `68` Register
  phone, and `69` Login phone. The Register images predate the field-order and
  panel-top refinements and are retained as historical evidence. They were
  compared visually with
  Notion references `24`, `26`, `22`, and `20` at matching viewports. The form
  widths and header placement are close, but content hierarchy differs because
  NoteFlow keeps its existing password Login and four-field registration while
  Notion's reference shows an email-first page and provider controls. The
  current Register UI now places Email first but keeps the existing remaining
  fields; unsupported provider actions were not added.
- The visual review is qualitative only. The captures do not cover all auth
  states, accessibility, or all target platforms, so no numeric auth or app
  score is assigned and the app-wide `>=95/100` gate is not established.
- Auth route follow-up: captures `79`–`84` record the existing reset-code
  request, new-password form, and signed-out verify-email page at 1280×800 and
  390×844. The reset form's `demo@example.com` value came from a URL parameter;
  no auth form was submitted and no backend response was simulated. The
  verify-email screen offers Login in this signed-out state. These captures
  document current states only; they are not paired with same-state Notion
  references and do not cover validation, busy, error, success, or
  change-password states.
- Register refinement: the desktop panel top padding now matches the Notion
  signup reference at 32px (previously 40px), and Email is the first field.
  Existing Display name, Password, Confirm password, validators, keys, and
  `RegisterInput` mapping remain intact. The auth page suite passes 9/9,
  including field-order and 28–36px panel-top assertions. Capture `85` confirms
  the current source in a signed-out debug Web run; its Flutter debug ribbon is
  excluded from the fidelity review. The local-auth release preview rendered
  Home after navigation to `/register`; I did not override auth state. Captures
  `67`–`68` predate these refinements.
- After an earlier rerun hit a transient disk-full error and stalled in auth
  navigation, the current-source command
  `flutter test --no-pub test/presentation --reporter compact --timeout 60s`
  passed 189/189 using the temporary test-only package-root shim. The auth page
  suite passes 9/9 within that run; `.dart_tool/package_config.json` was
  restored byte-for-byte to SHA-256
  `BB1F5D5C8F88BED214DF461A6D8B4B7F62CAB1F38829E65E05C4FEA9C9D73025`.

### Auth text-scale regression check — 2026-09-23

- Added a widget check that pumps Login and Register at 200% text scale in a
  360×800 viewport, scrolls each existing submit action into view, and verifies
  there is no layout exception. The Register password-confirmation test now
  scrolls its existing submit action into view before tapping it in the 800×600
  test viewport.
- Current auth widget suite: PASS, 10/10. Current full presentation suite:
  PASS, 190/190, using the temporary test-only `local_llm_bridge` package-root
  shim. `.dart_tool/package_config.json` was restored byte-for-byte to SHA-256
  `BB1F5D5C8F88BED214DF461A6D8B4B7F62CAB1F38829E65E05C4FEA9C9D73025`.
- This covers only Login/Register action reachability under one high text-scale
  phone configuration. It does not establish full semantics, focus, keyboard,
  localization, 1.3 scale, other surfaces/platforms, or the `>=95/100` score.

### Auth full-viewport background follow-up — 2026-09-23

- `_AuthFormScaffold` now gives the scroll content a minimum height equal to
  the viewport minus its top and bottom padding. This keeps the selected auth
  background visible below short forms while retaining scrolling for tall forms.
- The widget test checks Login and Register at 360×800, 393×852, 768×1024,
  1280×550, 1280×800, and 1440×900. The auth widget suite passes 11/11 and the
  full presentation suite passes 191/191 with the temporary test-only
  `local_llm_bridge` shim; `.dart_tool/package_config.json` was restored to
  SHA-256 `BB1F5D5C8F88BED214DF461A6D8B4B7F62CAB1F38829E65E05C4FEA9C9D73025`.
- `flutter analyze --no-pub lib/presentation/auth/auth_pages.dart
  test/presentation/auth/auth_pages_test.dart` reports no issues. Current-source
  `flutter build web --release --no-pub --dart-define=NOTEFLOW_AUTH_MODE=local`
  passes (Flutter 3.47.5, WASM dry run, 304.7s). The browser preview opens the
  existing Home state and Web storage-unavailable notice; I did not alter auth
  state to force Register, so a release Register recapture remains pending.
- Current-source `flutter build apk --release --no-pub` passes (87.5 MB,
  316.0s). `flutter devices --machine` lists Windows, Chrome and Edge only; no
  Android device/emulator or Apple runner is available for native visual QA.

### Current shell and Notes responsive review — 2026-09-23

- Release Web build used the current working tree with
  `--dart-define=NOTEFLOW_AUTH_MODE=local`, served from
  `output/playwright/20260923-shell-current/web`. Captures `70`–`78` use DPR 1.
- The 280px desktop sidebar appears at 1280×800, 1024×768, and 1440×900; the
  768×1024 layout uses the labeled NavigationRail; 390×844 uses the compact
  toolbar and navigation bottom sheet. At 360×800 the storage message wraps
  inside the viewport. Home and Notes show the existing Web storage-unavailable
  state; no note data was loaded or persisted in this browser run.
- This verifies current-source layout at those Web viewports, not a same-state
  Notion pixel diff, loaded-note UI, native-device behavior, or the `>=95/100`
  rubric.
- `flutter build apk --release --no-pub`: PASS, 87.5 MB. `flutter devices`
  currently lists Windows, Chrome, and Edge only; no Android device/emulator is
  connected, and iOS/macOS builds require an Apple runner.
- `flutter analyze --no-pub lib/main.dart lib/presentation`: PASS, no issues.
  `dart format --output=none --set-exit-if-changed` on the 27 modified Dart
  files: PASS, 0 changed. Current-source presentation suite: PASS, 189/189,
  with the temporary test-only shim and restored package-config SHA above.

### Inter font asset follow-up — 2026-09-23

- Bundled `assets/fonts/Inter-Variable.ttf` and its SIL OFL license in
  `pubspec.yaml`; FontTools confirmed variable `opsz`/`wght` axes and Vietnamese
  glyph coverage. The asset adds no dependency and changes no application,
  domain, infrastructure, auth, route, or persistence code.
- `flutter analyze --no-pub lib`: PASS. Current presentation suite: PASS,
  191/191 with the temporary test-only `local_llm_bridge` shim and restored
  `.dart_tool/package_config.json` SHA-256
  `BB1F5D5C8F88BED214DF461A6D8B4B7F62CAB1F38829E65E05C4FEA9C9D73025`.
  The unfiltered root `flutter analyze --no-pub` reports 42 existing issues in
  the unrelated bridge tests and temporary output shim.
- Web release build: PASS (Flutter 3.47.5, 399.1s); its font manifest and output
  include Inter and OFL. Android release APK: PASS (92,217,544 bytes,
  1,758.1s); the APK archive includes both assets.
- Capture `86` is the current light-theme Web Home at 1280×720, served from that
  release build. It verifies rendered typography on this one Web screen only;
  the existing message says Web cannot load or save notes. No note was loaded
  or persisted. iOS/macOS builds and runtime rendering remain unverified on
  this Windows host. This capture does not provide a Notion pixel diff or a
  numeric fidelity score, and does not establish the `>=95/100` gate.

### Auth release comparison — 2026-09-24

- Fresh default Cognito-mode Web release builds from the current checkout were
  served at DPR 1: captures `104`–`109` use
  `output/playwright/20260924-auth-mobile-anchor/web`, except refreshed
  captures `106` and `110`, which use
  `output/playwright/20260924-auth-desktop-anchor/web`. The browser used the
  existing `#/login` and `#/register` routes; no auth form was submitted.
- Current captures: `104` Register email at 390×844; `105` Login email at
  390×844; `106` Register email at 1280×800; `107` Login email at 1280×800;
  `108` Register details at 390×844; `109` Login password at 390×844; and `110`
  Register email at 768×1024. Captures `108` and `109` use the synthetic
  `ui-review@example.test` value and stop before account creation or login.
  The email Continue actions only advance the existing local UI step.
- Same-size comparison uses current Notion captures `111`–`114`; the older
  desktop files `24` and `26` are actually 1280×720 despite their filenames.
  The app and public Notion routes were captured at DPR 1, with each browser
  viewport set after navigation; no form was submitted.
- Mobile review found the
  supported form geometry close: the 390px field gutter is 20px, the input is
  350px wide, the main header/form anchors are within a few pixels, and the
  Register Continue button occupies the same `y=375–414` center-column rows as
  the reference. Login's mobile CTA is 3px above Notion's; desktop Login CTA is
  3px below its same-size reference. Register desktop/tablet callout padding
  and CTA spacing were adjusted; the refreshed release capture `106` places the
  CTA at `x=461–818, y=396–435`, matching Notion capture `112` at
  `x=460–819, y=396–435` within 1px horizontally and exactly vertically.
  Capture `110` checks that same registration layout at 768×1024. Notion does
  not provide a directly paired tablet reference here.
- Provider buttons, legal acceptance copy, and language/help controls visible
  in Notion are not added because NoteFlow has no corresponding auth contract.
  Their absence changes the lower-page density. These auth captures do not
  assign a numeric score and do not establish the app-wide `>=95/100` gate.
- `flutter test --no-pub test/presentation/auth/auth_pages_test.dart`: PASS,
  13/13, using the temporary test-only `local_llm_bridge` package-root shim.
  The full presentation suite passes 193/193 with the same shim. Both runs
  restore `.dart_tool/package_config.json` to SHA-256
  `BB1F5D5C8F88BED214DF461A6D8B4B7F62CAB1F38829E65E05C4FEA9C9D73025`.
  Targeted auth analysis reports no issues; Web release build passes.
- After the desktop Register spacing follow-up, the Web release build passes
  and current screenshots `106` (1280×800) and `110` (768×1024) were recaptured.
  The Android release APK also passes from this source at 87.9 MB (142.4s).
  At the time of that build-only check, no Android device/emulator was
  connected; the later auth-only AVD runtime check is recorded below.
  iOS/macOS native builds and runtime checks remain unavailable on this Windows
  host. An earlier build attempt had a transient Dart out-of-memory error; no
  Gradle or backend source was changed.

### Home/Dashboard Step 4 refresh — 2026-09-24

- Desktop Home now uses a 44px top bar, a 960px content column, and a 64px top
  inset; compact layouts keep their 32px inset. Note rows are flat and at least
  56px tall. The grid uses the existing page marker. Loading, empty, and error
  states follow the Home content geometry. The section stays `Recently updated`
  because the existing note model has no visit-history field.
- This tranche changes Dashboard presentation and presentation tests only.
  Existing controllers, sort/filter behavior, callbacks, keys, note fields,
  storage, and API contracts remain in place.
- `flutter analyze --no-pub lib/presentation/dashboard
  lib/presentation/notes/notes_theme_tokens.dart
  test/presentation/dashboard/dashboard_page_test.dart
  test/presentation/common/accessibility_contract_test.dart`: PASS, no issues.
  Dashboard tests: PASS, 37/37. Full presentation suite: PASS, 194/194. Test
  runs use the temporary ignored `local_llm_bridge` shim to bypass the existing
  native MSVC hook-linker failure; `.dart_tool/package_config.json` was restored
  after each run to SHA-256
  `BB1F5D5C8F88BED214DF461A6D8B4B7F62CAB1F38829E65E05C4FEA9C9D73025`.
- Fresh local-auth Web release: PASS (132.2s). Android release APK: PASS
  (88.0 MB, 74.7s). These are compile results. `flutter devices` reports only
  Windows, Chrome, and Edge; `flutter emulators` finds no AVD. There is no
  Android runtime evidence. Native iOS/macOS builds and runtime checks were not
  available on this Windows host.
- Same-state, same-viewport Notion Home screenshots are not paired with a
  loaded NoteFlow Home. The current Web storage limitation and widget-test
  fixtures cannot stand in for a persisted note. No numeric score is assigned;
  the plan's `>=95/100` gate remains unproven and Step 4's visual comparison
  checklist stays open.

### Android 15/API 35 auth runtime follow-up — 2026-09-24

- Installed and launched the existing release APK on the `NoteFlow_API35` AVD.
  Captures `124`–`127` record Login, the email field with the Android keyboard,
  Register reached through the existing Create account action, and Login at
  system font scale `2.0`. The font scale was restored to `1.0` after capture.
- Login rendered at startup; focusing Email showed the focus treatment and
  native keyboard while keeping Continue reachable. Create account opened the
  existing Register screen. No login or registration form was submitted.
- At 200% text scale, the NoteFlow brand and Login heading remain vertically
  separated; the earlier concern about overlap was a misread of this capture.
  This is responsive/auth evidence only, not a Notion comparison or score.
- The Android run did not load persisted notes or exercise Home, the editor,
  save, menus, or overlays. Same-state Notion pairs for those surfaces remain
  outstanding, so no numeric score is assigned and the `>=95/100` gate remains
  unproven. iOS/macOS runtime checks still need an Apple runner.

### Home desktop card-density follow-up — 2026-09-24

- Home now defaults to the existing compact Grid layout when the available
  content width is at least 840dp; phone and tablet widths keep the existing
  single-column List by default. The existing List/Grid segmented control
  remains available as a manual override.
- Wide Grid calculates two to six columns from a 136dp minimum card width. The
  compact page cards use existing note title, preview and updated date data,
  with the existing page icon, theme tokens, semantics and open callback. The
  List card markup and all data/controller/save contracts are unchanged.
- Dashboard widget tests pass 39/39, including the 840dp breakpoint, six cards
  in the first row at 1440dp, and 200% desktop text scale; the full presentation
  suite passes 202/202.
  Targeted `flutter analyze` reports no issues. The temporary test-only
  `local_llm_bridge` package root was used for tests; after each run,
  `.dart_tool/package_config.json` was restored to SHA-256
  `BB1F5D5C8F88BED214DF461A6D8B4B7F62CAB1F38829E65E05C4FEA9C9D73025`.
- Web release build passes in 53.5s; Android release APK builds at 88.0MB in
  68.0s. These verify compilation only; no Android Home runtime capture was
  made for this change.
- Existing Home screenshots predate this change and show the Web
  storage-unavailable state. Widget fixtures verify layout but do not establish
  a persisted-note runtime or a same-state Notion visual pair. No numeric score
  is assigned; the app-wide `>=95/100` gate remains unproven.

### Android Home/editor/autosave runtime follow-up — 2026-09-24

- Built `flutter build apk --release --dart-define=NOTEFLOW_AUTH_MODE=local`
  from source revision `e0b6181`; Gradle reported 1083.2s and the QA APK was
  87.2MB. Its signing certificate matched the existing Cognito release.
- Installed by `adb install -r` on the Android 15/API 35 AVD without clearing
  app data. Captures 128–129 show the actual empty Home and blank editor at
  1080×2400.
- Through the app UI, created a temporary note and entered body text. The note
  appeared in Home, remained after force-stop/relaunch, and reopened with the
  existing “Note saved.” status. The app's More → Delete → confirmation flow
  removed that exact QA note; Home returned to “No notes yet.” No other notes
  existed in the workspace during this check.
- Restored the previous Cognito APK at
  `build/app/outputs/flutter-apk/app-release.apk` byte-for-byte (SHA-256
  `5E0480792576BC417B497EF61548FBD2F24B642F1AEAADD5E30BA0D563988339`),
  updated its `.sha1` sidecar, reinstalled it, and confirmed the Login screen.
  The QA note was deleted before restoring the original build; app data was not
  cleared.
- This confirms Android local-auth runtime autosave/persistence only. It does
  not change the Web storage-unavailable limitation or score visual fidelity.
  There are still no same-state Notion pairs for Home/list/editor, no physical
  device capture, and no iOS/macOS runner. The fidelity score remains
  **unassigned; the `>=95/100` gate is not proven**.

### Dashboard empty state — flat page canvas — 2026-09-24

- `DashboardEmptyView` no longer wraps its existing empty message and Create
  action in a tinted, bordered surface. They align directly with the Home page
  gutter, following the flat page treatment in the Notion reference. The
  `dashboard-empty` semantics container, label, `dashboard-empty-create` key,
  `onCreateNote` callback, and all data/controller contracts remain unchanged.
- [Capture 130](130-noteflow-home-empty-1080x2400-android15-api35-flat-canvas.png)
  shows the current empty Home at 1080×2400 on the Android 15/API 35 AVD (font
  scale 1.0). The existing create action opened the note editor; Android Back
  from the untouched draft returned to “No notes yet” without creating a note.
- Targeted `flutter analyze --no-pub` reports no issues. The Dashboard widget
  suite passes 39/39 over its 360–1440dp coverage using the existing temporary
  test-only `local_llm_bridge` package root. After the run,
  `.dart_tool/package_config.json` was restored to SHA-256
  `BB1F5D5C8F88BED214DF461A6D8B4B7F62CAB1F38829E65E05C4FEA9C9D73025`.
- Android local-auth release build passes in 72.7s at 87.2MB; the QA APK was
  installed with `adb install -r`. The original Cognito APK and `.sha1` sidecar
  were restored; its SHA-256 remains
  `5E0480792576BC417B497EF61548FBD2F24B642F1AEAADD5E30BA0D563988339`.
- Web release build passes in 86.5s. A 1280×720 dark Web runtime check shows
  the existing storage-unavailable message; Web cannot reach the actual empty
  state with the current storage implementation. No iOS/macOS runner is
  available on this Windows host.
- Capture 130 is platform runtime evidence for the empty state, not a paired
  Notion screenshot. Loaded Home/List/Grid and other states still need
  same-viewport pairs; no numeric fidelity score is assigned and the
  app-wide `>=95/100` gate remains unverified.

### Loaded Home and Notes list — local-auth Android runtime — 2026-09-24

- [Capture 131](131-noteflow-notes-list-loaded-1080x2400-android15-api35.png)
  shows the Notes list after creating a temporary note through the existing
  empty-state CTA. [Capture 132](132-noteflow-home-loaded-recent-1080x2400-android15-api35.png)
  shows Home/Recently updated after force-stop and relaunch, with that note
  still present. Both captures use the Android 15/API 35 AVD at 1080×2400 and
  system font scale 1.0.
- The editor showed “Note saved.” after entering the title and body. The note
  remained after relaunch and opened from the list. More → Delete → confirmation
  removed this exact QA note; Home returned to “No notes yet.” No app data was
  cleared.
- The original Cognito APK was reinstalled and the Login screen verified;
  `build/app/outputs/flutter-apk/app-release.apk` retains SHA-256
  `5E0480792576BC417B497EF61548FBD2F24B642F1AEAADD5E30BA0D563988339`.
- This adds Android behavior and layout evidence only. These captures are not
  same-viewport comparisons against Notion, and they do not cover Grid, loading,
  search, selected states, iOS, or macOS. The visual fidelity score remains
  **unassigned; the `>=95/100` gate is not proven**.
