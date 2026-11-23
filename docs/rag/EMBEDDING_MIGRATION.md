# EmbeddingGemma-2 migration contract

Status: implementation profile, query admission and the stream mapping stay off until the gates in
`_agent_ops/reviews/embeddinggemma-migration-plan-20261017.md` pass.

## Active profile

`docs/rag/embeddinggemma_profile_v1.json` pins the artifact and runtime identity:

- model `embeddinggemma-2-q8`, GGUF Q8_0, 768 dimensions, cosine, mean pooling, L2 normalization;
- model file `embeddinggemma-2-Q8_0.gguf`, 309855520 bytes, SHA-256
  `6f1bd4ac6c5df7444f9cca7ca36cafe6cfa34cd6f49fefb1e0b4be8143aed8bc`;
- runtime llama.cpp `0.7.0-dev` build 11706 commit `f74e2fa6a31cc33ab4ee4ae516641cfe62df3924`,
  CPU, no Metal, context 2048, parallel 1;
- tokenizer `google/embeddinggemma-2` revision `914f7f89142e33e77833254d9c9b90c3cef7303b`,
  files pinned in `docs/rag/embeddinggemma_tokenizer_manifest.json`.

`docs/rag/policy_v2.json` is the active policy. `docs/rag/policy_v1.json` is kept unchanged for
rollback. The snapshot policy identity hashes the profile, tokenizer manifest, dimensions, input
formats, pooling/normalization/quantization, chunking and span policy, so a Cohere-era snapshot or
manifest is never treated as current and a 1024-dimensional vector is refused (never padded or
truncated).

## Input format

Document: `title: {title or none} | text: {content span}`.

Query: `task: search result | query: {question}`.

The framing is applied exactly once. Token counts include the framing, BOS/EOS and any runtime
special tokens; an over-limit input is refused, not truncated.

## Vector index

- Legacy retained index: `rag-v1`, 1024/float32/cosine (unchanged logical `RagVectorIndex`).
- Active additive index: `rag-eg2-q8-768-v1`, 768/float32/cosine
  (`RagEmbeddingGemmaVectorIndex`).
- Worker, query and probe all receive the active index ARN. No key or vector is shared between the
  two indexes and the legacy index is not cleaned up by this migration.

## Secrets

`CLOUDFLARE_ACCESS_CLIENT_ID` and `CLOUDFLARE_ACCESS_CLIENT_SECRET` are Amplify-managed SSM
SecureStrings in `noteflow-dev` / `noteflow-smoke` (`ap-southeast-1`). The managed Lambda declares
`secret(...)` refs; the CDK worker/probe resolve the same refs through Amplify's secret fetcher at
deploy. No value is read, printed, committed or written into a CDK template.

## Open before activation

- The VI/EN notice and client/backend contract now use `rag-consent.v2`. A legacy v1 grant
  reads as current-denied with its generation preserved; an explicit v2 Allow is still required
  after deployment. Acceptance is never copied automatically.
- A live AWS -> Cloudflare -> Mac canary, tokenizer differential proof and the migration ledger
  preflight are still required.
- Query admission (`RAG_QUERY_ADMISSION_ENABLED`) and the stream mapping stay disabled until the
  full migration gate passes.

## Operator migration

`tool/rag/migrate_embedding_profile.ts` defaults to read-only preview. After verifying all six
reviewed legacy input digests, `--apply` updates only the pilot config using whole-value CAS,
generation +1 and enabled=false. It never changes canonical notes, consent, counters or vectors.
Set RAG_EMBEDDINGGEMMA_TOKENIZER_DIR=output/rag/embeddinggemma-tokenizer. An explicit v2 grant
is required before backfill. The backend identifier is `noteflow-smoke`, including the hyphen.

Local tokenizer parity and mock gates do not prove the live AWS path. Query admission and the
stream mapping remain off until migration, safety and quality gates pass.
