# Resume the low-end Android study

Branch: `Note-ai-app-ver2`.
Base: `note-ai-app` commit `a874e517dfc61dfadb04378f82d666b9472871c0`
(28 September 2026). Prepared 22 October 2026.

## RAM selection policy

The production catalog now configures the existing `ModelSelectionPolicy`:

| OS-reported physical RAM | Eligible model, subject to platform/OS/ABI gates |
| --- | --- |
| Below 2 GiB, or unknown | Neither production model passes the RAM gate |
| At least 2 GiB and below 6 GiB | Gemma 3 1B IT Q4_K_M |
| At least 6 GiB | Gemma 4 E2B IT Q4_0 wins by higher priority |

These values apply the historical small/big test's 2/6 GiB policy to the real
catalog at the user's request. They are selection-policy values stored in the
existing `estimatedPeakMemoryBytes` field, not measured peak-memory results or
guarantees of model fit. The plugin supplies physical RAM in MiB, and the
adapter converts it to bytes. Storage thresholds remain unset.

The vivo 1915 (PD1934F_EX), Android 12, MT6768, arm64-v8a reports
5,886,804 KiB in `/proc/meminfo` (about 5.6 GiB). Its RAM snapshot should
select Gemma 3. This still requires observation through the installed revised
app. The Xiaomi 13T's detected RAM, selection, and inference remain pending.

Both automatic model descriptors retain context 4096 and maximum final output
512 tokens. CPU thread selection and native runtime are unchanged. No automatic
retry with a smaller model was added.

## Clone and prepare

Use a short destination path on Windows; long source paths previously exceeded
the Windows native compiler command length.

```powershell
git -c core.longpaths=true clone --branch Note-ai-app-ver2 --single-branch https://github.com/IvanTran0101/note_ai_app.git C:\src\nf
cd C:\src\nf
flutter --version
flutter pub get --enforce-lockfile
Push-Location packages/local_llm_bridge
dart pub get
Pop-Location
flutter analyze
dart tool/verify_ram_selection.dart
flutter test --reporter expanded
```

This laptop used Flutter 3.47.3, Dart 3.13.3, Java 17,
Android SDK platform 36, build-tools 36.0.0, and NDK 28.2.13676358.
Record actual tool versions on the next host. The existing Amplify deployment
configuration is retained. Use Cognito authentication for the normal APK so
registration and login work; on-device AI does not require local-auth mode.

Verification on this laptop: full static analysis passed; the direct production
RAM-policy checks passed 8/8, including the measured vivo RAM snapshot and exact
threshold boundaries. The Android ARM64 release build passed. Both the full
Flutter test command and a targeted browser-test attempt stopped before test
execution because the Windows native compiler invocation splits the installed
`C:\Program Files (x86)\...` path (`'C:\Program' is not recognized`). This is
the previously observed native Windows build-hook issue; a full regression-suite
pass is still pending. The direct RAM checks do not load the native model.

## Build and install

Connect and unlock the phone, enable USB debugging, and accept its debugging
authorization prompt. Verify that `adb devices -l` reports one authorized device.

Normal release build, with evidence instrumentation disabled by default:

```powershell
flutter build apk --release --target-platform android-arm64 --dart-define=NOTEFLOW_AUTH_MODE=cognito
adb -d install -r build/app/outputs/flutter-apk/app-release.apk
adb -d shell am force-stop com.example.note_ai_app
adb -d shell am start -W -n com.example.note_ai_app/.MainActivity
```

Registration and login require internet access to the configured Cognito backend.
`NOTEFLOW_AUTH_MODE=local` is only for account-free AI measurements: it starts a
demo session without an authentication service, so registration and login cannot
work after signing out. `adb install -r` preserves existing app data and models
when both APKs use the same signing key. A different signing key prevents an
update; removing the old app deletes its local notes and downloaded models.
Back up needed data and obtain the owner's approval before removing it.

The release dependency graph now includes the explicit Error Prone and JSR-305
annotation classes required by R8. This addresses the observed missing-class
release failure without globally suppressing R8 warnings.

### Authentication verification, 29 October 2026

An ARM64 release built from `d44770f9629c8bbc47fe988f43f638a91d6e9420`
with `NOTEFLOW_AUTH_MODE=cognito` was installed and launched on the Xiaomi 13T
(`23078PND5G`). The owner confirmed authentication works after installation.
The previously installed APK used the local demo bootstrap, which cannot
register or authenticate accounts.

`dart analyze lib` passed and the Android release build passed. Existing
authentication tests stopped before execution at the Windows native build-hook
compiler-path quoting issue described above. AI inference and RAM-selection
benchmarks were not rerun during this authentication check.

## Optional measurement build

Tracing is opt-in. It logs stage timings and, only for a named diagnostics run,
raw fixture prompts/outputs as base64. Use generic test fixtures only.

```powershell
flutter build apk --release --target-platform android-arm64 --dart-define=NOTEFLOW_AUTH_MODE=local --dart-define=NOTEFLOW_EVIDENCE_TRACE=true
```

Open the existing local-AI diagnostics page from workspace navigation. Only a
trace-enabled build starts the test endpoint, bound to device loopback port
8765. ADB forwarding makes it accessible from the test host:

```powershell
adb -d forward tcp:8765 tcp:8765
```

The endpoint calls the existing app summarization callback and native worker:
`GET /status`, `POST /note`, `POST /summarize`, `POST /cancel`.
For note/summarize, send UTF-8 JSON with `run_id` and `note`.
Remove the forwarding after testing: `adb -d forward --remove tcp:8765`.

Frame evidence requires a separate profile build with both
`NOTEFLOW_EVIDENCE_TRACE=true` and `NOTEFLOW_EVIDENCE_FRAMES=true`.
Record callback batches and delivery phase; Flutter's frame timestamp origin
must not be assumed to equal wall-clock time. Do not pool profile and release
latencies. The measured service duration ends before the text reveal animation.
Worker-isolate load events may have an empty run ID; associate them using the
process/log sequence and surrounding client-load events.

## Evidence and pending work

The baseline profile APK installed and launched on the physical vivo. A generic
note saved. Original automatic selection started the Gemma 4 download; it was
cancelled at the user's request before completion, and staging cleanup was
observed. This was not a model loading failure or a completed inference run.

The earlier provisional 7 GiB build is installed on the phone. Rebuild/install
this 2/6 GiB version before collecting its results. No Gemma 3 download,
checksum, runtime load, or real summary has yet been measured for this policy.

The generic_roles_v2 corpus and pristine CSV templates are under
`docs/testing/low_end_android/`. Copy templates into a separate results folder
before filling them. See the checklist there for the full protocol.

Keep first download, artifact verification, runtime loading, the first summary
after process restart, and warm reuse separate. OS file caches may remain warm
after a process restart. Capture raw logs and failed attempts; never substitute
expected results for observations. Do not report token counts or token speed
that the native API does not expose.

Use `adb shell dumpsys meminfo --local com.example.note_ai_app` for memory
sampling: omitting `--local` caused repeated explicit GC on this phone and
disturbed the first download observation. Document actual sample intervals.

Physical phone testing is paused. The original Word/PDF report update and final
results ZIP remain pending until actual measurements are collected. iOS,
higher-end phone results, and independent human quality reviews remain pending.
