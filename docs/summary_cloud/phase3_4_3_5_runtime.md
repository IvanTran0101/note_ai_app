# Phase 3.4 + 3.5 — Per-run context and runtime composition

Implemented in the original project from HEAD `35f3269`; changes remain
uncommitted. Two DeepSeek workers implemented disjoint Application and runtime
configuration lanes. GPT-6.1 Sol High reviewed read-only; root integrated the
gateway, UI, and app composition. No full test suite was run.

## Phase 3.4 — Isolate and revalidate each run

- `SummaryRunContext` captures the selected saved `NoteDto`, account, monotonic
  session generation, consent snapshot, and a one-use cancellation scope.
- Cloud consent is in-memory, off by default, and bound to account plus session.
- Application validates the saved note and rechecks account, session, consent,
  and scope around asynchronous work before accepting/displaying a result.
- Remote guard reads account-scoped local sync state before stages and before
  HTTP dispatch. It refuses missing/deleted/changed/conflicted notes.
- Logout, account/session change, note edits (including edit then revert),
  conflict, consent revocation, and widget disposal cancel the run. Cancellation
  also races token, policy, and guarded asynchronous waits so the UI can recover.
- The HTTP gateway preserves typed cancellation across token lookup, refresh,
  body streaming, and transport errors; revalidates before initial and 401 retry
  sends.

## Phase 3.5 — Keep local and remote paths explicit

- Runtime mode comes from `NOTEFLOW_AI_MODE`; local remains the default.
- Remote endpoint comes from `NOTEFLOW_AI_API`, falling back to
  `custom.aiApiEndpoint` from Amplify outputs. Only HTTPS endpoints without
  credentials, query, or fragment are accepted.
- Unknown/missing/invalid remote configuration is represented as unavailable;
  app startup and CRUD remain usable, while Summary fails safely without local
  fallback.
- Remote mode requires Cognito and current cloud consent. Raw-text Local LLM
  debug and GGUF provisioning entry points stay local-only.
- No provider key, persisted consent, consent UI, direct DeepSeek request, or
  deployment is included. Consent settings and user-facing disclosure remain a
  later phase.

## Validation

- Related Native Flutter tests: 18 files, **318 passed**.
- Focused Dart analyzer: **No issues found** for 12 changed source files.
- `dart format`: 30 relevant source/test files checked.
- Focused Chrome tests: 14 files, **230 passed**. A broader 18-file Chrome
  attempt had two failures in `notes_workspace_page_test.dart` (navigation and
  storage); those cases do not exercise Summary, and their baseline was not
  verified. They are not counted as passing evidence.
- Full Flutter suite (>900 tests), live provider calls, secrets, deployment,
  commit, and push were not used.

## Focused Native command

```bash
flutter test --no-pub \
  test/application/auth/current_user_session_test.dart \
  test/application/notes/note_application_test.dart \
  test/application/note_intelligence/summary_run_context_test.dart \
  test/application/note_intelligence/summary_cloud_consent_test.dart \
  test/application/note_intelligence/summary_run_guard_test.dart \
  test/infrastructure/configuration/summary_runtime_configuration_test.dart \
  test/infrastructure/note_intelligence/summary_run_runtime_test.dart \
  test/infrastructure/note_intelligence/summary_http_gateway_scope_test.dart \
  test/infrastructure/note_intelligence/summary_http_gateway_test.dart \
  test/infrastructure/note_intelligence/summary_http_gateway_auth_test.dart \
  test/infrastructure/note_intelligence/summary_http_gateway_transport_test.dart \
  test/infrastructure/note_intelligence/summary_http_mapper_test.dart \
  test/infrastructure/note_intelligence/summary_http_mapper_errors_test.dart \
  test/presentation/notes/note_detail_page_test.dart \
  test/presentation/notes/notes_page_test.dart \
  test/presentation/notes/notes_workspace_page_test.dart \
  test/presentation/dashboard/dashboard_page_test.dart \
  test/presentation/sync/sync_presentation_controller_test.dart
```

## Handoff

Phase 3.4/3.5 mock implementation is ready for review. Consent defaults off,
therefore remote Summary is not user-accessible until a later consent UX phase.
Next: review this runtime boundary and approve the separate consent/UI phase;
do not add a real provider call until backend contract, auth and disclosure are
ready.
