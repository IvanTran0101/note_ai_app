# Summary Cloud — Phase 2 backend với mock

Hoàn thành: 2026-09-30. Contract v0.3 đã được user chốt.

## Kết quả

Backend source đã có POST /ai/summary cho direct/section/merge, kiểm tra Cognito
access-token claims do gateway xác thực, consent/schema/body, input estimate,
quota theo account và DeepSeek adapter. Chưa deploy endpoint hoặc đổi provider
Flutter. Hai DeepSeek Harness workers viết runtime và quota/resources ở các
file riêng; GPT-6.1 Sol High control plane review, root tích hợp tại project gốc.

## Các quyết định triển khai

| Phần | Hành vi |
| --- | --- |
| Budget | 16000 **estimated** input tokens = UTF8 bytes của messages JSON +256 framing headroom; không phải tokenizer. Section128/direct-final256 output. Actual usage vượt cap bị từ chối sau call, không thể ngăn phí đã phát sinh. |
| Provider | deepseek-flash, thinking disabled, không streaming; một fetch, không retry/redirect, timeout20s xuyên suốt headers/body, response<=64KiB. |
| Quota | Atomic conditional UpdateItem,10/account/fixed UTC minute; SDK abort4s, handler quota bound5s; TTL chỉ cleanup. Fixed windows có thể burst20 quanh ranh giới phút. |
| Secret | Amplify secret reference DEEPSEEK_API_KEY, resolve lúc runtime; từ chối placeholder chưa resolve. Đọc key mỗi invocation để hỗ trợ refresh/rotation/recovery, chỉ cache quota client. |
| Resources | Function group summary tách khỏi auth/pre-sign-up; API/table cùng stack của summary Lambda. Lambda28s/API30s; CDK L2 29s được override tại đúng CfnIntegration. Quota chỉ UpdateItem, không Notes access. |

Cognito signature/audience được API Gateway kiểm tra; handler yêu cầu sub không
rỗng và token_use=access. Không tin ownerId trong body. Endpoint xử lý plaintext
caller gửi lên, không đọc note theo ID hoặc chứng minh ownership của chuỗi text.

## Chạy checks offline

Từ project root, dùng dependencies đã cài:

```bash
npm run typecheck
node --import tsx amplify/ai/runtime.test.ts
node --import tsx amplify/ai/quota.test.ts
node --import tsx amplify/ai/infrastructure.test.ts
node --import tsx amplify/ai/lambda.test.ts
```

Node loader tránh IPC pipe của tsx CLI trong sandbox. Fixture loader bắt buộc
file tương đối trong repo, không fallback đường dẫn riêng hoặc silent skip.
Tests theo schema/provider/IO/auth-flow/transport, dùng native node assertions.

Kết quả đã chạy:30 runtime checks,8 quota checks,7 CDK checks; Lambda composition
mock kiểm missing key, unresolved placeholder, rotation và recovery. Typecheck
pass. Flutter analyze không có lỗi; flutter test906pass,2intentional skips.

## Giới hạn bằng chứng

- Mocks gọi code production; Phase1 oracle không được tính là backend behavior.
- CDK checks dùng dummy Lambda, không synth/deploy toàn bộ Amplify auth+secret.
- Quota concurrency/abort/IAM template đã kiểm bằng fake SDK/source; chưa có
  bằng chứng DynamoDB service thật hoặc gateway JWT thật.
- Token estimate bảo thủ có thể chia/chặn note vốn vừa context; không hứa cap
  token chính xác. Provider usage check là post-call. Chưa đo chất lượng, latency
  thật hoặc chi phí, không chạy benchmark lựa chọn threshold.
- Chưa cấu hình secret value, gọi Summary API thật, deploy, commit hoặc push.

## Handoff Phase 3

Dùng custom output aiApiEndpoint sau khi được phép deploy; Flutter adapter sẽ
nhận NOTEFLOW_AI_API và gọi ai/summary. Phase3 triển khai Dart orchestration
max4chunks+1merge; Phase4 consent/UI và account/snapshot guards. API smoke thật
chỉ dùng note giả lập khi tới batch được phép; provider/data disclosure review
phải xong trước note thật.

Nguồn đối chiếu: [DeepSeek Chat Completions](https://api-docs.deepseek.com/api/create-chat-completion/),
[Amplify secrets](https://docs.amplify.aws/react/build-a-backend/functions/environment-variables-and-secrets/),
[AWS HTTP API quotas](https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api-quotas.html).
