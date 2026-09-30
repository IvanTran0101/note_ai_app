# Phase 3.2 + 3.3 — Summary HTTP gateway và remote orchestration

Hoàn tất tại project gốc ngày 2026-09-30, HEAD `1056408` + thay đổi chưa commit.
Hai DeepSeek Harness workers implement hai phạm vi riêng; GPT-6.1 Sol High
review read-only; root tích hợp và chạy focused checks. Ponytail full.

## 1. Phase 3.2 — HTTP gateway

- `SummaryHttpGateway.generate` thực hiện một stage; giữ base path và schema v0.3.
- Nhận token callback tương thích `CognitoAccessTokenProvider.call`; bắt buộc
  `expectedAccountUserId`. Kiểm tra JWT sub trước mỗi dispatch. API Gateway vẫn
  xác minh chữ ký và access-token semantics; client guard chỉ giữ account nhất quán.
- Một deadline tối đa 35 giây cho token, tối đa một refresh sau 401, send và
  body read. AbortableRequest, cancel stream khi timeout/oversize, tắt redirects.
  Token trả về muộn không được bắt đầu HTTP. Các lỗi generation khác không retry.
- Mapper validate exact success schema, requestId, summary và usage; enforce
  output/input caps, status-authoritative errors, Retry-After tối đa 3600 giây.
  Không đưa token/content/raw response/exception vào failure. Client được inject
  là borrowed; `close()` chỉ đóng client do gateway tự tạo.

Files: `summary_http_gateway.dart`, `summary_http_call.dart`,
`summary_http_mapper.dart`, `summary_api_failure.dart` trong
`lib/infrastructure/note_intelligence/`.

## 2. Phase 3.3 — Remote service

- `RemoteSummarizationService` giữ nguyên Domain contract
  `summarize(String content) → Future<Summary>`.
- Direct nếu toàn bộ messages estimate ≤16000. Nếu không, preflight mọi chunk
  và body trước generation đầu tiên; tối đa 4 sections + 1 final merge.
- Sections gửi tuần tự, giữ thứ tự; merge đúng một lần. Lỗi stage/merge budget,
  output rỗng hoặc >4 chunks đều dừng; không trả partial summary, không merge
  đệ quy, không thêm direct call sau merge và không dùng local token heuristic.
- Một deadline toàn pipeline tối đa 150 giây, kể cả injected generator treo.
  Recheck consent trước mọi stage và trước khi trả kết quả.

`SummaryChunkSplitter` dùng full rendered policy estimate. Dùng lại boundary
chooser newline → whitespace từ local splitter, nhưng giữ nguyên UTF-16
substrings ở remote: nối chunks tái tạo normalized input, không cắt surrogate
pair hợp lệ, giữ lone surrogates và combining marks.

Policy thêm request serializer dùng chung cho gateway/preflight và trim tuyến
tính theo đúng ECMAScript whitespace set. U+0085 giữ nguyên. Local defaults và
local recursive summarizer vẫn như trước.

## 3. Checks đã chạy

| Phạm vi | Kết quả |
| --- | --- |
| 12 related native test files | 162 passed |
| 9 new cross-platform mock test files trên Chrome | 112 passed |
| Scoped Dart analyzer | No issues found |
| Format + git diff check | PASS |
| Baseline SHA checks | Backend contract, pubspec, policy JSON, .gitignore, changelist không đổi |

Không chạy full suite hơn 900 tests. Các regression covers: full-message
threshold 16000/16001, 2/4/>4 chunks, stage failure, blank output, merge budget,
consent revoke, hanging generator, body cap trước calls, token/account refresh,
stream cancellation, JSON/usage errors, U+0085, NBSP/BOM/U+2028 ở ranh giới,
4 exact emoji chunks và local splitter behavior. Mock integration dùng cả
HTTP gateway + orchestrator cho direct và 4 sections + merge.

Initial focused run phát hiện fixture dùng section capacity nhưng vẫn vừa
direct, và edge-trim regex có quadratic cost với khoảng trắng nội bộ dài. Đã
sửa fixture theo direct threshold và thay regex bằng quét hai đầu tuyến tính;
final checks phía trên pass.

Chrome unit-test harness bị kẹt khi đọc bundled assets, khớp
[Flutter issue 159879](https://github.com/flutter/flutter/issues/159879).
Chrome mock checks inject chính bytes JSON source bằng dart-define; native tests
vẫn dùng Flutter bundle. Điều này không chứng minh asset loader của app chạy
trên Web runtime. Production asset loader không đổi.

### Chạy lại native (từ project gốc, Bash/zsh)

```bash
flutter test --no-pub \
  test/infrastructure/note_intelligence/summary_http_gateway{,_auth,_transport}_test.dart \
  test/infrastructure/note_intelligence/summary_http_mapper{,_errors}_test.dart \
  test/infrastructure/note_intelligence/remote_summarization{_service,_lifecycle,_http}_test.dart \
  test/infrastructure/note_intelligence/summary_chunk_splitter_test.dart \
  test/infrastructure/note_intelligence/summary_request_policy_test.dart \
  test/infrastructure/note_intelligence/note_summary_resource_policy_test.dart \
  test/infrastructure/ai/local_summarization_service_test.dart
```

### Chạy lại Chrome mock tests

```bash
python3 - <<'CHECK'
from pathlib import Path
import base64, json
encoded = base64.b64encode(Path('assets/summary_policy.json').read_bytes()).decode()
Path('/tmp/summary-policy-defines.json').write_text(json.dumps({'SUMMARY_TEST_POLICY_BASE64': encoded}))
CHECK
flutter test --no-pub --platform chrome \
  --dart-define-from-file=/tmp/summary-policy-defines.json \
  test/infrastructure/note_intelligence/summary_http_gateway{,_auth,_transport}_test.dart \
  test/infrastructure/note_intelligence/summary_http_mapper{,_errors}_test.dart \
  test/infrastructure/note_intelligence/remote_summarization{_service,_lifecycle,_http}_test.dart \
  test/infrastructure/note_intelligence/summary_chunk_splitter_test.dart
```

## 4. Handoff Phase 3.4

Adapter/orchestrator có thể được inject, nhưng app vẫn dùng local. Chưa có remote
composition, consent UI hay per-run account/session/note snapshot context.

Phase 3.4: Application tạo context riêng cho mỗi lần chạy, revalidate
account/session/consent/note trước mọi stage và trước display; dừng khi logout,
đổi account, note edit/delete/conflict, thu hồi consent hoặc widget đóng.
`expectedAccountUserId` và `hasConsent` ở phase này không thay thế context đó.

Không có real API call, key provisioning, deployment, commit hoặc push trong
batch này. Token estimate vẫn không phải tokenizer/billing guarantee. Abort ở
client không bảo đảm provider ngừng xử lý request đã gửi.

## Closure Receipt

- CURRENT_TASK.md: updated — completion, files, checks, next Phase3.4.
- IMPLEMENTATION_LOG.md: appended — Phase3.2/3.3 evidence và fixes.
- SESSION_BRIEF.md: updated — active milestone, HEAD1056408 + uncommitted edits.
- PROJECT_CONTEXT_CARD.md: updated — accepted source/mock milestone.
- DECISION_LOG.md: not needed — contract/provider/product decisions unchanged.
- RISK_REGISTER.md: not needed — existing provider/runtime gates unchanged.
- REPO_MAP.md: regenerated — local index vẫn không hỗ trợ Dart; source read là evidence.
