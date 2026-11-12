# RAG Phase 2 — mocked backend

Scope: own synced canonical text notes, not protected or incoming shared notes.
This slice implements the v0.1 contract with synthetic adapters. Production
RAG remains disabled; no AWS resources, provider keys or Flutter flows are added.

## Run the synthetic HTTP demo

From the original repository root:

```sh
node --import tsx amplify/rag/mock_server.ts
```

In a second terminal:

```sh
curl http://127.0.0.1:8797/ai/rag/query \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer rag-mock-actor-a' \
  --data '{"wireVersion":1,"question":"SLGH031 chạy bao lâu khi lên cót đầy?","scope":{"type":"note","noteId":"n-watch"}}'
```

The credential is a fixed public synthetic test value, not a real JWT. The
server rejects browser origins and binds loopback only. Its explicit test
consent is not production consent; the real RAG consent default stays off.
Ctrl+C stops the demo. The currently running Flutter app is unchanged.

## Runtime path

1. HTTP route/schema/access-token claims boundary → canonical consent/scope
   snapshot and request deadline.
2. Fake query embedding → independent vector/BM25 Top-20 → RRF → reused vectors
   and MMR (maximum eight anchors).
3. Adjacent context expansion → source-span dedupe → bounded immutable evidence.
4. Fake Jev two-Noul gate → fake generation only on ALLOW → structural citation
   checks and canonical release revalidation.

No retry/retrieval loops. Empty search and index/provider failures have separate
envelopes. The backend never changes notes during a query.

## Mock provenance and live blockers

The Unicode word/number BM25 analyzer and snapshot version are explicit Phase 2
choices. Vietnamese diacritics are retained; no Vietnamese word segmentation
or production search-quality calibration is claimed.
Counters and 1024-dimensional embeddings are deterministic synthetic values.
They do not measure Cohere, DeepSeek or Jev tokenization/quality. Noul thresholds
0.9/0.1 exercise branches only. Mock answers quote evidence, not real generated
model output. Jev model/thresholds in policy_v1.json remain null.

The authority adapter simulates canonical state and session/consent generation.
Real JWT signature validation is an API Gateway/Cognito deployment gate.
DynamoDB/S3/S3 Vectors, coherent manifest publication/cleanup and Stream → Lambda indexing
belong to Phase 3; real Jev/DeepSeek adapters and evaluation belong to Phase 4;
Flutter consent/citations and live staging acceptance belong to Phase 5.

## Verification

See phase2_receipt.json for the exact commands, test counts, mock gate coverage
and limitations actually verified. No full Flutter suite is needed for this
backend-only slice. Source and test implementation use existing installed
dependencies and Node standard libraries; no dependency install is required.
