# Phase 1 acceptance matrix
All evidence below is artifact consistency, fixture validity or an offline reference-oracle check.
No row closes its application/provider/cloud gate. A declaration check is not behavior verification.
Commands: python3 -B tool/rag/check_phase1.py --root . ; python3 -B -m unittest discover -s tool/rag -p test_phase1_contract.py

## A — Hosting, chunking và hai nhánh retrieval

| ID | Phase 1 evidence | Runtime gate | Future steps |
| --- | --- | --- | --- |
| C01 | policy hosting/safety + w-r06/w-r07 | UNVERIFIED | P3.1 / P5.4 |
| C02 | policy + budget-01/02/03 + Unicode unit tests | UNVERIFIED | P1.3 / P2.2 / P3.2 |
| C03 | policy embedding + budget-01/03 | UNVERIFIED | P1.3 / P3.2 |
| C04 | policy Top-K + q10/q11/q12 eligibility oracle | UNVERIFIED | P2.1 / P2.3 / P3.1–2 |
| C05 | policy stores/scope + local-only oracle check | UNVERIFIED | P2.2–3 / P3.3 |

## B — RRF và MMR

| ID | Phase 1 evidence | Runtime gate | Future steps |
| --- | --- | --- | --- |
| C06 | rank-01..04 + duplicate/tie units | UNVERIFIED | P1.3 / P2.3 |
| C07 | rank-03 + span-04 + q20 | UNVERIFIED | P1.3 / P2.3 / P3.3–4 |
| C08 | policy MMR constants only; normalization proposal | UNVERIFIED | P1.3 / P2.4 |
| C09 | policy reuse-vectors declaration only | UNVERIFIED | P2.4 / P3.2 |
| C10 | policy ±1/nonrecursive + span-01 overlap example | UNVERIFIED | P1.3 / P2.4 |

## C — Expansion, dedupe và ngân sách context

| ID | Phase 1 evidence | Runtime gate | Future steps |
| --- | --- | --- | --- |
| C11 | q11/q12/q20 + span-04 | UNVERIFIED | P2.1 / P2.4 / P3.4 |
| C12 | span-01/02/05 + Unicode span units | UNVERIFIED | P1.3 / P2.4 |
| C13 | q05/q16 + span-03 | UNVERIFIED | P2.4 / P4.5 |
| C14 | budget-04/05/06 injected counts | UNVERIFIED | P1.3 / P2.4 / P4.1–4 |
| C15 | policy anchors/remove-expansion-first declaration only | UNVERIFIED | P2.4 / P4.3–5 |

## D — JEV và generation

| ID | Phase 1 evidence | Runtime gate | Future steps |
| --- | --- | --- | --- |
| C16 | w-n01..14 + q01/q04/q05/q24 | UNVERIFIED | P1.4 / P2.5 / P4.1–2 |
| C17 | w-s04/06/07/09 source binding | UNVERIFIED | P1.2 / P2.5 / P4.1–5 |
| C18 | q04/05/23/24 + unset-live thresholds unit | UNVERIFIED | P1.4 / P2.5 / P4.2 |
| C19 | query outcome accounting; no network imports/calls | UNVERIFIED | P2.3 / P2.5 / P4.4 |
| C20 | w-s01..16 + gold source maps | UNVERIFIED | P1.2 / P2.5 / P4.3–5 / P5.2 |

## E — Authority, lifecycle và triển khai

| ID | Phase 1 evidence | Runtime gate | Future steps |
| --- | --- | --- | --- |
| C21 | q10/11/12/18/20 + authority units | UNVERIFIED | P1.1 / P2.1 / P3.4 / P4.4 / P5.1–3 |
| C22 | q19 + consent/session units | UNVERIFIED | P1.1 / P2.1 / P3.4 / P5.1 |
| C23 | index lifecycle specification only; no job runtime | UNVERIFIED | P1.1 / P3.3–5 |
| C24 | q18..24 + wire errors | UNVERIFIED | P1.2 / P2.5 / P3.3 / P4.1–5 / P5.2 |
| C25 | synthetic provenance + runtimeEnabled false + review/live blockers | UNVERIFIED | P1.5 / P2.5 / P3 / P4 / P5 |
## Bounded negative verification
- Bool revisions/probabilities, duplicate JSON keys, unknown privileged request fields and invalid Unicode rejected.
- Owner/consent/session/revision fixture guards deny before simulated generation branch.
- Noul conflict/uncertainty/error branches expect zero simulated generation calls; no actual provider invoked.
- Citation source IDs, quote/offsets/revision and known labels must match fixture context/canonical data.
- RRF example and source-range dedupe examples are deterministic; no search-quality or MMR runtime claim.

## Phase 1 exit
- Artifacts/checks can be complete while contract-review gate remains open.
- Live Jev model/thresholds, actual tokenizers/BM25 runtime and n8n/IAM/cloud wiring remain deferred to their gates.
- User must review newly proposed wire/offset/normalization/consent-row defaults; reading earlier plan did not approve every new field.
- Do not tick Phase 2–5 gates or run paid calls because this checker passed.
