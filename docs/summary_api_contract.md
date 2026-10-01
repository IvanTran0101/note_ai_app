# Contract Phase 1 — Summary Cloud qua DeepSeek

Phiên bản: **0.3 — Phase 1: contract + fixtures + checks**

Cập nhật: **2026-09-30**
Phạm vi đã được user xác nhận: hoàn thành Phase 1 bằng contract, fixtures và
checks offline. Endpoint, adapter, consent UI và deployment thuộc phase sau.

## 1. Quyết định và thay đổi so với đề xuất trước

Giữ `INoteSummarizationService.summarize(String content) → Future<Summary>`.
Flutter điều phối direct/chunk/merge; backend thực hiện một generation cho mỗi
request, giữ provider key và tự xây prompt. Web và Native dùng cùng remote path.

| Hạng mục | Mặc định đã được yêu cầu đưa vào contract |
| --- | --- |
| Provider | `deepseek-flash`, tắt thinking, không streaming |
| Direct / chunk | Tối đa **16.000 input tokens cho mỗi generation**, tính cả prompt và cấu trúc message |
| Section output | Tối đa **128 tokens** |
| Direct / final output | Tối đa **256 tokens** |
| Pipeline | Tối đa **4 chunks + 1 merge = 5 generation calls**; không tự retry generation |

Thay đổi chính:

- API nhận `stage` và `inputs`, thay body chỉ có `content`.
- Bỏ ngưỡng 20.000 ký tự cho toàn note; giới hạn theo budget token và tối đa 4 chunks.
- Không dùng lại context 2k/4k hoặc tỷ lệ 2 ký tự/token của local GGUF.
- Dùng một lần merge cuối; recursive merge không thuộc cấu hình này.
- Không yêu cầu benchmark chọn threshold. Kiểm thử correctness vẫn bắt buộc khi triển khai.

16.000 là giới hạn vận hành do ứng dụng chọn, không phải context limit của
DeepSeek. Đây là mặc định tiết kiệm để review, không phải bằng chứng tối ưu toàn cục.

## 2. Điều kiện sử dụng và consent

| Trạng thái | Hành vi |
| --- | --- |
| Account Cognito đang đăng nhập; note của account, đã lưu, không conflict | Cho phép sau consent |
| Note đã lưu local nhưng chưa sync | Cho phép gửi snapshot sau consent; không tạo bản note trên server hoặc index |
| Note có thay đổi chưa lưu hoặc conflict | Chặn đến khi lưu hoặc giải quyết conflict |
| Note đã xóa, thuộc account khác, hoặc được bảo vệ | Chặn; protected notes chỉ được mở rộng sau khi có quy tắc riêng |
| Chưa consent, hết phiên, hoặc không có mạng | Không gửi generation request |

Hiện chưa có protected-note model. Contract này không tuyên bố đã có khóa/unlock
hoặc hỗ trợ sharing. Nếu thêm cờ cấm gửi cloud sau này, phải kiểm tra cờ đó trước
mọi stage. "Chưa sync" không đồng nghĩa "cấm gửi cloud".

Consent mặc định tắt. Thông báo đề xuất:

> Nội dung note bạn chọn sẽ được gửi đến DeepSeek để tạo bản tóm tắt. Cho phép
> Summary Cloud trong phiên đăng nhập này?

Hai lựa chọn: **Hủy** và **Cho phép**. Consent gắn với account trong bộ nhớ của
phiên; logout, đổi account hoặc khởi động lại app phải đồng ý lại. Settings có
thao tác tắt. Tắt consent chặn các stage tiếp theo và bỏ kết quả không còn hợp
lệ; không thu hồi nội dung đã gửi cho provider.

Mỗi request khai báo `accepted: true` và đúng `version: "summary-cloud-v1"`.
Backend từ chối khai báo thiếu, sai kiểu, false hoặc sai version. Đây là consent
được khai báo theo request, không phải bản ghi consent bền vững hoặc bằng chứng
kiểm toán server-side.

Flutter kiểm tra ownership trên note local. Backend xác thực caller và validate
dữ liệu gửi lên; không thể chứng minh ownership của một chuỗi văn bản tùy ý.
Endpoint không đọc note bằng identifier do client gửi và không cần quyền đọc
DynamoDB notes. Chỉ dùng note giả lập cho spike; rà soát provider/data disclosure
trước khi sử dụng note thật. NoteFlow không lưu input/section summaries vào
database hoặc logs; điều này không hứa rằng DeepSeek không lưu dữ liệu.

## 3. API request và response

### Request

```http
POST /ai/summary
Authorization: Bearer <Cognito access token>
Content-Type: application/json
```

```json
{
  "stage": "section",
  "inputs": ["Nội dung một đoạn đã chia"],
  "consent": {
    "accepted": true,
    "version": "summary-cloud-v1"
  }
}
```

| Stage | Inputs | Provider output budget |
| --- | --- | --- |
| `direct` | Đúng 1 string: toàn snapshot note nằm trong input budget | 256 tokens |
| `section` | Đúng 1 string: một chunk | 128 tokens |
| `merge` | 2–4 strings: section summaries của cùng snapshot, đúng thứ tự | 256 tokens |

Body phải là JSON object đúng schema. Strings phải không rỗng sau trim. Backend
chỉ trim whitespace ở rìa; không tự bỏ đoạn hoặc rút gọn nội dung để làm vừa
budget. Chặn request body vượt **256 KiB UTF-8** trước khi xử lý generation.
Đây là guard transport bổ sung, không phải cách chuyển byte thành token.

Không nhận `ownerId`, provider key, `model`, `max_tokens`, system prompt, URL
provider hoặc các trường tùy ý. Backend xây prompt từ stage và inputs đã validate.
Client không gửi generation prompt hoàn chỉnh.

### Thành công — HTTP 200

```json
{
  "summary": "Bản tóm tắt hợp lệ…",
  "requestId": "server-generated-id",
  "usage": {
    "inputTokens": 1200,
    "outputTokens": 95
  }
}
```

`summary` là string không rỗng sau trim. Backend chỉ chấp nhận output text kết
thúc bằng `finish_reason: "stop"`; `length`, filtered, aborted hoặc output
không hợp lệ không được biến thành thành công. Usage phải được kiểm tra schema
trước khi trả; không tự tạo số token khi provider không cung cấp. `requestId`
do server tạo cho mỗi HTTP request, không dùng để suy ra quyền hoặc idempotency.

### Thất bại

```json
{
  "error": { "code": "timeout" },
  "requestId": "server-generated-id"
}
```

| HTTP | Code / điều kiện |
| --- | --- |
| 400 / 413 | `invalidInput` / `inputTooLong`: schema, stage, cardinality, token hoặc body budget |
| 401 / 403 | `unauthorized` / `consentRequired` |
| 429 | `rateLimited`; thêm `Retry-After` khi có thời gian chờ hợp lệ |
| 502 | `providerUnavailable` / `invalidOutput` |
| 504 / 500 | `timeout` / `unexpected`: lỗi deadline hoặc backend không phân loại được |

Gateway có thể trả body khác envelope, đặc biệt khi authorizer từ chối hoặc
integration timeout. Flutter phải map theo status và dùng lỗi an toàn khi body
không đúng schema. Không hiển thị raw provider response/exception cho user.

## 4. Token budget và orchestration

Yêu cầu cho phase backend: backend kiểm soát 16.000-token input cap. Phải đếm/ước lượng toàn bộ
messages sau khi thêm prompt, wrappers và inputs. Flutter dùng policy tương
thích để chia đoạn; việc client báo vừa budget không thay thế validation server.

Ưu tiên tokenizer tương thích với model. Nếu dùng estimate, phải khai báo đó là
estimate, có headroom bảo thủ và không coi tỷ lệ 2 ký tự/token của local là sự
thật. `usage` từ provider dùng để ghi nhận số thực tế, không thêm một API call
để đếm token. Cách đếm cụ thể là chi tiết implementation cần xác định trước khi
enable remote adapter, không yêu cầu benchmark tối ưu threshold.

```text
Capture snapshot + account + consent
  → Nếu direct prompt + note vừa budget: 1 direct call → kết quả cuối
  → Nếu không: split theo ranh giới văn bản, bảo toàn thứ tự/nội dung
      → hơn 4 chunks: báo pipelineTooLarge trước generation đầu tiên
      → 2–4 section calls tuần tự
      → kiểm tra merge prompt + section summaries vừa budget
      → 1 merge call → kết quả cuối
```

Một summary dài gồm N chunks có N + 1 generation calls; N tối đa 4. Section
outputs được tính phí khi sinh ra, rồi được tính là input ở lần merge. Không
gọi thêm một direct summary sau final merge.

Với tối đa 4 section outputs × 128 tokens, dữ liệu merge dự kiến rất nhỏ so với
cap 16.000, nhưng backend vẫn validate prompt hoàn chỉnh. Nếu merge không vừa
budget hoặc output bị cắt, báo lỗi; không chia thêm hoặc recursive merge để
vượt trần 5 calls. Không chấp nhận một phần kết quả làm summary hoàn chỉnh.

Trước mỗi stage kiểm tra account/consent; trước hiển thị kiểm tra account,
note id và snapshot còn hợp lệ. Nếu một section lỗi, dừng pipeline, giữ note
và summary cũ. Intermediate summaries chỉ ở bộ nhớ; không persist khi app đóng.

Đây là yêu cầu dành cho phase runtime: orchestrator Dart phải enforce trần 5
generation calls cho một thao tác UI.
Backend stateless theo stage không thể xác minh client đã dùng bao nhiêu calls
cho toàn note; quota theo account phải enforce riêng ở server. Không coi trần
client hoặc requestId là cơ chế chống lạm dụng server-side.

## 5. Prompt, thời gian và quota

Backend gọi Chat Completions với `model: "deepseek-flash"`,
`thinking: {"type": "disabled"}`, `stream: false`, và `max_tokens` theo stage.
Provider trả plain text; backend tự đóng gói JSON response, không cần JSON mode
để bắt model tạo transport envelope.

| Stage | Chính sách prompt |
| --- | --- |
| `direct` | Tóm tắt dữ kiện trong note; giữ ngôn ngữ, không theo app locale |
| `section` | Giữ tên, con số, thời điểm, phủ định và ý chính phục vụ merge |
| `merge` | Hợp nhất theo thứ tự, tránh lặp; không tự giải quyết mâu thuẫn bằng cách đoán |

Inputs được coi là dữ liệu, không phải system instructions. Nội dung trộn ngôn
ngữ phải được xử lý theo nguồn; không thêm một generation call chỉ để phát hiện
ngôn ngữ. Output 128/256 tokens ưu tiên summary ngắn, có thể mất chi tiết phụ;
không hứa 80–150 từ hoặc cố cắt output để đạt số từ.

Các giới hạn vận hành sau được giữ trong plan Phase 1 mà user đã yêu cầu thực
hiện. Chúng là cấu hình dự kiến cho phase implementation sau, không phải kết
quả benchmark hoặc deployment đã có:

| Giới hạn | Giá trị đề xuất |
| --- | --- |
| Một generation | DeepSeek deadline 20 giây; Lambda 28 giây; HTTP API integration 30 giây |
| Flutter | Timeout tối đa 35 giây/request; deadline tổng pipeline 150 giây |
| Đồng thời | Một pipeline đang chạy trong UI; backend concurrency/throttle riêng |
| Account quota | 10 stage requests/phút/account; tính cả direct, section và merge |
| Retry | Không tự retry generation; chỉ refresh Cognito một lần sau 401, trước generation |

Quota 10 thay đề xuất cũ 5 HTTP requests/phút để một pipeline tối đa 5 calls
có thể hoàn thành. Backend phải triển khai quota này theo account đã xác thực;
throttle toàn API không tương đương quota account. Retry/Regenerate do người
dùng chọn là một thao tác mới và có thể bị tính phí; batch này không có resume
hoặc deduplication generation. Hết deadline không gửi stage mới; abort client
không bảo đảm provider ngừng xử lý hoặc không tính phí request đã gửi.

## 6. Ước lượng chi phí

Theo giá kiểm tra ngày 2026-09-30: Flash off-peak cache-miss input $0,15/triệu
tokens, output $0,60/triệu tokens. Peak: $0,30 và $1,20. Đây là tham chiếu giá
provider, không phải mức giá cố định trong product hoặc trần thanh toán.

| Tổng input của direct / các section calls | Luồng | Phí tham chiếu off-peak |
| --- | --- | --- |
| 8.000 tokens, gồm prompt | Direct; output tối đa 256 | Khoảng $0,00135/note |
| 16.000 tokens, gồm prompt | Direct; output tối đa 256 | Khoảng $0,00255/note |
| 32.000 tokens, tổng hai section calls gồm prompt của chúng | Hai section outputs 128 + merge output 256 | Khoảng $0,00515/note, chưa gồm prompt/wrappers của merge |

Các mốc này mô tả input của generation, không phải token nội dung note thuần.
Một note có đúng 16k tokens nội dung sẽ cần chunk nếu thêm prompt làm vượt cap.
Routing luôn theo input đã tính prompt; không bỏ prompt reserve để khớp bảng
giá. Cần headroom nếu dùng estimate; không cố tăng chunk vượt cap để giảm calls.

Ví dụ hai section calls có tổng input 32k: input 32.000 + 256 intermediate-summary tokens; output
256 section + 256 final tokens. Phí = 32.256 × 0,15/1.000.000 +
512 × 0,60/1.000.000 = $0,0051456, chưa tính merge prompt/wrappers và AWS.

Không giả định cache hit. Giá peak hiện gấp đôi ví dụ off-peak. Không trì hoãn
request của user để chờ giờ rẻ; chi phí thực tế dựa trên usage, model và giá ở
thời điểm gọi. Log metadata requestId/stage/latency/usage/error code; không log
JWT, provider key, inputs hoặc summary text.

## 7. Acceptance và phạm vi hoàn thành

Không yêu cầu benchmark 4k/8k/16k hoặc đánh giá so sánh để duyệt bộ mặc định.
Khi triển khai vẫn phải có kiểm thử correctness với mock:

| Nhóm | Điều kiện nghiệm thu |
| --- | --- |
| Routing / budget | Direct 1 call; chunk 2–4 section calls + 1 merge; token cap tính cả prompt; hơn 4 chunks bị chặn trước generation |
| Tính đầy đủ | Bảo toàn thứ tự/chữ Unicode; không mất đầu/cuối; section lỗi hoặc output `length` không trả summary thành công |
| Quyền / consent | Không gửi khi consent tắt; đổi account hoặc snapshot thì dừng các stage tiếp theo/bỏ kết quả sai |
| API / lỗi | Schema/cardinality/transport cap đúng; 401 refresh tối đa một lần; không tự retry provider; xử lý cả gateway body ngoài envelope |
| UI / dữ liệu | Copy/Regenerate/Retry giữ hành vi; lỗi giữ note/summary cũ; không download GGUF trong remote mode; không lưu input hoặc log nội dung |

### Artifacts Phase 1

| Artifact | Vai trò |
| --- | --- |
| [Wire cases](summary_cloud/wire_cases.json) | Case request/provider-response hợp lệ và không hợp lệ; token counts trong case là số giả lập |
| [10 synthetic fixtures](summary_cloud/note_fixtures.json) | Note/scenario giả lập với required facts, forbidden claims và expected outcome |
| [Acceptance matrix](summary_cloud/acceptance_matrix.md) | Mapping yêu cầu → fixture → cách xác minh trong các phase sau |
| [Wire checker](summary_cloud/check_contract.py) | Kiểm tra case API bằng oracle offline; không gọi API và không chứng minh endpoint/runtime |
| [Note checker](summary_cloud/check_notes.py) | Kiểm tra 10 note fixtures, descriptor, số call giả lập và mapping trong matrix |

Chạy từ project root:

```bash
python3 docs/summary_cloud/check_contract.py
python3 docs/summary_cloud/check_notes.py
```

Phase 1 hoàn thành khi các artifacts đã có, checks offline thực sự chạy và các
hạn chế được ghi rõ. Không yêu cầu benchmark chọn threshold. Điều đó không có
nghĩa endpoint, consent UI, quota, tokenizer, product tests hoặc DeepSeek smoke
đã được triển khai/chạy. Không đánh dấu các mục runtime trong matrix là passed
chỉ vì checker fixture chạy thành công.

Consent theo phiên, quota 10 stage requests/phút/account, deadlines và transport
cap là các quyết định plan được giữ cho phase sau. Tokenizer/counting strategy,
quota enforcement và provider review vẫn là implementation gates; không giả
định chúng đã tồn tại. Chỉ dùng dữ liệu giả lập cho API smoke ban đầu.

## 8. Nguồn đối chiếu

- [DeepSeek Models & Pricing](https://api-docs.deepseek.com/quick_start/pricing/)
- [DeepSeek Thinking Mode](https://api-docs.deepseek.com/guides/thinking_mode/)
- [DeepSeek Chat Completions](https://api-docs.deepseek.com/api/create-chat-completion/)
- [DeepSeek Token Usage](https://api-docs.deepseek.com/quick_start/token_usage/)
- [AWS HTTP API quotas](https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api-quotas.html)

### Ghi nhận checks Phase 1 — 2026-09-30

Hai DeepSeek Harness workers đã tạo wire cases/checker và 10 note fixtures/matrix
trong hai phạm vi riêng. Root review, làm rõ case 429 (HTTP request khác generation),
thêm note checker và chạy lại cả hai. 87 wire checks và 10 note assets đã qua checks offline. Root sửa descriptor
whitespace và thêm kiểm tra âm cho token giả lập sai kiểu. Không có bằng chứng
hành vi product hoặc DeepSeek smoke.
