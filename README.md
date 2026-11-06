Cross-Platform Note AI

Cross-Platform Note AI is a Flutter/Dart note-management application developed in
two connected phases:

1. **Midterm Essay:** an evidence-based Flutter demonstration of on-device AI for
   note summarization and grounded question answering.
2. **Final Project:** a full cross-platform note product with account management,
   note organization, protection, sharing, offline synchronization, and AI.

The architecture and roadmap below describe both current work and planned
features. They do **not** imply that every feature or platform has been verified.
For the Android submission, start with [Setup and submission](#setup-and-submission).

## Goals

The project uses one Flutter project and shared Dart code for its Flutter Web
release and at least one native release. It makes a note application practical
first, then makes AI behavior visible, testable, and explainable.

Midterm proves useful AI can run locally and offline. Final extends the product
into a secure, synchronized, multi-user note-management application. Its intended
AI direction is DeepSeek through a backend, keeping provider keys out of both the
mobile and Web clients.

## Scope by phase

| Phase | Primary outcome | AI implementation |
| --- | --- | --- |
| Midterm / Essay | Research-quality Flutter demo with technical evidence | Local, offline inference using llama.cpp and GGUF models |
| Final Project | Complete note-management product on Web plus native | DeepSeek via secure backend; local Midterm path remains on-device evidence |

### Midterm: local AI investigation

The Midterm is focused on:

- Concise summary for a note.
- Natural-language QA grounded in note content, with source references.
- Offline on-device inference, not a remote API call.
- llama.cpp with GGUF. Start feasibility with Gemma 1B 4-bit on the Samsung Galaxy
  A05s reference device (4 GB RAM); compare/validate Gemma 2B 4-bit on a more
  capable device when feasible.
- Hardware-aware model recommendation, one-time provisioning, validation or
  downgrade, and persisted configuration.
- Local RAG: normalize -> chunk -> embed -> local vector index -> retrieve ->
  grounded prompt -> answer + sources.
- Evidence: load success/time, time to first token, tokens/sec, peak memory,
  crash/OOM, retrieval latency, Recall@K/Precision@K, answer quality,
  groundedness, citation correctness, and failure paths.

~~~text
Note changed
  -> normalize -> chunk -> embed -> local vector index

Question
  -> embed -> retrieve Top-K eligible chunks -> grounded prompt
  -> llama.cpp / GGUF -> answer + source references
~~~

Long notes require a deliberate strategy, such as direct summary for short notes
and chunk-summary-merge for long notes. QA must return insufficient-information
when the sources do not support an answer. The UI must show download,
initialization, inference, cancellation, errors, and unsupported-device outcomes
without blocking interaction.

### Final: product requirements

Final moves the priority from AI research to a robust note product:

- **Account management:** registration, verification/activation, login/logout,
  password reset/change, profile/avatar, and persisted preferences.
- **Simple notes:** shared create/edit screen, debounced autosave with feedback,
  grid/list preference, search, labels, sorting, pinning, delete confirmation,
  and validated attachments.
- **Protection and sharing:** per-note password protection, secure password
  representation, backend-enforced access, sharing with registered users,
  read-only/edit permissions, revocation, Shared With Me, and real-time
  collaboration for editable notes.
- **Offline-first data:** cached loaded notes, durable offline edits,
  pending/failed-sync feedback, reconnection retry, account-isolated local data,
  and a documented conflict strategy.
- **AI:** regenerable note summary and grounded QA. Retrieval only considers
  authorized notes. Protected notes remain excluded until explicitly unlocked.
  Source references open the actual note.

The Final requires at least three meaningful unit tests, three meaningful widget
tests, and one meaningful integration test. Web and native releases must expose
the mandatory core functionality from the same Flutter project.

## Architecture

The project uses a light, layer-first DDD-inspired design. It favors clear
boundaries and feature growth over needless interfaces or classes.

~~~text
Presentation
    -> Application
        -> Domain

Infrastructure
    -> implements Domain / application ports

main.dart / composition root
    -> wires infrastructure implementations
~~~

**Domain never depends on Infrastructure.** Database, device information, backend,
model runtime, and provider SDKs are implementation details. They implement
contracts defined inward.

### Layer boundaries

| Layer | Owns | Does not own |
| --- | --- | --- |
| Presentation | Flutter screens/widgets, UI state/controllers, navigation, user feedback | SQL, HTTP, AI/model SDKs, business rules |
| Application | Use cases, orchestration, DTO mapping, authorization/transaction coordination | Widgets, persistence implementation, model runtime |
| Domain | Entities, value objects, invariants, business concepts, repository/capability contracts | Flutter, database, HTTP, native APIs, AI runtime |
| Infrastructure | Database/backends, device/native adapters, model provisioning/runtime, adapter implementations | Presentation behavior or business policy |

### Modules and ownership

#### Notes

**Note** is the core aggregate root. It manages its state and invariants; it does
not save itself, run AI, or map itself to UI data.

**INoteRepository** is a persistence contract. Its implementation belongs in
Infrastructure. **NoteManager** is optional and only justified for domain rules
that cannot belong to Note; ordinary CRUD does not need it.

#### Note Intelligence

Note Intelligence extends the Note domain and is not a generic chatbot.

~~~text
Note -> INoteSummarizationService -> Summary

Question + selected notes
  -> IQuestionAnsweringService
  -> Answer + SourceReference
~~~

Summary is a value object. It does not contain runtime paths or model metadata.
AI contracts describe what the application needs; Infrastructure chooses how to
perform it.

#### Local AI infrastructure

~~~text
First launch / re-provision
  DeviceCapabilityService
    -> ModelSelectionPolicy
    -> ModelProvisioningService
    -> download, verify, store, warm-up
    -> AIConfigurationStore
    -> Ready / downgrade / failure

Normal summary
  NoteSummaryAppService
    -> INoteSummarizationService
    -> LocalSummarizationService
    -> LocalLLMRuntime / LlamaCppAdapter
    -> selected GGUF model
~~~

The runtime loads a model, generates output, and releases memory. It does not know
Note, Summary, DTOs, or device-selection policy. Hardware data, native APIs,
selected model, downloads, file paths, and runtime configuration all belong to
Infrastructure.

Persist model/version/path, device tier, and initialization state using
**AIConfigurationStore**. Handle insufficient storage, interrupted/corrupt
downloads, missing/incompatible models, memory pressure, cancellation, and
unsupported devices.

### Final AI evolution

The AI capability remains stable while the implementation changes:

~~~text
                    Domain/application AI contract
                                  ^
                                  |
Midterm: LocalAiProvider --------+------> llama.cpp + GGUF on native device

Final:   RemoteAiProvider -------+------> Backend API -> DeepSeek
~~~

The backend holds the DeepSeek credential, performs server-side validation/rate
limits, and returns safe application responses. Provider keys never enter Flutter.
This backend route is the compatible Final AI strategy for Flutter Web. The local
GGUF route remains Midterm evidence for on-device/offline AI and must not be
silently claimed as equivalent in every browser.

## Folder structure

Organize by architectural layer, then capability. Add a folder only when it has
real code.

~~~text
lib/
├── presentation/
│   ├── notes/
│   ├── note_intelligence/
│   ├── auth/                    # Final
│   ├── sharing/                 # Final
│   └── common/                  # UI-only code
├── application/
│   ├── notes/
│   │   ├── contracts/
│   │   ├── dto/
│   │   └── services/
│   ├── note_intelligence/
│   │   ├── summary/
│   │   └── question_answering/  # Final
│   ├── auth/                    # Final
│   ├── labels/                  # Final
│   ├── sharing/                 # Final
│   ├── protection/              # Final
│   └── sync/                    # Final
├── domain/
│   ├── notes/
│   │   ├── entities/
│   │   ├── value_objects/
│   │   ├── contracts/
│   │   └── services/
│   └── note_intelligence/
│       ├── summarization/
│       └── question_answering/  # Final
├── infrastructure/
│   ├── shared/
│   │   ├── ai/
│   │   ├── database/
│   │   ├── network/
│   │   ├── storage/
│   │   └── platform/
│   ├── notes/
│   ├── note_intelligence/
│   ├── auth/                    # Final
│   ├── sharing/                 # Final
│   └── sync/                    # Final
└── main.dart
~~~

**infrastructure/shared/** is only for technical blocks reused by two or more
infrastructure features. Do not add a top-level **shared/** folder. Decide the
owner of any genuinely generic cross-layer utility explicitly rather than hiding
it under Infrastructure.

## Dependency rules

| From | Allowed dependencies | Forbidden dependencies |
| --- | --- | --- |
| Presentation | Application and presentation-only code | Infrastructure, database/backend/runtime SDKs |
| Application | Domain and application contracts/DTOs | Widgets, concrete infrastructure |
| Domain | Dart-only domain code | Flutter, persistence, network, files/platform APIs, AI SDKs |
| Infrastructure | Domain and inward ports it implements | Presentation |
| Composition root | All layers for dependency wiring only | Business workflows |

Use contracts only at meaningful boundaries: repositories, AI providers, vector
stores, synchronization gateways, and clocks isolate concrete external
dependencies or make tests deterministic. Avoid interfaces with no implementation
choice or testing value.

## Coding conventions

- Dart files use lower_snake_case; types UpperCamelCase; members lowerCamelCase.
- Keep current contract naming consistent: **INoteRepository** and
  **INoteSummarizationService** style names for comparable inward ports.
- Prefer immutable DTO/value objects and explicit state/failure types.
- Map data at boundaries: UI state <-> application DTO <-> domain model <->
  infrastructure data model.
- Define cancellation, timeout, retry, and visible state for long-running work.
- Isolate platform code behind Infrastructure adapters and preserve Web compilation.
- Evaluate package maintenance, licence, native/Web support, offline behavior, and
  secret handling before adoption.
- Keep the project formatted, analyzer-clean, and covered by meaningful tests.
- Do not invent benchmark values, completed features, or compatibility claims.

## Roadmap

| Milestone | Focus | Exit evidence |
| --- | --- | --- |
| M1 | Feasibility | 1B GGUF runs on A05s, or a documented go/no-go decision |
| M2 | Flutter/native bridge | Flutter receives a local model result |
| M3 | Hardware-aware provisioning | Selection, validation/fallback, and persisted configuration |
| M4 | Summary | Usable offline summary with long-note strategy and measurements |
| M5 | Retrieval | Local semantic retrieval with a measured dataset |
| M6 | Local RAG QA | Grounded answers and clickable sources |
| M7 | Midterm evidence | Benchmarks, failure cases, screenshots, methodology, limitations |
| M8 | Midterm delivery | Clean reproducible demo/report and oral-exam readiness |
| M9 | Final core | Auth, notes, autosave, labels, search, pinning, adaptive UI |
| M10 | Offline and security | Local data, sync states, conflict policy, protected notes |
| M11 | Sharing and authorization-aware AI | Permissions, collaboration, authorized retrieval, backend enforcement |
| M12 | Final release candidate | Web/native integration and automated tests |
| M13 | Final delivery | Web URL, native artifact, demo evidence, reproducible repository |

## Validation and evidence

### Midterm

Record device and platform conditions before interpreting results. Test model
loading/warm-up, memory pressure, cancellation, missing/corrupt model, inadequate
storage, and airplane-mode operation. Test summary inputs of varied lengths and
the RAG pipeline with a curated question/note dataset, different chunk sizes,
Top-K values, and insufficient-information cases.

### Final

Demonstrate shared Web/native core behavior, auth, note create/edit/autosave,
attachments, search, labels, pinning, accessible UI states, offline edit ->
reconnect -> sync, locked-note/security enforcement, and sharing permissions.
Demonstrate at least one AI workflow on both submitted platforms. QA demonstrations
must include source navigation.

## Setup and submission

### Scope and prerequisites

The submission build below targets a physical **64-bit ARM Android device**.
The checked-in app uses the configured AWS Cognito user pool for accounts and a
local llama.cpp/GGUF model for note summaries. The app downloads the model after
the user agrees. Authentication and the first model download require Internet;
local inference runs on the device once the model is available. The APK does not
contain the model weights.

The mobile catalog currently contains these pinned models:

| Model | Artifact size | Configured RAM selection threshold | Source and license |
| --- | ---: | ---: | --- |
| Gemma 3 1B IT Q4_K_M | 0.75 GiB | 2 GiB | [ggml-org/Gemma 3 GGUF](https://huggingface.co/ggml-org/gemma-3-1b-it-GGUF) |
| Gemma 4 E2B IT Q4_0 | 3.12 GiB | 6 GiB | [Google/Gemma 4 GGUF](https://huggingface.co/google/gemma-4-E2B-it-qat-q4_0-gguf) |

These thresholds are selection rules, not measured peak-memory guarantees.
Check the linked model pages for their licenses and access conditions. After
consent, the app downloads the selected artifact to app-private storage and
verifies its size and SHA-256 before loading it.

The following setup was used to build and check commit `0518d70af`:

- Flutter **3.47.1**, Dart **3.13.1**, Java **17**.
- Android SDK platform **36**, build-tools **36.0.0**, NDK **28.2.13676358**;
  the Android emulator/build toolchain may also require CMake **3.22.1**.
- Git and Internet access to resolve packages. Optional backend development uses
  Node.js/npm; the local typecheck was run with Node **26.7.0** and npm **11.19.0**.

Install [Flutter](https://docs.flutter.dev/get-started/install), an Android SDK
through [Android Studio or the command-line tools](https://developer.android.com/studio),
and a JDK. Run `flutter doctor -v` to check the installed toolchains and
`flutter doctor --android-licenses` to review Android SDK licenses. Use the SDK
manager to install the platform, build-tools, NDK and CMake versions above if
they are missing.

### Download project dependencies

Clone the submission branch, or extract the submitted source ZIP:

~~~bash
git clone --branch Note-ai-app-ver2 --single-branch https://github.com/IvanTran0101/note_ai_app.git
cd note_ai_app
~~~

If using a ZIP, enter the extracted project directory instead. From the
repository root, on macOS/Linux or in a compatible shell:

~~~bash
flutter pub get --enforce-lockfile
(cd packages/local_llm_bridge && dart pub get)
~~~

The root `pubspec.lock` pins the app's resolved Dart packages. The nested
`local_llm_bridge` package has its own development dependencies and intentionally
does not track a lockfile; its `dart pub get` resolves them separately. The
bridge builds the vendored llama.cpp source under `packages/local_llm_bridge/third_party`;
keep that source and its license in the submission.

The checked-in Flutter configuration points to an existing Cognito user pool and
sync endpoint; it is not an instruction to deploy a new backend. For a local AI
demo without accounts, `--dart-define=NOTEFLOW_AUTH_MODE=local` starts a demo
session, but registration and login are unavailable in that mode. Never commit
passwords, API keys, signing keys, or `.env` files. Backend installation is
optional when only building the Flutter app. To work on the Amplify backend in a
fresh checkout, install Node.js/npm and run:

~~~bash
npm ci
npm run typecheck
~~~

`npm ci` removes and recreates the existing `node_modules` directory; do not use
it if that directory contains local work you need to preserve.

### Run and validate

~~~bash
flutter devices
flutter analyze
flutter test
~~~

To run on a connected device, replace `<device-id>` with the identifier listed by
`flutter devices`:

~~~bash
flutter run -d <device-id> --dart-define=NOTEFLOW_AUTH_MODE=cognito
~~~

On a clean Git archive,
full `flutter analyze` passed after **both** dependency installation steps above.
If a local checkout contains ignored audit or generated files such as `output/`,
the full analyzer can report errors from those files; `flutter analyze lib test`
checks the app and tests, as the repository's CI does. The checkout audit on
6 November 2026 reported 932 Flutter tests passed and 2 skipped. The clean archive
was checked separately for dependency resolution and analysis; a clean-archive
test run and complete real-device end-to-end test remain unverified.
There is currently no root `integration_test/` directory; do not use
`flutter test integration_test` as a verified command.

### Build the Android APK

~~~bash
flutter build apk --release --target-platform android-arm64 \
  --dart-define=NOTEFLOW_AUTH_MODE=cognito
~~~

Submit `build/app/outputs/flutter-apk/app-release.apk`. The adjacent
`app-release.apk.sha1` is a text checksum, **not** an installable APK. The APK
under `build/app/outputs/apk/release/` may be another copy of the same build;
compare file hashes before assuming two artifacts are identical. For example,
on macOS:

~~~bash
shasum -a 256 build/app/outputs/flutter-apk/app-release.apk
~~~

The current Android release configuration uses the **Android Debug** signing
key. It is suitable for a local class test when accepted by the course, not a
production signing setup. Replacing an existing installation signed with a
different key can fail; uninstalling that app removes its local notes and model,
so back up required data first. The 6 November 2026 release build succeeded,
but its install, account flow, model download and summary on an Android phone
were not verified in that audit. See [Android test notes](docs/LOW_END_ANDROID_VER2.md)
for earlier device evidence and limitations.

Before submission, test the actual APK on a compatible Android phone: launch,
register or log in, create a note, accept the model download if needed, and
generate a summary. Model selection currently uses 2/6 GiB RAM thresholds, not
guaranteed device-fit measurements. The grading setup also depends on the
configured AWS deployment remaining available. Share any test account details
through the course's agreed channel, not in the repository.

### Safe dependency review and source ZIP

Inspect before removing or upgrading packages:

~~~bash
flutter pub deps --style=compact
flutter pub outdated
(cd packages/local_llm_bridge && dart pub outdated)
~~~

These commands inspect dependencies; they do not prove that a package is unused.
Review imports, build hooks, assets and platform-specific use, then rerun the
tests and Android build after any change. Do not delete the vendored native bridge
to reduce ZIP size. `flutter clean` deletes generated build outputs, including
the APK; preserve any artifact you need before using it.

Only after confirming a specific root dependency is unused, it can be removed
with `flutter pub remove <package-name>` (replace the placeholder with the
reviewed package), followed by `flutter analyze`, `flutter test`, and the release
APK build above. This command changes `pubspec.yaml` and `pubspec.lock`; review
both changes. No dependency removal is required merely to create the submission.

From a Git checkout, first commit the intended source changes, then create a
clean source ZIP:

~~~bash
git archive --format=zip --output=../noteflow-source.zip HEAD
~~~

`git archive` includes tracked files from `HEAD` only: it excludes uncommitted
changes and ignored local folders such as `output/`, `.dart_tool/` and
`node_modules/`. Check the ZIP contents and do not include local credentials,
generated caches, or the downloaded model weights. The APK is submitted
separately.

## Sources and decision authority

This README consolidates the current Notion architecture/roadmap and the course
requirements. Official requirements remain authoritative if planning documents
conflict:

- **sources/503107-Essay-V1.pdf** - Midterm: Flutter and Artificial Intelligence,
  Integrating On-device Machine Learning Models.
- **sources/503107-FinalProject-V1.pdf** - Final: Cross-Platform Note Management
  Application requirements.

If an implementation changes a contract, platform strategy, security boundary, or
benchmark claim, update this README and ensure every team member can explain the
decision in the oral examination.
