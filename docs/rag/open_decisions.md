# Decisions and blockers after Phase 1 scope approval
Approved core choices are unchanged. Technical defaults below make a concrete reviewable draft; they are not secretly live production settings.

| ID | Status | Resolution / next gate |
| --- | --- | --- |
| OPEN01 | APPROVED_BY_USER | Own synced text notes; no protected/shared/attachments. Account/current-note scope shapes proposed for review. |
| OPEN02 | TECHNICAL_DRAFT + LIVE_BLOCKER | UTF-16 half-open spans, title newline content embedding input proposed. Actual Cohere/DeepSeek/Jev counters and fit proof required before live. Counter fixtures are injected, not measured. |
| OPEN03 | TECHNICAL_DRAFT | RRF/max pool score relevance; maximum positive cosine redundancy; source-key tie proposed. λ=0.7 and max 8 approved. Validate selection behavior in Phase 2. |
| OPEN04 | DEFERRED_PHASE4 | Exact two Nouls/criteria approved. liveModel/liveThresholds NULL; mock 0.9/0.1 never treated as calibration. Pin/evaluate VI/EN before live gate. |
| OPEN05 | TECHNICAL_DRAFT + LIVE_MEASUREMENT | Wire limits 16 KiB/4096 bytes/2048 code points; response 64 KiB/output 1024; total deadline 26 s proposed. Per-stage budgets, concurrency and external bill caps need review/measurement. |
| OPEN06 | TRANSPORT_APPROVED + DEFERRED_PHASE3 | User approved DynamoDB Stream → Lambda indexing worker on 2026-10-12. Event source mapping/IAM, filters, bounded retries, failed-event recovery and backfill remain to specify/implement. No n8n host needed. |
| OPEN07 | TECHNICAL_DRAFT | /ai/rag/query request/response/error mapping in rag_api_v1.md proposed; no endpoint created. |
| OPEN08 | TECHNICAL_DRAFT + DEFERRED_PHASE3 | Canonical RAG consent row/CAS generation/revalidation proposed. Retention/physical cleanup and manifest publication implementation remain open. |
| OPEN09 | DEFERRED_PHASE2_TO4 | No new dependencies/key/install. Select a VI BM25 analyzer/snapshot codec and compatible AWS/provider adapters after contract review. |

## Review now
1. Proposed wire DTO/status/error mapping and sizing caps.
2. UTF-16 source spans and title-prefix accounting.
3. RRF normalization/positive-cosine/tie rules for MMR.
4. Canonical consent-row/key/generation and index-readiness semantics.

## Not review by guesswork
Do not assign real probability thresholds, tokenizer correctness, language accuracy, live permissions or total monthly charge from synthetic values.
Phase 2 can work with injected adapters/counters and mock thresholds; live path remains disabled until corresponding gates are met.

## Phase 2 implementation authorization — 2026-10-11
User explicitly authorized implementation of Phase 2 using DeepSeek implementors.
Technical defaults above are now implemented and mock-tested; they do not enable
production provider calls or replace live-fit/calibration/budget gates. OPEN03
mechanics and OPEN07 HTTP shapes are fixed for this mock. OPEN09 has a mock
NFKC/lower Unicode word analyzer (rag-analyzer.v1), BM25 k1=1.2/b=.75 and version-1
lexical snapshot codec with complete chunk-policy identity; live search quality
and storage/SDK compatibility remain unverified. See PHASE2_HANDOFF.md and
phase2_receipt.json. Policy runtimeEnabled remains false and Jev live values null.

## Phase4 current receipt — 2026-10-12
Phase3 indexing/storage/consent-CAS has synthetic AWS proof; old deferred rows
above are historical. Phase4 provider/runtime/budget/evaluator code is now
implemented and private-deployed. JEV64calls succeed, but frozenconfirmation
acceptance2/8=25% fails75% gate. OPEN04 remainsBLOCKING, OPEN02 exactJevtokenizer
andOPEN05 fullgeneration latency remainunverified. No liveDeepSeek/CoherePhase4
calls or publicRAGroute. See PHASE4_HANDOFF.md andphase4_receipt.json. Userreview
ofphase4_remediation_v2.md pending; no retune/counterreset/modelbudgetincrease.

## V2 result — 12 October 2026
V2 wording and64 additional calls approved and executed, cap144, used128. Fresh
confirmation allowed5/8=62.5%, VI2/4 andEN3/4,0unsafeallow. OPEN04 remainsblocking;
no calibration row published, noDeepSeek/Cohere calls, noPhase5/publicrelease.
See phase4_calibration_review.md. EarlierV1receipt above is historical.

## Hạnh gold review and offline recalibration — 12 October 2026
User correctedHạnh toanswerable(negativeanswer), nofact/source/questionchange.
Development9answerable/23unsafe; frozenofflinecandidate.85/.10 allows8/9=88.9%,
0unsafe. Seenregression7/8=87.5%,0unsafe; NOTfreshconfirmation. Guardblocks
promotion andlive runner before network.0newcalls/deploy/publishedapproval.
OPEN04stillneedsfresh32-caseconfirmation; historical128/144counter notqueried
again. See phase4_hanh_recalibration.md/json.

## Current Phase4 final gates — 12 October2026
User approved fresh32confirmation and cap176. Candidate.85/.10 retained, fresh7/8=87.5%,
0unsafe, approvalpublished;8/8DSfixtureanswers and2native-language fullAWSqueryanswers
verified. OPEN04 nowPASS_SYNTHETIC_PRIVATE, notproductionaccuracy. OPEN02 exactJev
admission/promptoverhead andOPEN05large-corpus/realuserlatency remainreleasechecks.
176Jev/15DS/4Cohere/4queries, noreset. MappingDisabled(Functioncallfailed) remainsa
Phase5preflight/recoverygate. No publicroute/Flutterenable orreal-user data. See
phase4_final_gates.md/json forlatestreceipt; allprecedingreceipts arehistorical.
