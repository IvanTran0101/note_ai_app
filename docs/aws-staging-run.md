# Chạy app với AWS staging và DeepSeek thật

## Mở ngay

Mở http://127.0.0.1:8780. Đây là `lib/main.dart`, Cognito thật và Summary remote, khác demo fixture ở port 8776. Browser đang giữ tài khoản synthetic để xem hai note smoke; tài khoản này chưa xác minh email và không nhận email test.

## Khởi động lại khi server đã dừng

```sh
cd "/Volumes/Kingsman/Projects/Schools/NoteFlow/note_ai_app"
flutter run --no-pub -d chrome -t lib/main.dart --web-port=8780 \
  --dart-define-from-file=output/aws-smoke/dart-defines.json
```

Không khởi động thêm server trên port 8780 nếu terminal hiện tại còn chạy. Browser mới có thể cần đăng nhập bằng tài khoản staging của bạn. Profile AWS chỉ dành cho CLI/backend; không phải tài khoản đăng nhập app.

## Các file cấu hình

- `output/aws-smoke/amplify_outputs.json`: public configuration của đúng sandbox.
- `output/aws-smoke/dart-defines.json`: public Cognito configuration, labels enabled, AI remote. Không chứa DeepSeek key hoặc AWS credentials.
- `DEEPSEEK_API_KEY`: encrypted backend sandbox secret, không nằm trong Flutter.
- `.env` tại thư mục gốc vẫn chưa tồn tại; không cần tạo để chạy cấu hình staging đã chuẩn bị này. `lib/amplify_outputs.dart` giữ nguyên.

Cấu hình sandbox: `noteflow-dev / ap-southeast-1 / noteflow-smoke`. Không dùng public outputs của sandbox khác. Helper `tool/m06_dev_config.py` chỉ lọc cấu hình public; không đưa key vào file --dart-define-from-file.

## Đã kiểm chứng

Cognito SRP login, note autosave/All synced, direct Summary và hai chunk -> merge thành công trên Web. CloudWatch ghi nhận 4 DeepSeek calls (4,395 input / 179 output tokens). 59 Flutter tests liên quan và analyzer pass; không chạy toàn bộ suite.

## Giới hạn và chi phí

$5 là ngưỡng theo dõi AWS thủ công, không phải hard cap. Cost Explorer có độ trễ; số $0 estimated hôm nay không chứng minh chi phí staging bằng 0. DeepSeek có ngân sách riêng; 5/12 attempts được ghi bảo thủ, 4 calls thực tế. Không tự chạy thêm generation sau smoke. Tài nguyên AWS vẫn tồn tại sau khi dừng Flutter; cần chỉ thị riêng trước teardown.

RAG chưa bật. Mail verification/recovery/SES, native hoặc HTTPS S3 upload/finalize/download, sharing/realtime và protection chưa được smoke này kiểm chứng. Chỉ dùng note giả trong sandbox cho đến khi các gate dữ liệu thật được chốt.

Known UI issue: khi đang ở editor vừa tạo và autosave, New note có thể giữ editor cũ. Nhấn Back rồi New note để tạo note tiếp theo. Lỗi này được ghi riêng; lỗi revision stale trước Summary đã được sửa.

## Prompt Summary cập nhật — 2026-10-06

Lambda staging đã nhận prompt ngắn: direct/merge tối đa 2 câu, 45 từ; section tối đa 1 câu, 25 từ. Trần 128/256 token và kiểm tra kết quả đầy đủ được giữ nguyên.

Nếu app đã mở từ trước, đợi autosave rồi nhấn `R` viết hoa trong terminal Flutter để nạp lại asset policy. Server 8780 của smoke đã restart; server 8781 của bạn chưa bị can thiệp.

Các số 4 calls/5 attempts ở phần smoke trên là bằng chứng lịch sử. Khi đối chiếu log lại, có 13 staging events cộng 2 diagnostic calls và 1 lượt bị chặn: tổng bảo thủ 16. Agent không gọi thêm API trong đợt sửa này; cần quyết định mới về giới hạn lượt trước khi chạy thêm paid verification.

Xem `_agent_ops/reviews/summary-prompt-fix-2026-10-06.md` để phân biệt checks offline, diagnostic trước đó và metadata deployment.
