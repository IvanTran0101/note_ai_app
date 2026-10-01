# Summary Phase 4.2–4.5 — implementation receipt

Implemented in the original project on `Final-here-do-not-merge-main`, baseline
`e24dd7f`, preserving the existing uncommitted Phase 4.1 work. Three parallel
DeepSeek workers owned disjoint UI and mock lanes; GPT-6.1 Sol High performed
read-only control review. No remaining source correctness blocker was reported.
No commit, push, deployment or real Summary/provider request was made.

## 1. Implemented behavior

- Consent disclosure and Settings switch follow the existing resolved app Language
  preference: explicit VI/EN wins, System uses the existing locale/EN fallback.
  Changing language does not change permission. Cancel grants nothing and sends
  zero requests. Allow uses the captured account/session/consent intent, rechecks
  the saved note, then dispatches. Revoke and logout invalidate active scopes.
- Availability explains draft, dirty, conflict, unauthenticated and unavailable
  runtime states. A consent-required note remains actionable. One UI run owns its
  spinner and Cancel; cancellation races cannot clear a newer run's state.
- Safe EN/VI errors, bounded manual Retry-After cooldown and new-scope regenerate
  preserve the original note and previously accepted summary. Rejected input
  stays blocked until its saved revision changes. No automatic generation retry,
  partial summary, raw payload or persisted Summary was added.
- Scoped local runs also recheck their saved revision. The existing app root holds
  one physical local inference latch until its promise finishes, even after UI
  cancellation/page changes. Local cancellation discards output, without claiming
  to force-stop inference. Remote abort cannot retract content or guarantee no cost.
- A newer same-identity saved DTO received while editing stays pending; reverting
  the draft adopts that latest DTO. Account/controller changes clear old results.

## 2. Files to review

1. `lib/presentation/notes/note_summary_controller.dart`: per-run UI orchestration.
2. `summary_consent_dialog.dart`, `summary_cloud_settings_tile.dart`,
   `note_detail_localizations.dart`: pure localized copy and session consent UI.
3. `note_detail_page.dart`, `note_detail_surface.dart`, `note_detail_editor_form.dart`,
   `note_summary_availability.dart`, `note_summary_feedback.dart`: editor integration.
4. `lib/main.dart`, `lib/application/notes/note_application.dart`,
   `lib/application/note_intelligence/summary_consent_app_service.dart`: app composition,
   local latch and derived runtime availability; Domain/wire/policy are unchanged.
5. `tool/summary_phase4_mock.dart` and `lib/dev/summary_phase4_mock_*.dart`: offline
   real-root smoke fixture, memory stores, fake auth and intercepted HTTP only.
   This entrypoint bypasses Cognito bootstrap and explicitly disables sync,
   regardless of endpoint compile flags. Production `main()` never imports it.

## 3. Reproduce the offline app

```sh
flutter run --no-pub -d chrome -t tool/summary_phase4_mock.dart
```

Use only the seeded synthetic Mock note. Overlay modes: ready, delayed,
rateLimited, providerUnavailable, invalidOutput and unauthorized. The counter
shows transport sends and `Policy: bundled (loaded)` after generation. This tool
uses the real `SummaryRequestPolicy.load` asset loader; Chrome unit tests inject
source-policy bytes through the existing helper and are separate evidence.

For the native local latch fixture:

```sh
flutter run --no-pub -d macos -t tool/summary_phase4_mock.dart \
  --dart-define=NOTEFLOW_MOCK_LOCAL_SUMMARY=true
```

## 4. Verification and limitations

- 22 related Native test files: **287 passed**. Full >900 test suite was not run.
- 21 focused Chrome files: **259 passed, 1 intentional Native-only skip**. The
  workspace file with the two baseline failures was kept outside this passing set.
- Final analyzer: clean. Formatting and `git diff --check` checked.
- Offline mock Web release build passed, including Wasm dry-run; iOS simulator
  debug unsigned final rebuild passed (23.5s). No installed dependency change.
- Actual served Web and iOS simulator UI: decline/accept, real bundled policy,
  spinner/Cancel, failed regenerate retaining accepted summary and original note.
  Web VI disclosure follows Settings preference; Settings revoke confirmed on both
  surfaces, native logout returns to sign-in. Restart-off/relogin-off and late
  result rejection have focused tests; manual native relogin was not completed
  because the simulator text-entry automation did not populate its email field.
- Initial Web debug/release focus failures were traced to the **mock fixture**:
  app and overlay were siblings without a common Directionality, and root
  ReadingOrder traversal accessed group geometry before layout. The fixture
  now wraps the whole Stack in shared LTR Directionality and native Flutter
  WidgetOrderTraversalPolicy. No production focus policy or SDK was changed.
  Fresh debug and rebuilt release: **zero new console errors** through startup,
  decline/allow, delayed cancel, provider failure and manual rate-limit cooldown.
  The counter stays4 when cooldown ends; no automatic generation retry.
  The tool prints full diagnostic errors with forceReport:true, without suppression.
  Native final build/restart also shows0HTTP and asks for new consent. Native
  relogin remains test-covered rather than manually completed; this is the only
  manual authentication evidence limitation, not an untested session reset.
  SDK: Flutter3.47.1 stable (6655482ec0), Dart3.13.1.

### Pre-existing Chrome workspace failures

Two isolated Chrome cases FAIL on archived `e24dd7f` with a byte-identical
`notes_workspace_page_test.dart`:

1. `wide editor back keeps dirty changes behind confirmation`
2. `discarding a draft preserves the unsupported storage state`

Commands: `flutter test --no-pub --platform chrome --reporter expanded
 test/presentation/notes/notes_workspace_page_test.dart --plain-name '<case>'`
in the isolated baseline. Logs are `/tmp/summary-phase4-baseline-case-a.log` and
`...-case-b.log`. The test runner exposes no detailed exception, so the cause is
**unclassified**, not a confirmed focus/autosave diagnosis. Owner: Notes workspace
and Web test harness. These cases are not counted as passing Summary Chrome
acceptance, and unrelated workspace implementation was not changed to hide them.

## 5. Gate

Source implementation is complete with focused mock evidence. This is not a
claim that the whole final project is DONE. The mock Web fixture focus problem
is resolved; the pre-existing workspace Chrome cases and manual relogin evidence
limit are recorded above. Live provider/deployment/disclosure
review belongs to Phase 5. AIS-FR-05 protected/unlock model remains mandatory and
absent; contract v0.3 does not authorize protected-note transmission. No new
persistence, dependency, event bus, streaming or runtime selector was introduced.

## Exact focused test set

Native command: `flutter test --no-pub --reporter expanded` followed by these22paths.
Chrome uses the same set except `notes_workspace_page_test.dart`; the local latch
case explicitly skips Web. Supply the current asset bytes as base64 with
`--dart-define=SUMMARY_TEST_POLICY_BASE64=<base64 of assets/summary_policy.json>`
for the existing Chrome policy test helper.

```text
test/application/note_intelligence/summary_consent_app_service_test.dart
test/application/note_intelligence/summary_runtime_availability_test.dart
test/application/notes/note_summary_snapshot_test.dart
test/infrastructure/note_intelligence/summary_failure_mapper_test.dart
test/infrastructure/note_intelligence/summary_run_runtime_failure_test.dart
test/presentation/notes/note_detail_summary_flow_test.dart
test/presentation/notes/note_summary_controller_test.dart
test/presentation/notes/notes_application_controller_summary_test.dart
test/presentation/notes/summary_cloud_settings_tile_test.dart
test/presentation/notes/summary_consent_dialog_test.dart
test/presentation/notes/summary_phase4_mock_acceptance_test.dart
test/presentation/notes/summary_phase4_mock_local_latch_test.dart
test/presentation/notes/summary_phase4_mock_settings_test.dart
test/support/summary_phase4_mock_support_test.dart
test/application/note_intelligence/summary_run_context_test.dart
test/application/notes/note_application_test.dart
test/infrastructure/note_intelligence/summary_run_runtime_test.dart
test/presentation/dashboard/dashboard_page_test.dart
test/presentation/notes/note_detail_page_test.dart
test/presentation/notes/notes_page_test.dart
test/presentation/notes/notes_workspace_page_test.dart
test/presentation/sync/sync_presentation_controller_test.dart
```
