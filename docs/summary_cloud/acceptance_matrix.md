# Ma trận nghiệm thu — Summary Cloud Phase 1 (fixtures giả lập)

## Cập nhật Phase2 — 2026-09-30

Các trạng thái trong bảng Phase1 phía dưới là baseline lúc soạn. Bằng chứng
backend mới:30 runtime mocks,8 quota mocks,7 CDK checks và Lambda composition
missing/placeholder/rotation/recovery đã pass; typecheck pass. Backend validation,
provider I/O/output/usage guards và quota/resource đã có code production.
Dart pipeline4+1, consent UI, ownership/snapshot guards và semantic quality vẫn
đang chờ Phase3/4/5. CDK dùng dummy Lambda, không xác minh complete Amplify
auth/SSM hoặc gateway/Dynamo/DeepSeek thật. Xem [handoff Phase2](phase2_backend.md).

Phạm vi batch: contract + fixtures + checks offline. **Không** có endpoint, adapter,
consent UI, quota hay provider call nào được chạy trong batch này.
Nguồn: [docs/summary_api_contract.md](../summary_api_contract.md) (v0.3) ·
Fixtures: [note_fixtures.json](note_fixtures.json) (10 case, worker 2) ·
Wire cases: [wire_cases.json](wire_cases.json) + [check_contract.py](check_contract.py) (worker 1).

## Cách đọc trạng thái

| Nhãn | Nghĩa |
| --- | --- |
| **fixture đã soạn** | Fixture tồn tại và tự-check offline đã chạy; **không phải** bằng chứng hành vi sản phẩm |
| **chờ mock** | Cần mock provider + test orchestrator (đếm call, stage, cardinality) ở phase implementation |
| **chờ UI** | Cần widget/UI test cho thông báo, trạng thái nút và dữ liệu giữ lại |
| **chờ live** | Cần provider smoke với note giả lập + review provider/data disclosure |
| **chờ backend** | Cần enforce phía server (quota, validate, log policy) |
| **kiểm tĩnh** | Không fixture hóa được; xác minh bằng code review/diff khi implement |
| **thiếu fixture** | Chưa có case riêng; ghi rõ để không đánh dấu passed |

Nguyên tắc kiểm: `expectedFacts`/`forbiddenClaims` được kiểm theo **dữ kiện quan sát
được**, không so khớp nguyên văn; không golden wording; không benchmark chọn threshold;
không đánh dấu một hàng là passed chỉ vì fixture JSON hợp lệ.

## A. Routing và ngân sách token (16k / 128 / 256 / 4+1)

| # | Yêu cầu contract | Fixture | Cách xác minh ở phase sau | Trạng thái |
| --- | --- | --- | --- | --- |
| A1 | Direct đúng 1 call khi snapshot + prompt vừa 16.000 input token; output ≤256 | `fx-vi-direct-01`, `fx-en-direct-02` | Mock đếm call: `stage=direct`, `inputs` đúng 1 string, không merge; đọc `max_tokens=256` trong request backend dựng | chờ mock |
| A2 | Note dài: 2–4 section + **đúng một** merge, tổng ≤5 call; merge là bước cuối, không recursive merge, không direct sau merge | `fx-account-switch-08`, `fx-section-truncated-09`, `fx-rate-limit-timeout-10` (chạy nhánh không lỗi) | Mock cho pipeline chạy trọn trên cùng descriptor: đếm 2–4 section + 1 merge = N+1 ≤5, `stage_plan[-1]=merge`, không call thứ 6 | chờ mock |
| A3 | Hơn 4 chunk bị chặn **trước generation đầu tiên** (`pipelineTooLarge`), không cắt nội dung cho vừa budget | `fx-oversize-budget-06` | Mock assert 0 generation call; UI hiện lỗi an toàn "quá lớn", không hiện lỗi provider | chờ mock (fixture đã soạn) |
| A4 | Section output ≤128, direct/final ≤256; `finish_reason=length`/filtered/aborted không thành công | `fx-section-truncated-09`, `fx-vi-direct-01`, `fx-account-switch-08` | Mock bơm `finish_reason` biến thể và `usage`; assert không có summary ở nhánh `length`; wire cases kiểm envelope | chờ mock |
| A5 | Body ≤256 KiB UTF-8 là guard transport **tách biệt** ngân sách token; không quy đổi byte/ký tự thành token | `fx-oversize-budget-06` (byte guard **không** chạm), `wire_cases.json` transport_cases | Checker wire đã chạy offline; mock generator 262.144 ± 1 byte; fixture assert `tokenBudgetCheck.trips=true` nhưng `bodyBytesCheck.trips=false` | wire offline đã chạy; mock chờ |

## B. Toàn vẹn dữ kiện, ngôn ngữ và prompt injection

| # | Yêu cầu contract | Fixture | Cách xác minh ở phase sau | Trạng thái |
| --- | --- | --- | --- | --- |
| B1 | Inputs là **dữ liệu**, không phải system instruction; client không gửi `model`, `max_tokens`, system prompt, provider key | `fx-prompt-injection-04` | Mock chụp request: chỉ có `stage`/`inputs`/`consent`; prompt do backend dựng; assert stage/cardinality không đổi theo câu lệnh trong note | chờ mock + chờ live |
| B2 | Bảo toàn tên, số, ngày giờ, phủ định, ý chính; không bịa dữ kiện | `fx-vi-direct-01`, `fx-en-direct-02`, `fx-mixed-language-03`, `fx-prompt-injection-04` | Đọc summary theo rubric `expectedFacts`/`forbiddenClaims` (không so nguyên văn); có thể lặp ở live smoke với note giả lập | chờ mock; chờ live |
| B3 | Trộn ngôn ngữ xử lý theo nguồn, không theo app locale; không thêm call chỉ để phát hiện ngôn ngữ | `fx-mixed-language-03` | Mock assert vẫn direct 1 call; đọc summary kiểm giữ cả hai nguồn, không dịch toàn bộ | chờ mock |
| B4 | Chia chunk giữ thứ tự và ký tự Unicode; không mất đầu/cuối snapshot | `fx-account-switch-08`, `fx-section-truncated-09` (descriptor 2 chunk) | Mock ghép lại inputs của section và so với snapshot sau trim (chuỗi và byte UTF-8); assert không mất dấu tiếng Việt | chờ mock |
| B5 | Output rỗng/không hợp lệ không được biến thành HTTP 200 | `fx-section-truncated-09`, `wire_cases.json` provider_cases | Oracle provider offline đã chạy; mock bơm text rỗng, `finish_reason` lạ | wire offline đã chạy; mock chờ |

## C. Consent, account, snapshot và Cognito

| # | Yêu cầu contract | Fixture | Cách xác minh ở phase sau | Trạng thái |
| --- | --- | --- | --- | --- |
| C1 | Consent tắt/hủy → không gửi generation request; không tự bật lại | `fx-consent-off-07` | Mock assert 0 HTTP request; UI test: nút Hủy giữ consent tắt, không hiện lỗi provider | chờ mock + chờ UI |
| C2 | Mỗi request khai báo `accepted=true` + `version=summary-cloud-v1`; consent theo **phiên**, logout/đổi account/khởi động lại phải đồng ý lại | `fx-consent-off-07`, `fx-account-switch-08`, `wire_cases.json` request_cases | Mock/oracle kiểm body consent sai kiểu/false/sai version → 403 `consentRequired`; UI test đổi account bắt consent lại | wire offline đã chạy; mock/UI chờ |
| C3 | Đổi account giữa pipeline → dừng stage tiếp theo, bỏ kết quả không còn hợp lệ | `fx-account-switch-08` | Mock đổi account sau section 2: không gửi merge; variant `snapshot_changed` đổi snapshot sau section 1: không gửi section 2. Không hiển thị/lưu intermediate sai state | chờ mock |
| C4 | Body rỗng sau trim → chặn; note chưa lưu/conflict/xóa/account khác/protected → chặn hoặc bỏ kết quả; note chưa sync **được phép** gửi snapshot sau consent, không tạo note/index trên server | `fx-empty-note-05`, mô tả trong `fx-account-switch-08`; variants `unresolved_conflict`, `protected_note`, `foreign_owner`, `dirty_or_deleted`, `saved_unsynced` | Mock assert 0 request cho note rỗng; mock dựng biến thể conflict/protected/xóa; kiểm backend không đọc DynamoDB notes theo id client gửi | chờ mock |
| C5 | 401 → refresh Cognito **tối đa một lần** trước generation; không tự retry generation | `fx-consent-off-07` variant `expired_after_refresh`, `fx-rate-limit-timeout-10` | Mock trả 401 hai lần: assert đúng 1 refresh, sau đó `unauthorized`, 0 generation retry | chờ mock + chờ backend |

## D. Lỗi, quota, timeout và gateway

| # | Yêu cầu contract | Fixture | Cách xác minh ở phase sau | Trạng thái |
| --- | --- | --- | --- | --- |
| D1 | Một section lỗi → dừng pipeline **atomic**, giữ note/summary cũ, không chấp nhận kết quả một phần | `fx-section-truncated-09` | Mock cho section 1 `length`: assert không gọi merge, không có summary, state cũ nguyên vẹn | chờ mock |
| D2 | 429 kèm `Retry-After` hợp lệ → lỗi an toàn, **không** auto retry; Retry/Regenerate do người dùng là thao tác mới, có thể tính phí/quota | `fx-rate-limit-timeout-10` | Mock backend quota trả 429 trước generation của section 2 (2 HTTP requests, 1 generation): assert dừng pipeline, có thời gian chờ, không retry tự động; UI hiện lỗi an toàn | chờ mock + chờ UI |
| D3 | Deadline: DeepSeek 20s, Lambda 28s, integration 30s, Flutter 35s/request, tổng pipeline 150s; hết deadline không gửi stage mới; abort không bảo đảm provider dừng | `fx-rate-limit-timeout-10` (variant `timeout_after_dispatch`) | Mock trì hoãn để chạm deadline: assert không có stage mới sau deadline, không summary; không khẳng định provider đã dừng | chờ mock |
| D4 | Quota **10 stage request/phút/account** enforce ở server; trần 5 call phía client và `requestId` không phải cơ chế chống lạm dụng | `fx-rate-limit-timeout-10` (nhánh 429) | Test backend đếm theo account đã xác thực (không phải throttle toàn API); mock xác nhận 429 khi vượt | chờ backend |
| D5 | Gateway trả body ngoài envelope → map theo status, dùng lỗi an toàn, không hiện raw provider response/exception | `fx-section-truncated-09`, `fx-rate-limit-timeout-10`, `wire_cases.json` response_cases | Oracle response offline đã chạy; mock bơm body HTML/timeout integration; UI test không lộ raw text | wire offline đã chạy; mock/UI chờ |

## E. Dữ liệu, log, remote mode và UI

| # | Yêu cầu contract | Fixture | Cách xác minh ở phase sau | Trạng thái |
| --- | --- | --- | --- | --- |
| E1 | Không log JWT, provider key, inputs hoặc summary text; chỉ metadata `requestId`/stage/latency/usage/error code | `fx-consent-off-07`, `fx-account-switch-08`, `fx-section-truncated-09`, `fx-rate-limit-timeout-10` | Bắt log trong mock run + code review; assert không có nội dung note/summary trong log | kiểm tĩnh + chờ backend |
| E2 | Không persist input/section summary vào DB hoặc storage; intermediate chỉ ở bộ nhớ, mất khi đóng app | `fx-account-switch-08`, `fx-section-truncated-09` | Mock/UI assert không ghi DB; reload app không còn section summary trung gian | chờ mock |
| E3 | Remote mode **không tải GGUF**, không dùng local worker/ngưỡng 20.000 ký tự/tỷ lệ 2 ký tự-token | không có fixture note (kiểm tĩnh) | Code review diff remote path: không dependency/native mới, không download model, không fallback local | kiểm tĩnh; chờ implementation |
| E4 | Chỉ dùng note giả lập cho smoke; review provider/data disclosure trước khi dùng note thật | toàn bộ 10 case `synthetic: true`, không có dữ liệu cá nhân/JWT/key thật | Kiểm `synthetic: true` + quét mẫu secret offline; live smoke chỉ chạy trên fixture này sau review | fixture đã soạn; chờ live |
| E5 | Copy/Regenerate/Retry giữ hành vi cũ; lỗi giữ note/summary cũ; thông báo không lộ chi tiết provider | `fx-consent-off-07`, `fx-section-truncated-09`, `fx-rate-limit-timeout-10` | Widget test: lỗi không xóa note/summary; Copy dùng summary hiện có; Retry do người dùng chủ động | chờ UI |

## Bằng chứng đã có trong batch này

- **Fixture giả lập**: 10 case / 5 nhóm × 2, `schemaVersion: 1`, `synthetic: true`; ID ổn định
  `fx-vi-direct-01` … `fx-rate-limit-timeout-10`, mỗi case có `scenario`, `expectedStagePlan`,
  `expectedGenerationCalls`, `expectedOutcome`, `expectedFacts`, `forbiddenClaims`.
- **Tự-check offline (chạy thật, stdlib, không gọi mạng/API)**: parse JSON; đúng 3 khóa top-level;
  10 ID duy nhất; 5 nhóm × 2; content không rỗng cho case eligible; descriptor expansion khớp
  (`expandedChars`/`expandedUtf8Bytes` = content + unit × repeatCount, tính theo UTF-8);
  plan/call ≤ 5 và đúng dạng direct hoặc 2–4 section + 1 merge cuối; `minimalChunksAtThisBudget`
  khớp ngân sách 16.000; quét mẫu JWT/AWS key/API key/email/số điện thoại — không thấy.
- **Wire checker (worker 1 sở hữu)**: `python3 docs/summary_cloud/check_contract.py` → `PASS: 87 fixture cases`
  cho `wire_cases.json`. Đây là bằng chứng **wire-case offline**, không bao gồm note fixtures và
  không phải bằng chứng runtime/provider.

## Gate còn mở — không được đánh dấu passed

1. **Implement**: chưa có endpoint `/ai/summary`, adapter, orchestration Dart cho direct/chunk/merge,
   consent UI, quota, hay mock harness. Mọi hàng "chờ mock/UI/backend" ở trên đang **pending**.
2. **Tokenizer/counting**: chiến lược đếm token (tokenizer tương thích hay estimate có headroom)
   chưa được chọn; mọi số token trong fixture là **giả lập cố định**, không phải phép đo.
3. **Live provider**: chưa gọi DeepSeek Summary API, chưa có smoke, chưa review data disclosure.
4. **Bằng chứng cấu trúc**: MCP graph tools không gọi được trong phiên này; local index ở HEAD
   `f3e894a` có 4.383 symbol nhưng **không phủ Dart**, nên đối chiếu là đọc trực tiếp
   `lib/domain/note_intelligence/i_note_summarization_service.dart`,
   `lib/application/note_intelligence/note_summary_app_service.dart`,
   `lib/application/notes/note_application.dart`,
   `lib/infrastructure/note_intelligence/local_summarization_service.dart`. Runtime chưa bị thay đổi.
5. **Variants đã soạn, kiểm thử runtime pending**: `saved_unsynced`, `unresolved_conflict`,
   `protected_note`, `foreign_owner`, `dirty_or_deleted`, `expired_after_refresh`,
   `snapshot_changed`, `timeout_after_dispatch`. Tất cả là state giả lập; protected
   model và runtime guards chưa tồn tại trong slice này.

Phân biệt rõ: **fixture đã soạn** ≠ **hành vi sản phẩm đã pass**. Không hàng nào trong ma trận
này là kết quả runtime, mock hay provider thật.

## Lệnh kiểm tra note fixtures

```bash
python3 docs/summary_cloud/check_notes.py
```

Checker này kiểm tra schema, descriptor expansion, kế hoạch/call count giả lập và
mapping ID trong matrix. Nó không tạo summary, không đếm token thật và không
xác minh semantic quality hoặc hành vi UI/backend. Case 429 tại section 2
phân biệt 2 HTTP requests và 1 generation vì quota chặn trước provider; timeout
không cung cấp bằng chứng về số generation đã được provider tính phí.
