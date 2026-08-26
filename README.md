Cross-Platform Note AI

Cross-Platform Note AI is a Flutter/Dart note-management application developed in
two connected phases:

1. **Midterm Essay:** an evidence-based Flutter demonstration of on-device AI for
   note summarization and grounded question answering.
2. **Final Project:** a full cross-platform note product with account management,
   note organization, protection, sharing, offline synchronization, and AI.

This README describes the approved target architecture and roadmap. It does **not**
claim that every planned feature, provider, benchmark, or platform is already
implemented. Update it as the codebase becomes runnable.

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

## Setup and release checklist

The actual Flutter/Dart version, backend technology, model assets, environment
variables, supported platforms, deployed URL, and native artifact name are
implementation-dependent. Add exact tested values here before delivery; do not
guess them.

The Final README must include verified commands equivalent to:

~~~bash
flutter pub get
flutter analyze
flutter test
flutter test integration_test
flutter run -d chrome
flutter build web
flutter build <selected-native-target>
~~~

Also document:

- Flutter/Dart versions and required native toolchains.
- Environment template and backend setup without secrets.
- Supported platforms and real platform-specific fallbacks/limitations.
- Backend/hosting, security rules/server-side authorization, migrations/indexes,
  local-persistence, and synchronization strategy.
- Midterm model acquisition/licence/storage steps.
- Public Web URL, native artifact, grading accounts/sample data, and repeatable
  test/build commands.

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
