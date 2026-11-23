# Chạy thử local trên macOS

## Mở ngay

Nếu services đang chạy, mở http://127.0.0.1:8776/?devUser=owner.
Recipient: http://127.0.0.1:8776/?devUser=recipient trong browser profile riêng.
Share tới `recipient@example.invalid`. Đây là hai actor tổng hợp, không phải
Cognito accounts. Không cần password, AWS credentials hoặc DeepSeek key.

## Khởi động lại

Từ `/Volumes/Kingsman/Projects/Schools/NoteFlow/note_ai_app`:

```sh
output/m06-local/python-env/bin/python tool/run_m06_local.py
```

Launcher khởi động backend8796, socket8797/control8798 và Chrome8776. Chỉ chạy
một launcher; nếu đang chạy, giữ terminal đó hoặc Ctrl+C để dừng trước khi mở
lại. Không xóa `output/m06-local` hoặc browser data: đây là ciphertext/key/outbox
đã lưu. `--serve-only` dùng khi muốn chạy Flutter trong terminal riêng.

Môi trường Python trên máy này đã được tạo trong ignoredoutput và có
`websockets==15.0.1`, là dependency của fixture hiện có. Nếu setup trên máy mới:

```sh
npm ci --no-audit --no-fund
python3 -m venv output/m06-local/python-env
output/m06-local/python-env/bin/python -m pip install websockets==15.0.1
output/m06-local/python-env/bin/python tool/run_m06_local.py
```

Cần Flutter/Chrome và Node trên PATH. Lockfile đã bổ sung4OpenTelemetrypeer
records, giữ nguyên tất cả version cũ. Các đường dẫn D:/R: trong teammate docs
là setupWindows; không cần trên macOS.

## .env ở đâu?

Đường dẫn dự kiến: `/Volumes/Kingsman/Projects/Schools/NoteFlow/note_ai_app/.env`.
Tại lúc kiểm tra chưa cófile này; template là `.env.example` cùng thư mục.
Không có secret/env thật nào được tạo hoặc sửa bởi đợt fix.

**Demo M06/M03 trênmain_dev:** launcher không đọc.env, không cần.env.
**Standalone local-user trênmain.dart:** user có thể copytemplate thành.env,
giữ `NOTEFLOW_AUTH_MODE=local`, chạy helper để lọc publicdefines:

```sh
cp -n .env.example .env
python3 tool/m06_dev_config.py prepare
flutter run -d chrome --dart-define-from-file=output/m06-dev/dart-defines.json
```

Standalone mode không cung cấp hai actor/share gateway như main_dev.
Flutter không tự đọc.env. Không truyền.env trực tiếp vào dart-define-from-file;
helper chỉ xuất các trường public cần thiết.

## Khi dùng dev deployment thật (không cần cho demo local)

`.env` cần `NOTEFLOW_AUTH_MODE=cognito` và
`NOTEFLOW_AMPLIFY_OUTPUTS_FILE=.env.amplify-outputs.json`. Fileoutputs là cấu hình
public của deployment đã chọn: auth region/pool/client và custom sync/events
endpoints. Labels chỉ bật sau khi backendtypedv2 tương ứng sẵn sàng.
AWS_PROFILE/AWS_REGION hoặc temporaryoperatorcredentials chỉ dành cho backend
wrapper; không phải credentials đăng nhập của user trong app.
DeepSeekAPIkey dùng secret backend trong Phase5, không đưa vào Flutter hoặc
.env mà publicconfigurationhelper đang đọc (helper không nhận field này).

## Giới hạn của local demo

CRUD,labels,attachments và sharing/realtime chạy với productionusecases + SDK
fixtures. Không chứng minh IAM/S3/Cognito/SES live. Không gửi recoveryemail thật.
Summarylocal trênWeb không khả dụng; cần approvedclouddeployment để thử
DeepSeek. RAG chưa implement. Script không gọi DeepSeek/AWS hay deploy.

## Receipt

P1bucketIAM fixed; genuine403stilldenied. P2projection maps malformed/schema
inputto422nonretryable and retains security/serverclasses. RestoredAIcoverage
usesv0.4fixtures, realLambdacomposition with SDK/fetch doubles and deadline checks.
See `_agent_ops/reviews/p1-p2-fix-implementation-2026-10-06.md` for final checks.
