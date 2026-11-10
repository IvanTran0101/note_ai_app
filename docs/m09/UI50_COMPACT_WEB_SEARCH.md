# UI50 — open Web Search as a modal at compact widths

29 October2026. This is a Web presentation checkpoint. Whole M09 remains PARTIAL;
Web>=95% and Android>=95% visual similarity remain UNVERIFIED.

## Reference and change

Actual Notion Web Search opened from390x900 twice as a modal at[0,81,390.4,700].
Its600px inner grid clips horizontally. NoteFlow now uses its existing responsive
modal at every embedded Web width, retaining safe available-width content.
Native phones retain the existing bottom-docked Search. Standalone routes,
query/filter/sort/access/controller/callbacks/persistence are unchanged. No new
feature, dependency, config or permission is introduced.

The new Chrome integration case failed before the fix because no overlay existed.
Production changes one presentation condition in DashboardPage.openSearch.
The old dock case is now native-only and has explicit Web replacement coverage;
the native landscape one-field/query/scroll/Clear assertions remain unchanged.

## Verification

- Chrome2/2: new initial390px modal, results/no-match/Clear,390->1280->390x420,
  one persistent field/query, Close/reopen/barrier dismissal; existing desktop
  dialog continuity. ui50-search-chrome63.log. Actual red evidence is
  ui50-initial-narrow-red63.log, not a compilation failure.
- VM3/3: compact dock, native landscape with IME and existing desktop dialog.
  ui50-native-continuity-vm63.log. Strict source/test2 paths clean.
- Build63 Web56.5s/APK28.7s;1079 runtime paths, fingerprint
  `f2ba7acb9f0c07083f4a5aa58560522652a9f99debabbfaa7af042969f85f19c`, drift[].
  Existing Kotlin plugin migration warning remains. APK artifact SHA256
  `907b17ddc469a615e4b3acea29b5489ca9798ed6b3a3e5199057c6ac04462430`.
  APK63 was built, not installed; actual native62 evidence belongs to UI49.
- Installed Chrome fetched21,462,180 bytes with matching packaged SHA256
  `fdf8c5d19e2f2b38e44e7987e7434aa6bc0b4939044417ed7a3218f03e4994f9`.
  Initial390x920 viewport has900px product area after the20px dev strip;
  popup y101,height700 matches reference y81 after that offset.
- Actual Chrome63: one field; resize1280x920 and390x440 preserves full query;
  body Clear104.56x48px remains visible, Clear empties query, sequential typing,
  Close/Escape/reopen and outside click checked. Dismissal verified after the
  animation, not an immediate stale field count. ui50-web63-runtime.json.
- Real Light/Dark narrow modal captured. Theme changed via existing menuitem
  controls and restored to Light. Zero captured page errors in both sessions.

## Limits and next UI work

Host free RAM fell to~200MB while two QA emulators and native compilation were
running. Notion reference app ANR persisted after restart. Both owned emulators
were gracefully closed without wiping data; free RAM recovered to~6GB. Schedule
one emulator at a time after builds. Native62 font/rotation/nav had been restored
before closure. A new actual63 Android check is not claimed.

The Chrome control kernel timed out waiting for a text-only locator in the theme
menu, resetting its owned browser. Reopened the same retained profile, confirmed
Light, then used observed menuitem roles successfully for Dark/Light inspection.
Earlier Search receipt remains; no lost verification is silently reconstructed.
The initial static-server reload raced startup and was refused; retry after
server readiness fetched the exact bundle. No product connection-error diagnosis.

Next is Settings, using actual Notion Preferences measured1280x920: panel912x820
at304,50; title26/32/w600, subtitle16/24, section16/24/w500, label14/20/w500 and
helper13/18. Use only existing settings. The IAB tab later reported unavailable
browser control after the user resumed; its earlier captured geometry is valid,
but closing/resetting that reference tab could not be confirmed. No preferences
were changed there. Existing UI51 ref crop excludes account sidebar.

Graph transport remains closed; exact current page/content/dialog/test source
was read after failed graph/index/coverage calls. No exhaustive graph claim.
No new subagent this checkpoint;21 actual workers across the continuing task.
Root owns implementation, integration, review, runtime checks and publication.

## Closure receipt

| Record | Resolution |
| --- | --- |
| MUST_REMEMBER.md | UI50 evidence and UI51 next, both95% gates open. |
| CURRENT_WORK.md | Source/build/runtime, resource scheduling and next action. |
| VISUAL_REVIEW.md | Scoped Web result, no whole-platform percentage. |
| AGENT_IMPLEMENTATION_20261019.md | Not needed: same reviewed21 deliveries, no new delegation. |
| ui43/LIVE_REFERENCE.md | Not needed: same direct390px ref already recorded; result lives here. |
| _agent_ops/* | Not needed: session tool/runtime records absent. |
