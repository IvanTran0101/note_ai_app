# RAG — Phase 1 artifacts and Phase 2 backend mock
MVP scope approved: own synced text notes, not protected/shared/attachments.
Phase 2 mock is implemented under amplify/rag: 148 related tests and typecheck PASS.
Read PHASE2_HANDOFF.md to run the loopback demo; phase2_receipt.json records evidence.
Fixtures contain no credentials or real user notes.

## Start
1. Read ../contracts/rag_api_v1.md.
2. Review policy_v1.json and open_decisions.md.
3. Run python3 -B tool/rag/check_phase1.py --root . from project root.
4. Run python3 -B -m unittest discover -s tool/rag -p test_phase1_contract.py.
5. Read PHASE2_HANDOFF.md for the implemented mock; Phase 3 AWS integration remains separate.

## Contents
- contract_registry.json/.md: C01–C25 and future verification pointers.
- test/fixtures/rag: 12 authored notes, 24 VI/EN questions, wire/provider/ranking/span/budget fixtures.
- tool/rag: standard-library offline reference oracle and boundary tests. Not production security code/tokenizer/model evaluation.
- PHASE1_HANDOFF.md: receipt and review status after verification.

Approved constants: Cohere V3/1024; 400/512 tokens/0 overlap; Top-20 + Top-20; RRF60 equal weights; MMR0.7/max8; expansion±1/no recursion; source dedupe; 6000 evidence tokens; two Noul criteria.
Runtime remains disabled; live model/thresholds NULL. Code in amplify/lib, cloud, secrets and dependencies are untouched by this phase.
Notion plan: https://app.notion.com/p/3f625edc9a2580ec9630e8f7bfa9ef49
