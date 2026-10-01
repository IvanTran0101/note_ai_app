# Phase 4.1 — Consent and safe Summary failure boundary

Implemented on 2026-10-01 in the original project, from clean HEAD `e24dd7f`.
Changes remain uncommitted. Two DeepSeek workers implemented consent and failure
mapping; GPT-6.1 Sol High reviewed read-only; root integrated controller/main and
ran the related checks. Domain, wire contract v0.3 and policy remain unchanged.

## Application consent API

`SummaryConsentAppService` reuses the in-memory `SummaryCloudConsent` store and
live `ICurrentUser`/session generation. It exposes only these actions to UI;
its injected mutable store and callbacks remain private.

| API | Behavior |
| --- | --- |
| `state` | `unavailable`, `consentRequired`, or `granted`, derived from live state |
| `beginConsent()` | Issues an immutable request for the current account/session/consent generation and service issuer |
| `grantConsent(request)` | Synchronously validates the captured binding before granting; never substitutes a newly active account |
| `revokeConsent()` | Clears memory first, then cancels active runtime scopes through the injected callback |

Requests have no public constructor. Logout/login of the same account,
A→B→A, revoke/regrant, repeated confirmation, service recreation, and runtime
availability changes cannot grant using an obsolete request. Consent starts off
for a fresh store/session and is never persisted.

Production availability requires remote mode, valid configuration, Cognito and
an undisposed app. Confirmation captures a binding for a later disclosure UI;
Phase 4.1 does not show that UI or automatically grant permission.

## Safe failure vocabulary

The existing Application `SummaryRunFailure` now also describes generation
outcomes. `SummaryApiFailure` is translated in Infrastructure; existing run
failures retain identity and cancellation reason. Unknown synchronous or
asynchronous failures become `unexpected`, with no cause/message/raw payload in
the failure object.

- Provider unavailable → Application `serviceUnavailable`.
- API timeout → existing `deadlineExceeded`.
- Rate-limit hint is readable only for `rateLimited` and integer seconds1–3600;
  invalid hints are dropped. No automatic generation retry was added.

The frozen transport maps HTTP502 to provider unavailable; HTTP503 without a
recognized contract mapping remains `unexpected`. No wire/status change was made.

## Composition and caller behavior

- `NotesApplicationController.summaryConsent` exposes the optional Application
  service; production Dashboard detail and inline Notes use the shared wired
  controller. Legacy/test seams may leave it null.
- The existing pending `Future<String>`, completed string, cancellation scope
  and typed failure carry loading/result/cancel vocabulary; no additional event
  bus or unused UI-state holder was introduced.
- Remote runtime and the local Notes callback use the same safe failure boundary.
  Raw local Diagnostics retain their prior callback. Provisioning failed/cancelled
  notices still suppress duplicate generic Summary errors.
- Note content and derived-summary persistence behavior are unchanged.

## Verification

| Check | Result |
| --- | --- |
| 16 related Native Flutter test files | 247 passed |
| 8 related Chrome test files | 98 passed |
| `flutter analyze --no-pub` | No issues found |

Coverage includes stale confirmation/account/session/service bindings,
revoke→regrant, Application revoke of a real runtime awaiting a token with zero
HTTP sends after the late token, safe unknown failures, all API error categories,
hint bounds, snapshot/scope forwarding and local provisioning notices.

Chrome mocks inject the current source-policy bytes using the existing test
support. They do not prove actual Web app asset loading or deployed/provider
behavior. No full suite (>900 tests), real Summary provider call, deployment,
new dependency, secret, commit or push was used.

Initial validation exposed constructor privacy lints and a root-introduced
private-parameter callsite mismatch. The project requires Dart `^3.13.1`:
private initializing formals expose their public parameter names at callsites.
The final constructors need no lint suppression, and the checks above passed.

### Native command

```bash
flutter test --no-pub \
  test/application/note_intelligence/summary_consent_app_service_test.dart \
  test/application/note_intelligence/summary_run_context_test.dart \
  test/application/note_intelligence/summary_cloud_consent_test.dart \
  test/application/note_intelligence/summary_run_guard_test.dart \
  test/application/notes/note_application_test.dart \
  test/infrastructure/note_intelligence/summary_failure_mapper_test.dart \
  test/infrastructure/note_intelligence/summary_run_runtime_failure_test.dart \
  test/infrastructure/note_intelligence/summary_run_runtime_test.dart \
  test/infrastructure/note_intelligence/summary_http_gateway_auth_test.dart \
  test/infrastructure/note_intelligence/remote_summarization_lifecycle_test.dart \
  test/presentation/notes/notes_application_controller_summary_test.dart \
  test/presentation/notes/note_detail_page_test.dart \
  test/presentation/notes/notes_page_test.dart \
  test/presentation/notes/notes_workspace_page_test.dart \
  test/presentation/dashboard/dashboard_page_test.dart \
  test/presentation/sync/sync_presentation_controller_test.dart
```

## Handoff

Phase 4.1 source/mock gate passes. Phase 4.2 remains a separate implementation:
capture a request before opening disclosure, and pass that same request to
`grantConsent` only after user acceptance; Settings calls `revokeConsent`.
Dialog/Settings, availability/loading UI, specific errors/regenerate UX and
manual Web/Native acceptance are still Phase 4.2–4.5. Protected-note/unlock,
the previously unclassified broader Chrome workspace cases and live provider
evidence remain separate final-project gates.

Notion: [4.1 — Chốt consent/state boundary](https://app.notion.com/p/3ec25edc9a25819db1fcddee593b3617).
