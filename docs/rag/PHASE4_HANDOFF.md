# Latest checkpoint — PASS_SYNTHETIC_PRIVATE (12 October2026)

Fresh32confirmation7/8=87.5%,0/24unsafe, thresholds.85/.10 unchanged fromdevelopment.
Approval published;8/8 post-fix fixtureanswers and actualfullchain EN/VI sources/citations
verified.357RAGtests/29Python/typecheck/Phase1checkerPASS.176/176Jev,15/24DS,4/8Cohere,
4/8queries; reservation0.040542USD, not invoices. No furtherpaidcalls/publicenable.
MappingDisabled withAWSFunctioncallfailed; needsPhase5preflight/recovery. Cross-language
VIquery/ENnoteUNCERTAIN retained. Userdata/Flutter/Vercel/largecorpus unverified.
See phase4_final_gates.md/json; historical checkpoints below remain unchanged.

---

# Latest checkpoint — Hạnh gold corrected, offline candidate only

User chốt Hạnh đủ dữ kiện để trả lời "chưa". Candidate recalibrated on development:
0.85/0.10,8/9=88.9%,0unsafeallow; seenregression7/8=87.5%,0unsafeallow.
No newAPIcalls/deploy/livepolicychange. Confirmationpurpose nowregression-only;
report.gates.passed staysfalse evenwhenregressionmetrics pass.
See phase4_hanh_recalibration.md/json. Earlierdeployment/calibrationreceipt below
is historical and remains unchanged; fresh32-caseconfirmation still required.

---

# RAG Phase 4 — code implemented, calibration gate remains open

Updated 12 October 2026. Project: anhminh-final, base f6e188e.
Three DeepSeek Harness implementors completed disjoint provider, runtime and
calibration slices. Root integrated code, AWS resources and live verification.
No commit or push. No real-user notes were processed.

## Current result

| Step | Evidence | Status |
| --- | --- | --- |
| 4.1 JEV adapter | 128 real synthetic calls; pinned jev-1.13.0; two Nouls in one request; bounded HTTP/schema/usage | PASS transport |
| 4.2 Calibration | V1 2/8; approved V2 uses new confirmation: 5/8 answerable allowed, 0 unsafe allow | FAIL required 75% |
| 4.3 DeepSeek RAG | Flash non-thinking; answer/sourceIds mapped to authorized metadata; strict JSON/citations | Code/mock PASS; live blocked |
| 4.4 Runtime guards | Private Lambda, canonical ports, parent cancellation, atomic budget, read-only source IAM | Code/tests PASS; live refusal verified |
| 4.5 Full answers | Fixture/evaluator implemented; no calibration approval published | Live semantic/full-chain proof blocked |

## Calibration details

V1: development 32 selected 0.95/0.05, allowing 5/8 answerable cases.
Confirmation allowed 2/8 (25%), VI 0/4 and EN 2/4, with 0 unsafe allows.

User then approved V2 wording with the same criteria, 32 fresh confirmation cases
and 64 additional JEV calls. Total cap increased from 80 to 144 without resetting
usage. The P1/P2 policy stays unchanged; live questions are isolated in
amplify/rag/question_set.ts. Notes remain VI/EN; criteria are English.

V2: development selected and froze 0.95/0.10, allowing 6/8 (75%). Fresh
confirmation allowed 5/8 (62.5%), VI 2/4 and EN 3/4. All 24 unsafe cases were
refused; there were 0 provider errors. Thresholds were never retuned on confirmation.
Old confirmation is retained in regression-v1.json and is not held-out again.
Labels are synthetic author claims, not independent human-reviewed ground truth.

## Verification and AWS

348 focused RAG tests, 0 failures/0 skips; TypeScript typecheck, Phase 1 checker
and 26 Python RAG checks passed. Full Flutter tests were not run.

Full backend synth and change-set review passed. V1 added only a private RAG
stack and source exports; data resources were not deleted or replaced. Auth
was unchanged, and Summary runtime index.mjs was byte-identical (source-map
packaging hash changed). V2 changed only RAG Lambda code. Stack UPDATE_COMPLETE.

Private Lambda: 512 MB, 28-second timeout, reserved concurrency 1, retained
pinned tokenizer layer. No HTTP route, Function URL or frontend RAG output.
Indexing mapping stays Disabled. No Notes/Auth/Profile/Avatar data mutations.
Actual query/generation refuse LIVE_POLICY_NOT_CONFIGURED before provider egress
because passing calibration has not been published.

## Keys, token-fit and budget

Amplify references existing SSM SecureStrings DEEPSEEK_API_KEY and
TYPESAFE_API_KEY. Key values were never read, printed or copied into Flutter.
No dependency, .env or key changes.

Official DeepSeek V4 tokenizer artifact is pinned by hash and loaded using the
existing HF tokenizer package. Evidence/output use that artifact; exact hosted
prompt overhead is not claimed. JEV input admission uses conservative UTF-8
bytes plus framing margin, not an exact JEV tokenizer. Production fit stays open.

Used: 128/144 JEV calls, 0/24 DeepSeek calls, 0/8 Cohere calls, 0/8 private queries.
No counter reset or call refund. AWS $5 and external $1 are targets, not account
billing hard caps; DeepSeek worker Harness costs are separate. Actual invoices
were not queried. See phase4_receipt.json for usage and evidence hashes.

## Reproduce offline

```bash
python3 tool/rag/prepare_tokenizer.py
python3 tool/rag/prepare_phase4_tokenizer.py
RAG_TOKENIZER_DIR=output/rag/tokenizer node --import tsx --test amplify/rag/*.test.ts amplify/rag/indexing/*.test.ts amplify/rag/providers/*.test.ts amplify/rag/calibration/*.test.ts
npm run typecheck
python3 -m unittest discover -s tool/rag -p 'test_*.py'
```

The private runner tool/rag/evaluate_phase4.ts only accepts bundled fixture IDs.
It checkpoints responses, freezes development before confirmation and publishes
approval only after a passing gate. Raw receipts are ignored under output/rag.
Do not reset counters, rerun confirmation to choose thresholds, or bypass approval.

Next: review phase4_calibration_review.md. Live DeepSeek answers, full-chain
latency/semantic proof, human-reviewed gold and real-user Flutter/JWT release
remain unverified. Phase 4 is not acceptance-complete and Phase 5 stays closed.
