# RAG API contract v0.1 — Phase 1 review artifact
Status: approved product/algorithm choices + technical defaults proposed for review.
Runtime disabled. This is not a deployed API or provider-quality receipt.
Scope approved 2026-10-11: own synced text notes, never protected/shared/attachments.

## 1. Boundaries
- Flutter Web on Vercel calls the AWS backend; BM25 runs in Lambda, snapshots in private S3 Standard, semantic index in S3 Vectors.
- Actor is the verified Cognito access-token sub. Body cannot supply actor/owner, evidence, provider endpoint/model, thresholds or consent proof.
- Only canonical notes owned by actor, already synced, not deleted, not protected, with available content are eligible. A shared copy remains excluded even with read/unlock permission.
- Here shared means an incoming/other-owner projection. Sharing one's own note outward does not change its owner; it remains subject to the same own-note guards.
- RAG consent is separate from Summary, default off, bound to account/version/generation. Missing consent fails before embedding or indexing. Revalidate before every external call and authorized response release.
- Notes local-only, drafts not synced, protected notes (even unlocked), other owners and attachments are excluded. Query never mutates a note.
- Application source is unchanged by this phase. Offline Python oracles simulate facts, never verify a real JWT, AWS authority, tokenizers or Jev semantics.

## 2. Proposed wire — version 1
Route: POST /ai/rag/query. JSON required, no unknown or duplicate fields.
Server requestId is a correlation value, not an idempotency or exactly-once billing promise.

```json
{"wireVersion":1,"question":"SLGH031 chạy bao lâu khi lên cót đầy?","scope":{"type":"account"}}
```

Note scope alternative: {"type":"note","noteId":"n-watch"}.
Actor comes from access token; noteId is raw canonical own-note ID, not a foreign owner reference.
Question is preserved; only blankness checks trim. Valid UTF-8 required.
Technical proposed limits: body 16 KiB; question 2048 Unicode code points and 4096 UTF-8 bytes; response 64 KiB; generation max 1024 tokens; total request deadline 26000 ms.
These wire bounds do NOT prove embedding-token fit. Actual Cohere input (including prefix) must also fit 512 tokens and 2048 characters with truncate NONE. Fail before egress if no trustworthy fit counter/proof exists.
Identifiers are nonblank, trimmed, max 128 code points, no ASCII control characters. Numeric versions/revisions/offsets follow JavaScript safe-integer semantics: integral 1.0 equals 1, but booleans and fractional values are rejected.
DTO shape is a review proposal, not a new user-approved algorithm constant.

## 3. Answer and sources
```json
{"wireVersion":1,"requestId":"fixture-q01","status":"ANSWERED","answer":"Khoảng 80 giờ khi lên cót đầy. [S1]","sources":[{"sourceId":"S1","noteId":"n-watch","revision":1,"title":"SLGH031","startOffset":0,"endOffset":125,"quote":"SLGH031 sử dụng Caliber 9SA5.\nKhả năng dự trữ năng lượng khoảng 80 giờ khi lên cót đầy.\nVỏ đồng hồ dùng Ever-Brilliant Steel."}]}
```
The example is the validated synthetic w-s01 fixture; it is not a real provider response.
Each source is server issued and belongs to the exact evidence bundle approved by Jev. note/revision/title/span/quote must match canonical own-note text and context source map.
Proposed offsets: UTF-16 code units, start inclusive/end exclusive. Never bisect a surrogate pair or rewrite source text by trimming/normalizing and then reuse old offsets.
Inline labels must map to known unique source IDs; no provider-invented labels, raw bucket keys, public/signed S3 URLs, arbitrary external URLs or owner impersonation fields.
Structural citation checks do not prove semantic truth; Phase 4 needs human-reviewed gold evaluation.
After delivery, a source click checks revision/currentness; a changed note is reported as changed, not presented as the same old quote.
Answer language follows question in proposed generation behavior; Settings preference controls UI/consent copy. No second language setting.

## 4. Abstention and errors
```json
{"wireVersion":1,"requestId":"rq-demo","status":"NOT_ENOUGH_CONTEXT","reason":"INSUFFICIENT_EVIDENCE","answer":null,"sources":[]}
```
Other abstention reasons: UNRESOLVED_CONFLICT, UNCERTAIN. HTTP 200 for a successfully evaluated question without an answer.
A retrieval/index/provider/schema/authorization failure is never disguised as no evidence.
Error envelope: {"wireVersion":1,"requestId":"rq-demo","status":"ERROR","code":"INDEX_NOT_READY"}.
Error names and HTTP mapping are technical proposals in policy_v1.json:
INVALID_INPUT 400; INPUT_TOO_LONG 413; UNAUTHORIZED 401; CONSENT_REQUIRED 403;
SCOPE_DENIED 404 (hide note existence); INDEX_NOT_READY/SOURCE_CHANGED 409;
RATE_LIMITED 429; EVIDENCE_VALIDATION_UNAVAILABLE/PROVIDER_UNAVAILABLE/LIVE_POLICY_NOT_CONFIGURED 503;
INVALID_PROVIDER_OUTPUT 502; TIMEOUT 504.
No raw provider body, token, credential, stack or content in error/log output.
No automatic retrieve-again or generation retry/fallback after abstention or failure. SDK retries need explicit bounded policy; timeout can already be billed.

## 5. Retrieval and context invariants
1. Semantic pre-filter eligible scope + Top-20; BM25 independently searches same eligible corpus + Top-20.
2. RRF rank-based fusion, constant 60, equal weights, absent contribution 0. Same identity/revision deduped; one contribution per branch, original ranks retained; max union 40.
3. MMR: normalized RRF relevance + chunk cosine redundancy; lambda 0.7, max 8 anchors. Proposal: divide RRF by pool maximum; redundancy max(0, max cosine to selected); first seed by relevance; stable source-key tie. Reject zero/non-finite/wrong-dimension vectors instead of inventing replacements.
4. GetVectors batches reuse 1024-dimensional same-model/revision vectors, including BM25-only candidates; no re-embedding per query.
5. Expansion up to previous 1 + next 1, same note/revision/section, no recursion or forced filling. Dedupe source identities/overlapping spans; contiguous spans may merge only within same source.
6. Do not content-hash/semantic-dedupe across distinct sources or erase different numbers, units, conditions or negation.
7. Evidence max 6000 DeepSeek tokens includes titles/source labels. Prioritize anchors; remove expansion before low-priority anchors; no mid-sentence cut. System/question/output use separate budget. Jev input has separate preflight.
8. Preserve original text order inside a passage; passage priority is best contained MMR anchor. Keep source-span map through merge.
9. Evidence bundle is immutable once gate is run; any source/bundle change invalidates verdict and current run. Do not refresh silently under an old permit.

## 6. Jev semantic contract — approved criteria
One request, same minimal question/evidence/title/source-label state; no vectors/retrieval scores/JWT/secrets/full corpus.
questionSetVersion = rag-evidence.v1. Both questions have type noul.
- answerable_from_evidence: True = evidence có dữ kiện cho các phần user hỏi, đúng đối tượng và điều kiện liên quan.
  False = chỉ cùng chủ đề; thiếu dữ kiện; hoặc phải bổ sung kiến thức ngoài evidence.
- has_unresolved_conflict: True = cùng đối tượng/điều kiện nhưng có thông tin không tương thích, context chưa giải quyết.
  False = không có mâu thuẫn liên quan hoặc evidence giải thích rõ sự khác biệt.
Jev returns noul probabilities, not free-text explanations or a separate confidence field. Each question is independent; backend combines results, does not average away a conflict.
Live model/thresholds are NULL and runtime disabled until Phase 4 evaluation and approval. Fixture thresholds 0.9/0.1 are synthetic branch-test values only.
Missing answers, wrong types, bool/non-finite/out-of-range probability, invalid usage or timeout => validation error, generation not called.
A value near 0.5 is uncertainty, not half-complete context. Backend owns reason codes and ALLOW/ABSTAIN/ERROR decision.
Typed output/high probability does not guarantee correctness. VI/EN and adversarial/distractor cases need actual evaluation; no automatic translation as a hidden paid stage.

## 7. Index, consent and release — engineering proposals
Consent record proposal in existing notes table: partition owner key OWNER#<verified-sub>, sort key RAG#CONSENT. Use existing canonical namespace helper, not raw client owner.
Record accepted/version/generation/updatedAt/provider purposes; CAS generation on grant/revoke; no TTL or note feed/relay fields. This is design only, no table mutation in Phase 1.
Index jobs bind canonical owner/note/revision, consent generation, chunking/model policy. n8n is async orchestration, not synchronous answer pipeline.
Publish coherent vector/BM25 manifest only after required artifacts are ready; reject older jobs replacing newer revision. Cache scope + manifest version, cache miss is not no evidence.
Revoke/delete/protect blocks subsequent use immediately through canonical guard; physical artifact removal is async with retention/cleanup policy still pending.
INDEX_NOT_READY is distinct from a completed search with no evidence. Release revalidation prevents stale answer across session/consent/source changes.
AWS 5 USD is a staging target, not a billing hard cap. External TypeSafe/DeepSeek cost and live authorization are separate.

## 8. Verification and next gate
python3 -B tool/rag/check_phase1.py --root .
python3 -B -m unittest discover -s tool/rag -p test_phase1_contract.py
Artifacts are synthetic/reference checks, not Flutter/backend/cloud tests.
Review technical defaults and remaining blockers in docs/rag/open_decisions.md before Phase 2 mock.
Sources: [Cohere V3](https://docs.aws.amazon.com/bedrock/latest/userguide/model-parameters-embed-v3.html), [Noul](https://docs.typesafe.ai/primitives/noul), [Jev Models](https://docs.typesafe.ai/models), [HTTP API quota](https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api-quotas.html).
