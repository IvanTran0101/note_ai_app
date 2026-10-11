# Decisions and blockers after Phase 1 scope approval
Approved core choices are unchanged. Technical defaults below make a concrete reviewable draft; they are not secretly live production settings.

| ID | Status | Resolution / next gate |
| --- | --- | --- |
| OPEN01 | APPROVED_BY_USER | Own synced text notes; no protected/shared/attachments. Account/current-note scope shapes proposed for review. |
| OPEN02 | TECHNICAL_DRAFT + LIVE_BLOCKER | UTF-16 half-open spans, title newline content embedding input proposed. Actual Cohere/DeepSeek/Jev counters and fit proof required before live. Counter fixtures are injected, not measured. |
| OPEN03 | TECHNICAL_DRAFT | RRF/max pool score relevance; maximum positive cosine redundancy; source-key tie proposed. λ=0.7 and max 8 approved. Validate selection behavior in Phase 2. |
| OPEN04 | DEFERRED_PHASE4 | Exact two Nouls/criteria approved. liveModel/liveThresholds NULL; mock 0.9/0.1 never treated as calibration. Pin/evaluate VI/EN before live gate. |
| OPEN05 | TECHNICAL_DRAFT + LIVE_MEASUREMENT | Wire limits 16 KiB/4096 bytes/2048 code points; response 64 KiB/output 1024; total deadline 26 s proposed. Per-stage budgets, concurrency and external bill caps need review/measurement. |
| OPEN06 | DEFERRED_PHASE3 | n8n host, trusted auth/trigger/transport and publication ownership not configured. |
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
