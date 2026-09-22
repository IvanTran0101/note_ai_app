# UI Upgrade — Step 0 Baseline (2026-09-22)

Baseline before the Notion-style UI/UX upgrade (`plan.md`). No source changes were
made in this step.

## Repository state

- Branch: `note-ai-app`, HEAD `6233e168904212026ed31c5fb4214a90264b72f4`
  (matches the plan baseline).
- Working tree: only `plan.md` (and this document) untracked at baseline time.

## Command results

| Command | Result | Notes |
| --- | --- | --- |
| `flutter pub get` | PASS | 17 packages have newer incompatible versions (advisory only). |
| `dart format --output=none --set-exit-if-changed lib test` | FAIL (pre-existing) | 4 files unformatted: `lib/amplify_outputs.dart`, `test/infrastructure/ai/model_catalog_test.dart`, `test/infrastructure/device/device_info_plus_hardware_detection_web_test.dart`, `test/presentation/notes/notes_page_test.dart`. `--output=none` so nothing was rewritten. |
| `flutter analyze` | FAIL (41 issues, pre-existing) | All errors are in `packages/local_llm_bridge/test/**`: `package:test/test.dart` URI missing (dev dependency not declared for that package). This is the external blocker predicted by `plan.md` §Step 0/Step 11. |
| `flutter analyze lib/main.dart lib/presentation` | PASS | No issues found. Presentation layer is clean. |
| `flutter test` | **PASS (568 passed, 1 skipped)** | Run via the test-gate workaround below. The 10 presentation/routing regression-gate files all pass at baseline. |
| `flutter build web` | PASS | Web target does not require the native build; usable as a build gate and for visual QA. |

## Environment blockers (outside UI scope) — status

1. **C++ toolchain (RESOLVED).** VS Community 2022 "Desktop development with
   C++" workload was installed (MSVC 14.42.34433, Windows SDK 10.0.22621).
   Two environment-level workarounds were required for `native_toolchain_c`
   (no repo file changed):
   - The VS install root `D:\visual studio` contains a space and breaks
     `native_toolchain_c`'s unquoted command construction. A junction
     `D:\vs -> D:\visual studio` was created and the installer registration
     (`D:\visual studio cache\_Instances\c5d4fb18\state.json`, backup
     `state.json.bak`) now reports `D:\vs` to `vswhere`.
   - `native_toolchain_c` 0.19.2 `run_process.dart` runs the compiler through
     `cmd.exe` (`runInShell`), hitting the 8191-char command limit on the long
     llama.cpp source list. The pub-cache copy was patched to `runInShell:
     false` (`C:\Users\meow\AppData\Local\Pub\Cache\hosted\pub.dev\
     native_toolchain_c-0.19.2\lib\src\utils\run_process.dart`). This is a
     local machine patch, not a repo change; it is lost on `pub cache repair`.
2. **`packages/local_llm_bridge/test` analyze errors.** Missing `package:test`
   dev dependency in that package. Keep as a documented blocker; do not fix
   inside UI tasks (`plan.md` forbids touching `packages/local_llm_bridge`).
3. **`packages/local_llm_bridge/hook/build.dart` Windows link defect
   (RESOLVED for tests via shim).** Even with a working compiler the hook
   cannot link `local_llm_bridge.dll` on Windows: it links without
   `advapi32.lib` (registry APIs used by ggml-cpu), emits colliding object
   files (`ggml-cpu/quants.c` vs `arch/x86/quants.c` both become
   `quants.obj`; same for `repack.cpp`), and leaves ~53 unresolved externals.
   Fixing it would modify a plan-locked package, so the **test-gate shim** is
   used instead (below).

### Test-gate workaround (shim, no repo changes)

- `packages/local_llm_bridge/lib` is copied to
  `scratchpad/local_llm_bridge_shim/lib` (identical Dart API, no `hook/`).
- `.dart_tool/package_config.json` (generated build cache) points
  `local_llm_bridge` at the shim, so the native build hook is never invoked.
- Tests run with `flutter test --no-pub` so `pub get` does not rewrite
  `package_config.json`. Any later `flutter pub get` restores the real path;
  re-apply the two-line `rootUri` edit to re-arm the shim.
- Only tests that actually load the native DLL cannot run on this machine;
  the plan's regression gate (the 10 presentation/routing files) does not.

## Available devices

- Windows desktop (`windows-x64`), Chrome 153, Edge 153.
- No Android device/emulator, iOS, or macOS runner on this machine. Native builds
  in Step 11 (`apk`, `ios`, `macos`) must be run where those toolchains exist.

## Active composition (from `main.dart`)

- `MaterialApp.router` (go_router via `createAppRouter`) with routes
  `/notes`, `/notes/:id`-equivalent detail navigation and auth/diagnostics routes.
- Active workspace path: `EmailVerificationBanner` + `WorkspaceShell` hosting
  `DashboardPage` and `NotesWorkspacePage`. `NotesPage` and `NoteEditorPanel`
  (`lib/presentation/notes/notes_page.dart`, `note_editor_panel.dart`) are
  **legacy/duplicate surfaces not on the active path** — style only the active
  path; do not delete legacy without route/test evidence (plan §3.2).
- `NoteDetailPage` is used in two hosts: pushed route from `DashboardPage`
  (`_openNoteDetail`) and embedded in `NotesWorkspacePage` (`onEmbeddedExit`).

## Save contract snapshot (`NoteDetailPage._buildSurface`)

- `_canSave => !_actionBusy && (_note == null || _isDirty)`.
- Autosave: 3 s debounce after every edit (`_autosaveDelay`), immediate save on
  focus loss of both fields, rescheduled when a save completes while still dirty.
- `_save()` (create/rename/replaceContent) is fully wired and reachable from:
  autosave, focus-loss save, and the back-confirmation "Save" decision.
- **Baseline UI anomaly (plan §1.3):** `_buildSurface` passes `canSave: false`
  and `onSave: null`, so `NoteDetailActionBar` never renders the Save button
  (`if (onSave != null)`). The rendered baseline is therefore **autosave-only**,
  with manual save reachable only through the back-confirmation dialog.
- Dirty guard: `NotesWorkspacePage._selectNote`/`_startNewNote` block switching
  while `_detailDirty` (message `unsavedChanges`); back confirmation
  (save/discard/cancel) via `showNoteDetailBackConfirmation`; delete always via
  `showNoteDetailDeleteConfirmation`. PopScope gates embedded and route exits.
- `NoteDetailRouteResult` reasons observed: `saved`, `deleted`, `discarded`,
  `cancelled`; `_handleDetailExit` updates the list accordingly.

## Key/semantics contract to preserve

- `note-detail-title-field`, `note-detail-content-field`, `note-detail-summary`,
  `note-detail-dirty`, `note-detail-more-delete`, `note-detail-delete`,
  `note-detail-back`, `note-detail-scroll` (plus `note-detail-save`,
  `note-detail-summarize`, `note-detail-more`, `note-detail-error`,
  `note-detail-status`, `note-detail-progress` used by the action bar/form).
- `notes-workspace-loading`, `notes-workspace-detail-empty`,
  `responsive-notes-{compact,medium,expanded}-surface`,
  `responsive-notes-{list,detail}-pane`.
- `workspace-nav-dashboard`, `workspace-nav-notes`, `workspace-sidebar`,
  `workspace-navigation-rail`.
- `dashboard-search-field`, `dashboard-search-toggle`, `dashboard-create-note`,
  `dashboard-content`, `open-settings`, `open-diagnostics`.
- Live regions: dirty text, error, status, loading progress.

## Responsive baseline

- Breakpoints: `<600` compact, `600–839` rail/list-detail, `>=840` sidebar.
- Sidebar `248dp`; list `320dp` medium (280–320 proportional), `336dp` expanded.
- Note detail page content constrained to `maxWidth: 760` with `16/16/16/24`
  padding.

## Typography baseline

- `main.dart` sets `fontFamily: 'Inter'` with fallback `Roboto, Arial, monospace`,
  but `pubspec.yaml` declares **no font assets** — the effective runtime font is
  the platform fallback. Confirm per platform in Step 2 and either bundle Inter
  (needs an allowlist exception for `pubspec.yaml`/assets) or standardise on the
  fallback and record it in the visual diff.

## Regression gate baseline

The 10 presentation/routing test files listed in `plan.md` §3.4 are the gate for
every step. **Baseline result (2026-09-22): all pass** — full suite `flutter
test --no-pub`: 568 passed, 1 skipped (the skip is a native-DLL smoke test that
cannot run under the shim). Every step must keep `flutter test --no-pub`
green (shim active) plus `flutter analyze lib/main.dart lib/presentation`.
