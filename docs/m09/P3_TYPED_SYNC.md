# M09.RT.P3 typed sync

2026-10-14. Source/local transport foundation accepted.
The completed editor/ref styling/actual UI scoring remains P4–P6.

## Contract and ownership

- Canonical document1 is the same strict Dart/backend golden. HTTP V3 uses
  `documentCapability: basicBlocksV1` and explicit document presence/null.
  Format-only changes fingerprint differently; derived content must match.
  Existing V1/V2 payloads/fingerprints stay unchanged for attempted retries.
- Backend authenticates/authorizes owned/shared/protected mutations through
  existing contracts. Primary/receipt snapshots carry the canonical document;
  protected/revoked feeds and AppSync invalidation events never expose it.
  Current grant/ACL checks still run; client readOnly is not authority.
- The capability probe never writes the cursor. The existing coordinator
  negotiates before choosing a backfill cursor; typed pages monotonically
  advance wire version. Same-revision plain caches/conflict remote snapshots
  can receive missing documents without overwriting pending local drafts.
- Older backends retain rich outbox/draft state and show a typed update-needed
  error. Capability recovery retries the exact rich payload/id. Frozen legacy
  body replacement against rich remote state refuses; a typed pull records an
  explicit conflict. Use cloud retains remote formatting; explicit Use local
  promotes the chosen plain draft into a typed paragraph/new mutation.
- One encrypted store/CAS/writer/outbox/cursor remains. HTTP send/session fences
  and mutation encoding are split by responsibility; no second state owner.
  Authorized content requests V3 with safe V2 fallback only for unsupported
  input version. A malformed successful V3 response is never silently trusted.
- Rich feed uses a bounded contiguous byte prefix; its cursor references the
  last returned row, including interleaved labels. Large legacy first rows
  still make progress. Existing encrypted encode/decode32MiB cap remains.

## Verification so far

Full VM1772 PASS /4 configured skips with concurrency2; installed Chrome66/66
across12 target mains, including actual IndexedDB/reseal + real local HTTP
two-actor roundtrip. Backend outside RAG145/145 across33 test files; fresh
document Node14/14 and shared Dart/backend golden PASS. Scoped client analyzer
and strict backend source/new test tsc clean.

Real local HTTP uses production adapters/use cases and local disk-backed SDK
fixture: format-only sync, reopen, share/edit, revoke mask/write refusal,
protected metadata/locked-write refusal, scoped authorized content, lock and
synthetic-note cleanup. Web/native backing is isolated from the app account
record; Web test key channel mock is distinguished from native real device
keys. Android real platform transport1/1 PASS: build409.3s, install-r1194ms,
test7s; APK SHA256
`62F63BF0635ED760435E559F693DE3704476A68CCE916FA164605EAB5606939F`.
This artifact runs the integration harness; restore main_dev for product UI.
These are transport/storage tests,
not the final human editor UI acceptance.

First broad VM had four crypto timeouts while emulator/parallel workloads ran
and three obsolete mock API contracts. Dedicated affected28/28 + fresh full
1772 passed after serializing load and updating mocks to explicit old-backend
404 or valid V3 content. An accidentally broad Node run included RAG and hit
the existing missing exact manifests; it is not a passing full-backend receipt.
No runtime defect was inferred from that missing-input gate.

## Rollout and local reproduction

Publish backend V3 capability/routes before rolling out rich cloud writes.
No AWS deployment/live acceptance or provider inference was performed here.
Missing `docs/rag/tokenizer_manifest.json` and `index_job_policy_v1.json`
remain separate gates; fabricated files are not substitutes.

Default local UI: `python tool/run_m06_local.py` (owner/recipient as before).
Opt-in transport VM:
`flutter test test/security/m09_local_transport_test.dart --dart-define=M09_LOCAL_HTTP=true`.
Start local services first with `python tool/run_m06_local.py --serve-only`.
For browser test origins only, set process-local `M09_QA_BROWSER_ORIGINS=1`
on that local server; default local dev still limits the UI origin to8776.
`tool/run_chrome_tests.py --dart-define=M09_LOCAL_HTTP=true` uses installed
Chrome and an isolated Windows SDK tools overlay. Native uses
`integration_test/m09_document_transport_test.dart` and ADB reverse8796.
All runs retain existing user/emulator data and use synthetic QA note IDs.
