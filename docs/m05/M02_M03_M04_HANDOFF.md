# Xác minh handoff M02 / M03 / M04 với M05 / M06

Ngày: 02/10/2026. Nguồn code: `final-tuankiet@528a7454ffcaab272aaedba65733dedce65639f6`.
Đối chiếu bảng G1–G5 trong ảnh collab, Notion Implement plan M02/M03/M04,
Planning before code, contract M06 và source hiện tại.

**Kết luận:** hướng đề xuất phù hợp với contract đã chốt. Collab có thể tiếp tục
thiết kế/triển khai M02/M03/M04 theo các ràng buộc dưới đây. Đây là xác minh
contract tích hợp; chưa phải nghiệm thu code của collab hay chứng nhận attachment
đã hoạt động. Chưa có branch/PR/snapshot implementation M02/M03/M04 được cung cấp.

## 1. Phần đã có và phần còn thiếu

- M05 đã có protection/grant/local encryption và Web local-first trong source.
  Backend mới chưa được deploy; source/tests không chứng minh endpoint cloud live.
- M06.1 đã có canonical identity, viewer/editor, share lifecycle, local codecs và
  encrypted retained drafts. M06.2 trở đi đang tạm ngưng; shared ACL/backend,
  recipient HTTP feed, sharing UI và realtime chưa được nghiệm thu.
- `NoteOperation` có `attachmentRead`/`attachmentWrite`; backend authorizer có thể
  kiểm tra các scope này khi caller tích hợp đúng. Chưa có attachment byte endpoint,
  Range handler hoặc encrypted binary cache trong source `lib/` và `amplify/` đã kiểm tra.
- **Hai gap quan trọng:** `NoteSecurityService.unlock()` mặc định chưa yêu cầu/cấp
  attachment scopes; `sync_http_mapper.dart` chưa encode owner/access revision
  của M06 hoặc decode share projection. Không suy ra tích hợp đã xong từ enum/DTO.
  Lease ngay sau enable local có toàn bộ operations, nhưng unlock/reopen mặc định
  không có hai attachment scopes; M03 phải kiểm thử cả hai đường, không chỉ enable.

## 2. G1 — Read transport

**Xác nhận boundary:** đọc metadata riêng tư, thumbnail, preview, actual bytes và
mọi request seek/Range đều thuộc `attachmentRead` của canonical note.

Cloud request phải có actor từ Cognito JWT, canonical `(ownerId, noteId)` được
kiểm tra, note chưa bị xóa, ACL hiện hành và, nếu protected, unlock grant của
chính actor với scope `attachmentRead`, protection revision đúng và chưa hết hạn.
Grant đặt ở `X-Note-Unlock-Grant`; không đưa password/grant vào URL, outbox hoặc log.
Grant M05 hiện mặc định 15 phút; đó không phải TTL đã duyệt cho signed GET.

**Transport:** giữ hướng authenticated streaming/Range làm phương án ưu tiên để
spike. M05 không cấm seek/Range. Spike phải chứng minh player Web/Android thực sự
truyền được authority ở mỗi request, CORS cho headers cần thiết, 206/416,
Content-Range/ETag/version, retry/seek sau expiry và memory không tăng theo toàn file.
Không suy ra video player tự gửi JWT/custom grant chỉ vì HTTP adapter gửi được.

Signed GET hiện **chưa chốt TTL hoặc cơ chế revoke**. S3 presigned URL có thể
được dùng lại đến expiry và là bearer capability; download đã bắt đầu có thể
tiếp tục qua expiry. [AWS S3 documentation](https://docs.aws.amazon.com/AmazonS3/latest/userguide/using-presigned-url.html).
Suy luận cho contract này: chỉ kiểm tra ACL lúc phát URL chưa chứng minh mọi
request sau revoke/password change được chặn. Cần cơ chế kiểm tra/invalidation
phù hợp hoặc một quyết định contract rõ về khoảng trễ; TTL ngắn riêng nó chưa
đủ để claim fresh ACL trên mọi request. Không tự dùng signed GET làm fallback
khi authenticated route từ chối. [HTTP Range reference](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/Range_requests).

**Điểm nối code:** `INoteAccessGuard.requireAccess(..., attachmentRead)` ở local;
`NoteSecurityAuthority.authorize(actor, owner, noteId, 'attachmentRead', grant)`
ở server. M03 phải nối scope issuance + byte route. M06 bổ sung real shared ACL
và recipient-aware runtime; không thay owner guard bằng unconditional allow.

## 3. G2 — File policy và nền tảng

M05/M06 **không có policy file type/size riêng đã chốt**. Cùng boundary áp dụng
cho image, video, general file và derivative/preview. MIME/extension không cấp
thêm quyền; size nhỏ không được bỏ guard hoặc lưu protected plaintext.

Allowlist, max per-file/count/total, filename normalization, local/cloud quota,
timeout và picker/permission thuộc M03; collab chốt số cụ thể rồi ghi README/tests.
Giới hạn JSON/password của API M05 không phải giới hạn binary upload.

Baseline nghiệm thu đã thống nhất là **Web Chrome + Android**. iOS/macOS giữ
runner và regression khi có toolchain; chưa có evidence attachment trên các
platform đó, không tự mở scope Windows native.

Web phải local trước, sync sau. Local quota/crypto/storage thất bại không được
báo Saved, tạo association trỏ file thiếu hoặc fallback sang plaintext.
Chưa có cache quota/eviction attachment từ M05 để M03 dùng ngay.

## 4. G3 — Sync và tương thích backend

| Dữ liệu | Contract cần giữ | Trạng thái hiện tại |
| --- | --- | --- |
| Actor / canonical note | Actor từ JWT; note là `(ownerId, noteId)`, owner không đổi thành recipient | Pair identity/local foundation đã có; shared HTTP integration còn thiếu |
| Content revision | Server `revision`; client `baseRevision`, `mutationId` và attempt history | Existing single sync engine |
| Protection | `protected`, `protectionRevision`, `contentAvailable`; protected feed không title/body/history riêng tư | M05 đã có |
| Access | `NoteShareGrant`: recipientId, role, status, accessRevision, sharedAt/updatedAt/revokedAt | Domain/local codec đã có; backend/feed/wire chưa hoàn thành |
| Protection intent | `protectionChange = {before, after, verifier}` đi cùng content qua durable outbox | M05 dedicated protected-mutations route; older server fail closed |
| Attachment | attachmentId, immutable object version/reference, metadata schema/fingerprint, integrity/size/type | M03 cần định nghĩa; chưa phải fields có thể gửi vào parser hiện tại |

Attachment lấy quyền từ associated note; không tạo một ACL tự do hoặc copy
owner/password/grant theo từng file. Content, protection và access revision là
các epoch độc lập; thay đổi revoke/protection phải được xử lý dù body revision
không tăng hoặc note đang có pending draft.

Filename, thumbnail, extracted text và private attachment metadata cũng cần
authorization. Feed/event cho locked/revoked note chỉ mang metadata an toàn;
không gửi raw URL, grant, private filename hoặc bytes qua feed/realtime.

**Đồng ý hướng compatibility của collab:** metadata versioned, preserve khi
legacy write chỉ sau mixed-version/replay tests chứng minh an toàn; nếu không
đủ bằng chứng thì reject rõ, không silently drop attachment. Backend compatible
deploy trước client; giữ note/cursor/outbox/conflict IDs, ciphertext/AAD và data.

Không thêm fields trực tiếp vào request cũ rồi kỳ vọng parser bỏ qua. Wire mới,
legacy fingerprint và replay phải được thống nhất cùng owner sync/M05/M06.
Một mutation đã attempt không được thay payload/fingerprint dưới cùng mutationId.

## 5. G4 — Quyền và cache local

Ma trận dưới đây là **policy đã có trong Domain M06.1**; shared runtime/backend
phải tích hợp trước khi claim sử dụng được. Mỗi quyền còn chịu M05 protection.

| Action | Owner | ACTIVE editor | ACTIVE viewer | Revoked / không có ACL |
| --- | --- | --- | --- | --- |
| Đọc note / attachment | Có | Có | Có | Không |
| Sửa title/content | Có | Có | Không | Không |
| Thêm / thay / gỡ attachment | Có | Không | Không | Không |
| Share/role/revoke, protection, delete, pin/labels | Owner quản lý | Không | Không | Không |
| Export file ra ngoài cache kiểm soát | Cần policy export + protection | Không theo policy hiện tại | Không theo policy hiện tại | Không |

`canEdit` không đồng nghĩa `canAttachmentWrite`. Editor slice hiện chỉ title và
content. Muốn mở attachment writes cho editor là thay đổi contract, không suy
diễn từ quyền sửa text. Xem nội bộ bằng app khác export ra external app/download;
đường mở file bên ngoài phải được phân loại và kiểm soát rõ.

**Local:** M05 encrypts account note/outbox/conflict envelope và password-wraps
per-note keys. Nó chưa encrypt arbitrary binary files, browser Cache Storage,
thumbnail/temp files hoặc external-player cache. Không reuse note key/ciphertext
format cho video mà không có adapter/format được xác minh.

M03 cần contract binary cache có crypto format/version + key identifier,
account/canonical note/attachment/object-version binding, authenticated chunks
nếu cần seek, crash-safe commit, quota/eviction và cleanup preview/temp.
Protection/access epoch kiểm soát khả năng dùng key/cache; không chỉ một boolean
unlocked cũ. Password rotation/recovery và legacy key wrapping phải có tests;
email reset không khôi phục password-derived key của ciphertext chưa sync.

Lifecycle cần enforce khi M03 tích hợp:

- Lock/expiry/logout/account switch: dừng player/download, bỏ plaintext buffers,
  preview/Blob URL/temp, hủy live key/grant, loại stale async callback. Durable
  encrypted owned notes/drafts được giữ; logout hiện không phải xóa toàn bộ data.
- Khi client **nhận được** revoke/protection epoch mới: persist access trước,
  chặn note-specific mutation/read, clear private view/key/preview; không để
  pending draft hoặc Use local bypass gate. M06.1 đã có note-draft retention,
  chưa có binary-cache implementation để claim attachment cleanup đã pass.
- Re-share: accessRevision mới; không tự replay blocked attempts/draft của epoch
  cũ. Retained encrypted draft là evidence để review, không phải quyền đọc lại.
- Server chặn request mới bằng current ACL. Không thể cam kết xóa tức thời bytes
  đã tải trên một thiết bị đang offline; reconnect phải áp dụng revoke trước sử dụng.

## 6. G5 — Attempt và object authority

**Đồng ý hướng server authority/idempotent retry của collab**, với các bindings:

- Account namespace = JWT actor, canonical owner/note riêng. Attempt gắn actor,
  canonical pair, attachmentId, attemptId, immutable target object version,
  expected manifest/note revision và fingerprint của type/size/checksum.
- Access/protection epochs của attempt phải được kiểm tra với current server
  state; protected write dùng `attachmentWrite`, không dùng grant `edit` thay thế.
  Không persist raw unlock grant trong attempt/outbox/fingerprint.
- Init/read/complete/associate/remove/retry/replay kiểm tra action hiện hành.
  Final attach/remove transaction cần note/manifest conditions và fresh security
  conditions; khi M06 shared writes có scope thì ACL/accessRevision phải tham gia
  conditional commit, không chỉ preflight. Hiện M05 transaction pin protection/
  grant, chưa có shared ACL transaction stamp.
- Server xác minh bytes thực, checksum/type/size và object version. Không attach
  object từ owner/note khác, kể cả cùng bare noteId hoặc biết object key.
- Lost ACK: inspect/retry cùng immutable attempt, trả receipt an toàn sau fresh
  authorization. Không trả private metadata từ receipt cho actor vừa bị revoke.
  Epoch cũ không được tái sử dụng sau re-share/password change.
- Cancel/cleanup quản lý staging object của attempt, không cho client xóa object
  final tùy ý. Chỉ garbage-collect khi server xác nhận không còn reference hoặc
  live attempt; remove association và cleanup không được tạo dangling reference.

Đây là contract M03 cần implement/test; M05 chưa có upload-attempt/object store.

## 7. Tích hợp 02/03/04/05/06 và trách nhiệm

- **Collab M02:** giữ shared atomic local note/outbox writer, autosave concurrency,
  IDs/retries/conflicts; expose safe capabilities/status cho UI. Note hiện
  `NoteRepository.save` commit qua `store.update` và giữ protectionChange khi
  coalescing; shared recipient save vẫn chưa được runtime cho phép.
- **Collab M03:** metadata/object/attempt policy, picker, transport/Range,
  encrypted binary cache/derivatives và integration tests. Nối Application port
  vào M05 guard; UI không lấy raw grant hoặc gọi Infrastructure trực tiếp.
- **Collab M04:** index/search/filter chỉ trên authorized available content;
  locked/revoked title/body/snippets/private filenames không nằm trong search
  results hoặc fallback cache. Pin/labels owner-only theo contract M06; label
  rename/delete không xóa note hay làm mất attachment/protection metadata.
- **Tuấn Kiệt M05/M06:** operation scope/key/session boundary; recipient-aware
  runtime/gateway, real ACL + conditional stamp/feed khi M06 được tiếp tục.
  Thay wire/codec/shared writer cần phối hợp trước để tránh hai đường ghi cùng state.
- Giữ **một** account outbox/cursor coordinator. Không thêm database/cursor song
  song cho shared notes hoặc binaries khiến association không atomic với note.
  M03 có thể có staging/attempt storage qua port nhưng note sync vẫn có một owner.
- Attachment bytes/filename/extracted text không tự thêm vào AI Summary/RAG inputs.
  Existing note-aware consent/revision/grant/stage/cancel lineage phải giữ nguyên.

## 8. Regression phải chạy trước khi nghiệm thu tích hợp

**Tất cả cases dưới đây là gate cần chạy, chưa được nghiệm thu trong batch này.**

| Gate | Cases tối thiểu |
| --- | --- |
| G1 | Chrome + Android image/video/file, seek 206/416/version, CORS; direct bytes/thumbnail/HEAD/Range thiếu JWT/grant, wrong actor/note/op/epoch và expired/revoked đều deny; renewal không mất vị trí |
| G2 | Invalid MIME/extension/size/count; cancel/permission denied; quota full; large-file memory/progress; local save không bị network gate |
| G3 | Legacy note + pending/conflict/ciphertext/cursor survive migration; old client sửa note có attachment; missing vs empty manifest; duplicate replay/lost ACK/fingerprint; atomic rollback/crash |
| G4 | Owner/editor/viewer direct API matrix; cached protected file offline; lock/reload/expiry/logout/account switch; revoke khi đang play/seek/download; clear preview/temp; re-share không hồi sinh draft/attempt cũ |
| G5 | Cross-owner same noteId isolation; upload rồi note deleted/protected/epoch changed; cancel/retry/complete races; wrong checksum/type/size; cleanup vs live reference; stale receipt không leak |
| Cross-module | Autosave + attach/remove + protection rotate không mất metadata; revoked shared note không chặn owned sync; Use local không vượt quyền; M04 search/label/filter không lộ locked data; AI không nhận attachment ngoài contract |

M05/M06.1 tests từng pass được ghi ở PROGRESS.md; chúng không thay thế attachment,
Range, direct storage URL hoặc M02/M03/M04 cross-module regression mới.

## 9. Evidence và giới hạn xác minh

Source links dùng baseline đã đọc để collab có thể đối chiếu sau khi branch đổi:

- [M05 operations/authority](https://github.com/IvanTran0101/note_ai_app/blob/528a7454ffcaab272aaedba65733dedce65639f6/amplify/protection/protection_store.ts#L3), [OwnerNoteAcl baseline](https://github.com/IvanTran0101/note_ai_app/blob/528a7454ffcaab272aaedba65733dedce65639f6/amplify/protection/protection_store.ts#L44), [actor/note/op/epoch/expiry guard](https://github.com/IvanTran0101/note_ai_app/blob/528a7454ffcaab272aaedba65733dedce65639f6/amplify/protection/authorizer.ts#L25).
- [Default unlock scope gap](https://github.com/IvanTran0101/note_ai_app/blob/528a7454ffcaab272aaedba65733dedce65639f6/lib/application/notes/note_security_actions.dart#L23), [local lease after enable](https://github.com/IvanTran0101/note_ai_app/blob/528a7454ffcaab272aaedba65733dedce65639f6/lib/application/notes/note_security_local_actions.dart#L34), [runtime owner gate](https://github.com/IvanTran0101/note_ai_app/blob/528a7454ffcaab272aaedba65733dedce65639f6/lib/infrastructure/security/note_security_runtime.dart#L89).
- [M06 role matrix](https://github.com/IvanTran0101/note_ai_app/blob/528a7454ffcaab272aaedba65733dedce65639f6/lib/domain/notes/note_access_policy.dart#L7), [share revision lifecycle](https://github.com/IvanTran0101/note_ai_app/blob/528a7454ffcaab272aaedba65733dedce65639f6/lib/domain/notes/note_share_grant.dart#L7), [retained encrypted note drafts](https://github.com/IvanTran0101/note_ai_app/blob/528a7454ffcaab272aaedba65733dedce65639f6/lib/infrastructure/security/encrypted_shared_drafts.dart#L4).
- [HTTP encode/decode integration gap](https://github.com/IvanTran0101/note_ai_app/blob/528a7454ffcaab272aaedba65733dedce65639f6/lib/infrastructure/sync/sync_http_mapper.dart#L69), [atomic local save](https://github.com/IvanTran0101/note_ai_app/blob/528a7454ffcaab272aaedba65733dedce65639f6/lib/infrastructure/notes/note_repository.dart#L116), [preserved queued protection intent](https://github.com/IvanTran0101/note_ai_app/blob/528a7454ffcaab272aaedba65733dedce65639f6/lib/infrastructure/notes/note_repository_mutations.dart#L114), [current transaction security conditions](https://github.com/IvanTran0101/note_ai_app/blob/528a7454ffcaab272aaedba65733dedce65639f6/amplify/sync/dynamo_sync_store.ts#L161).
- Local records: [M05 local-first](LOCAL_FIRST_WEB.md), [M06 contract](../m06/CONTRACT.md), [M06 progress](../m06/PROGRESS.md).
- Notion: [M02](https://app.notion.com/p/3e9f9c7a1aa080b08ac0dd9ffa4323d4), [M03](https://app.notion.com/p/3e9f9c7a1aa080ec8394d4390367e266), [M04](https://app.notion.com/p/3e9f9c7a1aa080ed97c5ece6a879d3d3), [planning](https://app.notion.com/p/3e6f9c7a1aa080978256eb9e02768c3a).

Tier2 graph root D:, project `D-kiet-hk7-flutter-midterm-note_ai_app-note-ai-app`,
generation `2026-10-02T10:43:45Z`, exact Git HEAD checked. Coverage checked for
relied source paths; partial library headers and metadata_changed paths were
verified against raw source. Full-text fallback scoped to lib/amplify was used
for attachment/Range absence; no claim about collab code on another branch.
Static source/contract review only: no new runtime tests, backend deploy,
M06 continuation or implementation checkbox acceptance in this batch.

### Closure receipt

| Record | Resolution |
| --- | --- |
| This report | G1–G5, role matrix, integration gaps and regression handoff recorded |
| M05 COLLAB_REVIEW / PROGRESS | Link and scope of this verification batch recorded |
| MUST_REMEMBER / M06 records | Not needed: existing decisions and paused scope unchanged |
| Notion checkboxes | Not needed: no new implementation acceptance |
| _agent_ops | Not available in this checkout; actual docs carry the review record |
