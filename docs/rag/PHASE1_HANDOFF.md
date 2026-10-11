# RAG Phase 1 handoff — artifacts ready for review

Target: original project, final-tuankiet at b39324a. Scope approved by user:
own synced text notes only; protected/shared/attachments excluded.

## Delivered
- API contract, policy, C01–C25 registry and acceptance matrix.
- 12 synthetic notes, 24 VI/EN query cases, 44 wire/Noul/response cases.
- 4 RRF examples, 5 source-span cases, 6 injected-counter boundary cases.
- Standard-library offline oracle/checker and meaningful boundary tests.

## Verification
Run from original project root:
1. python3 -B tool/rag/check_phase1.py --root .
2. python3 -B -m unittest discover -s tool/rag -p test_phase1_contract.py

Staged bundle verification: checker PASS; 22 unit tests PASS. Root verification
receipt is recorded in phase1_receipt.json after installation and rerun.
No Flutter/backend/AWS/provider tests were run or claimed. No full >900-file
suite, SDK install, secret access, model invocation, deploy, commit or push.

## What the evidence means
Policy constants and criteria are protected against drift; fixtures and wire
guards are consistent; offline RRF/source-span examples produce expected output.
Noul probabilities/token counts are authored or injected synthetic values.
Simulated generation accounting is not actual provider call observation.
Oracle authority flags are simulated canonical facts, not a real JWT verifier.
No MMR/BM25/application/cloud runtime or provider-quality claim.

## Review required
- Wire DTO/HTTP errors and technical sizing/deadline defaults.
- UTF-16 source spans, title-prefix accounting, RRF normalization/cosine tie rules.
- Proposed canonical consent row/generation/index-readiness semantics.
- Live tokenizers, BM25 analyzer, Jev model/thresholds, n8n/IAM/retention and
  external-provider budgets remain deferred to appropriate later gates.

## Next
User reviews contract v0.1. Phase 2 may then implement mocked runtime under that
contract. Keep runtimeEnabled false and liveThresholds/liveModel null until real
provider/evaluation gates are separately met. Do not reuse Summary consent or
enable shared/protected scope without a contract revision.
