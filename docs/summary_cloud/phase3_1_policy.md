# Phase 3.1 — Shared Summary policy

Hoàn thành 2026-09-30 tại project gốc, baseline1056408.

## Đầu ra

- assets/summary_policy.json là nguồn duy nhất cho prompt theo stage, consent version, input estimate16000, framing256, body cap262144, output128/256, maxChunks4/maxCalls5. Không chứa key hoặc provider configuration.
- Backend summary_contract.ts import asset và giữ API exports/schema/request/render behavior. Model, endpoint, secrets và HTTP flags vẫn backend-only.
- Dart SummaryRequestPolicy ở Infrastructure có JSON validation, Flutter AssetBundle loader, stage renderer, UTF8 estimate và fit check. Domain/Application/UI/local worker không đổi.
- Golden fixture19cases được capture từ backend **trước extraction** tại1056408. Tiếng Việt, emoji/combining, escapes, line separators, malformed surrogate, merge/order và biên15999/16000/16001 đều giữ baseline.
- ECMAScript edge trim được giữ riêng vì Dart trim cũng loại U+0085 nhưng JavaScript không.

## Checks đã chạy

```bash
node --import tsx amplify/ai/policy.test.ts
flutter test --no-pub test/infrastructure/note_intelligence/summary_request_policy_test.dart
npm run typecheck
```

19TypeScript goldens và24Dart focused tests pass. Backend runtime30/quota8/CDK7
vàLambda composition mocks pass. Analyzer sạch, full Flutter930pass2intentional
skips, Web build pass. Policy asset trong build/web có cùng SHA256 với source.
Installed esbuild xác minh Lambda bundle embed JSON (write:false, không execute
handler hoặc provider). Golden tests là correctness checks, không phải benchmark.

## Handoff

SummaryRequestPolicy.load() đọc Flutter asset; buildMessages/estimateInputTokens/
fitsInput dùng enum SummaryStage. Formula = UTF8 bytes của messages JSON +256.
Đây là estimate, không phải tokenizer hoặc đảm bảo token thật.

Phase3.2 sẽ thêm HTTP gateway; Phase3.3 thêm bounded orchestrator. Hiện chưa có
remote UI wiring, consent UI, provider request hoặc deployment.
