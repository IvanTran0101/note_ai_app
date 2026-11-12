# RAG contract registry v0.1

OPEN01 approved: own synced text notes, no protected/shared/attachments. All application/cloud runtime gates remain UNVERIFIED.
A = user-approved choice. E = engineering obligation derived from that choice. Technical defaults are proposed for contract review, not falsely attributed to human approval.

## A — Hosting, chunking và hai nhánh retrieval

| ID | Status | Rule | Planned steps |
| --- | --- | --- | --- |
| C01 | A | Flutter Web Vercel; backend RAG và BM25 trên AWS | P3.1 / P5.4 |
| C02 | A | Paragraph-first; sentence/token fallback cho phần lớn; pack liền kề; target 400/max 512 tokens, overlap 0 | P1.3 / P2.2 / P3.2 |
| C03 | A | Cohere Multilingual V3; 1024 chiều; document/search_document, question/search_query | P1.3 / P3.2 |
| C04 | A | S3 Vectors pre-filter phạm vi hợp lệ + semantic Top-20 | P2.1 / P2.3 / P3.1–2 |
| C05 | A | BM25 độc lập Top-20 trong Lambda; snapshot S3 thường; RAM/tmp là cache | P2.2–3 / P3.3 |

## B — RRF và MMR

| ID | Status | Rule | Planned steps |
| --- | --- | --- | --- |
| C06 | A | RRF constant 60, equal weights; rank từ 1; absent contribution 0 | P1.3 / P2.3 |
| C07 | A/E | Merge đúng source identity/revision, một đóng góp mỗi branch; union tối đa 40 | P1.3 / P2.3 / P3.3–4 |
| C08 | A | MMR = RRF chuẩn hóa + cosine giữa chunks; λ 0.7; tối đa 8 anchors | P1.3 / P2.4 |
| C09 | A | GetVectors theo batch; reuse vectors cùng model/revision; không re-embed shortlist | P2.4 / P3.2 |
| C10 | A | Expansion tối đa 1 chunk trước + 1 sau mỗi anchor; không đệ quy | P1.3 / P2.4 |

## C — Expansion, dedupe và ngân sách context

| ID | Status | Rule | Planned steps |
| --- | --- | --- | --- |
| C11 | A | Expansion cùng note/revision/section, còn quyền và đủ điều kiện | P2.1 / P2.4 / P3.4 |
| C12 | A | Dedupe source identity/overlapping spans; merge contiguous spans cùng nguồn hợp lệ | P1.3 / P2.4 |
| C13 | A | Giữ text gần giống nhưng khác nguồn, số liệu, điều kiện, đơn vị hoặc phủ định | P2.4 / P4.5 |
| C14 | A | Evidence cap 6000 tokens theo DeepSeek, gồm title/source labels; prompt/query/output ngân sách riêng | P1.3 / P2.4 / P4.1–4 |
| C15 | A | Ưu tiên anchors; quá budget bỏ expansion trước; không cắt tùy tiện giữa câu | P2.4 / P4.3–5 |

## D — JEV và generation

| ID | Status | Rule | Planned steps |
| --- | --- | --- | --- |
| C16 | A | Hai Noul: answerable_from_evidence + has_unresolved_conflict, criteria ở dưới | P1.4 / P2.5 / P4.1–2 |
| C17 | E | Minimal state text/source labels; source bundle immutable và bound tới request/revisions | P1.2 / P2.5 / P4.1–5 |
| C18 | A/E | Backend decision; allow mới generate; uncertainty/conflict/insufficient thì abstain | P1.4 / P2.5 / P4.2 |
| C19 | A | Không tự retrieve lại hoặc retry/fallback generation sau NOT_ENOUGH_CONTEXT | P2.3 / P2.5 / P4.4 |
| C20 | A/E | DeepSeek viết từ evidence đã gate; backend kiểm citation/currentness; semantic quality còn phải eval | P1.2 / P2.5 / P4.3–5 / P5.2 |

## E — Authority, lifecycle và triển khai

| ID | Status | Rule | Planned steps |
| --- | --- | --- | --- |
| C21 | E | Canonical actor/consent/source status/revision checks ở indexing, retrieval, egress và release | P1.1 / P2.1 / P3.4 / P4.4 / P5.1–3 |
| C22 | E | RAG consent riêng, default off; không reuse Summary grant; account/session/version binding | P1.1 / P2.1 / P3.4 / P5.1 |
| C23 | A/E | DynamoDB Stream → Lambda indexing worker ngoài query path; index/snapshot/cache publication chống replay/stale jobs | P1.1 / P3.3–5 |
| C24 | E | Absence/uncertainty khác index-not-ready, auth, provider/validation và source-changed errors | P1.2 / P2.5 / P3.3 / P4.1–5 / P5.2 |
| C25 | E | Secrets backend; focused tests; mock/live receipts riêng; AWS staging target 5 USD, external AI cost riêng | P1.5 / P2.5 / P3 / P4 / P5 |

Machine source: `contract_registry.json`; policy source: `policy_v1.json`. Criteria are in policy and API contract. Changing fields/normalization/criteria requires contract/policy version review; aliases are not a calibration guarantee.
