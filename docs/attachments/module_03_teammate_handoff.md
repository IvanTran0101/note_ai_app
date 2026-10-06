# Module 03 — Attachment: review và implementation handoff

Ngày kiểm tra: 2026-10-01. Đây là đề xuất triển khai, chưa phải approval cho dependency, AWS deployment hoặc thay đổi access policy.

Contract repository/access/query chung đã chốt tại [Module 02–03–04](../contracts/modules_02_03_04_contract.md). Dùng nguyên named signature/return type/fence trong file đó; M03 không định nghĩa biến thể updateById hoặc require riêng. Các transport/limits/access-runtime gates còn lại vẫn pending.

Integration update2026-10-02: current reviewed source16ee44b có old atomic API/pin/schema3. Consume PR-C0/common target và [schema4/wire2 specification](../contracts/sync_wire_v2_labels.md); không tạo một schema4 khác cho Attachment. Các nhận xét code6ce2afe bên dưới là historical review, không overriding latest source/prerequisites.

## 1. Kết luận và baseline

- Checkout kiểm tra: `Final-here-do-not-merge-main@6ce2afe`, sạch trước review.
- Baseline trong report e24dd7fc tồn tại nhưng đã cũ. Git diff tới 6ce2afe có 49 files, gồm 47 Dart files liên quan editor/Summary/Application/composition/tests/tool. Nhận định trước “chỉ docs/không có code delta” sai vì session checker không phân loại .dart; đã đính chính. Kiểm tra exact source/HEAD khi teammate bắt đầu.
- Plan phù hợp hướng kiến trúc hiện tại: Note giữ metadata, binary nằm ngoài JSON/DynamoDB note, sử dụng local-first outbox và backend kiểm tra quyền.
- **Chưa sẵn sàng triển khai toàn bộ module.** Có thể bắt đầu A0 để chốt contract và kiểm chứng transport. A1 cần thống nhất atomic mutation seam với người phụ trách Module 02/sync.
- Protected/shared attachments cần contract M05/M06. Hiện các contract này chưa có implementation trong luồng Note đã kiểm tra. Hướng unlock grant đã được thảo luận/chốt không đồng nghĩa code đã tồn tại.

Nguồn requirements đã đọc: [03 — Attachment Management](https://app.notion.com/p/3dc25edc9a2581e2acb9d3530cd317bf?pvs=204) và report người dùng đính kèm. Original DOCX mà report nhắc tới không được đọc độc lập trong review này.

## 2. Những lựa chọn nên giữ

1. `Attachment` là metadata thuộc `Note`; không tạo Domain attachment repository riêng cho metadata đang nằm trong aggregate.
2. Transfer state, picker handles, binary, signed URLs và credentials nằm ngoài Domain Note.
3. Upload được kiểm chứng xong mới queue metadata link; `Ready` chỉ sau server association ACK.
4. Retry dùng attempt identity ổn định; cancellation sau link commit trở thành thao tác remove rõ ràng.
5. Metadata đi qua toàn bộ sync/conflict path; binary không tự đi vào Summary/RAG.

## 3. Năm nhóm cần sửa trong report

### 3.1. Tách upload transport khỏi authenticated read transport

`amplify/sync/http_api.ts` dùng `HttpApi` + `HttpLambdaIntegration`, payload format 2.0. Không mặc định tái sử dụng integration này làm streaming gateway cho video/file lớn.

AWS hiện mô tả API Gateway response streaming cho REST APIs; request streaming không được hỗ trợ. Lambda synchronous buffered request/response có giới hạn 6 MB. Base64 event và envelope còn tạo overhead. Vì vậy một `openRead()` trên client không chứng minh backend nhận request theo stream. [API Gateway](https://docs.aws.amazon.com/apigateway/latest/developerguide/response-transfer-mode.html), [Lambda quotas](https://docs.aws.amazon.com/lambda/latest/dg/gettingstarted-limits.html).

Đề xuất cho upload: authenticated control API tạo attempt, upload trực tiếp vào private S3 staging bằng quyền giới hạn theo attempt, backend kiểm chứng rồi trả verified descriptor. Link vào note vẫn đi qua mutation/association được kiểm tra phía server.

Read cần quyết định riêng:

- Nếu yêu cầu kiểm tra quyền note/unlock ở mỗi request: spike một read gateway thực sự hỗ trợ streaming, Range và nền tảng mục tiêu; đó là phần infrastructure mới cần duyệt.
- Nếu dùng signed GET URL: ghi rõ nó là bearer capability có thời hạn. Việc revoke ACL của note không tự thay đổi URL đã cấp bởi credentials của backend. Không claim revoke tức thời; cần approval cho thời gian phơi lộ tối đa và hành vi download đang chạy.

Signed upload URL có thể được dùng lại và ghi đè object cùng key khi còn hiệu lực. Final descriptor phải trỏ tới immutable final object hoặc pinned object version đã kiểm chứng; không trỏ tới staging key vẫn có thể ghi. [S3 presigned URLs](https://docs.aws.amazon.com/AmazonS3/latest/userguide/using-presigned-url.html).

Nếu copy staging sang final, validate và copy cùng source version hoặc dùng điều kiện tương ứng rồi kiểm chứng final version/checksum. Không để overwrite giữa validation và copy thay thế bytes đã được duyệt. Test race này tách khỏi test upload URL hết hạn.

Trên Web, package `http` 1.6.0 đang resolve có `BrowserClient.send()` gọi `await request.finalize().toBytes()` trước fetch. Do đó native streaming upload và Web binary upload cần adapter có bằng chứng phù hợp; không dùng `StreamedRequest` rồi claim Web không buffer cả file. Spike lựa chọn browser File/Blob/chunk transport cùng progress/cancel. Resolve source dependency qua `.dart_tool/package_config.json`, không hard-code pub-cache path của máy tác giả.

Spike read/open phải kiểm tra image preview, video seek/Range, file download và cách truyền auth của browser/player; không mặc định mọi player có thể thêm bearer header. Ghi CORS cần cho từng data path, không chỉ CORS của JSON sync API.

### 3.2. Atomic mutation là prerequisite thật, áp dụng cho tất cả writer

Ở baseline6ce2afe chưa có atomic method. Source16ee44b đã có old-signature updateById và atomic text path, nhưng cần PR-C0 migrate named owner/actor/fence/fresh-Note contract. Không implement binary metadata integration dựa trên overload khác common target.

Target updateById trả Future<Note>; change synchronous trả chính fresh Note; canCommit là synchronous boolean fence. Dùng đủ noteId/ownerId/expectedAccountUserId cùng tên/kiểu như common contract. Không dùng actor làm canonical owner hoặc hứa rollback commit đã thành công nếu session đổi trong durable write.

Thêm atomic attachment link trong khi giữ text save theo stale aggregate có thể làm mất collection mới. M02/sync và M03 cần chốt một mutation seam để các thay đổi text/link/remove đều đọc fresh aggregate và commit note + outbox trong `ILocalSyncStore.update`.

Callback của `ILocalSyncStore.update` hiện là synchronous và cấm I/O. Thực hiện async access/session checks trước transaction; kiểm tra captured account/session và cached authorization facts phù hợp tại local commit; backend kiểm tra current ACL/unlock tại server commit. Không gọi HTTP/picker/upload trong IndexedDB transaction.

Một Note vừa tạo local có `serverRevision == 0`. Đề xuất đơn giản: cho phép staging offline nhưng giữ attempt ở Queued cho tới khi remote create được ACK; sau đó mới khởi tạo note-bound remote upload. Nếu chọn provisional upload trước create, phải định nghĩa association/cleanup contract riêng và test note-create failure.

### 3.3. Version metadata và giữ idempotency khi nâng cấp

Local schema hiện là v2 strict. `SyncNotePayload`, remote snapshots và backend response hiện không có attachments. `parseMutationBody` hiện chỉ copy `title/content`; client gửi thêm attachments tới backend cũ có thể bị bỏ qua mà mutation vẫn trả applied.

Migrate legacy records sang `attachments: []` chỉ áp dụng khi phiên bản legacy thực sự không có field. Không biến malformed attachment metadata thành collection rỗng. Migration phải giữ account, cursor, tombstones, outbox và conflict snapshots; không clear/reset dữ liệu.

Backend fingerprint hiện chỉ hash operation, noteId, baseRevision, title và content. Giữ nguyên `mutationId` nhưng đổi normalization/fingerprint sau rollout vẫn có thể làm replay cũ thất bại. Contract cần phân biệt legacy/vNext mutation và giữ legacy replay semantics; không tự thêm field vào attempted payload rồi gửi lại cùng ID. Khi vNext hoạt động, mọi field attachment có ý nghĩa và thứ tự collection đã chốt phải tham gia canonical fingerprint.

Triển khai backend nhận/validate/trả metadata trước khi enable client emission. Client cũ không được phép replace note có attachment bằng payload legacy làm mất collection. Chốt server-side preserve/reject/upgrade policy và test mixed versions; “backend trước client” một mình chưa đủ.

Kiểm tra tất cả constructor/copy paths: Note → NoteDto → LocalNoteState → outbox → mapper → parser → Dynamo snapshot/replay → response → ACK/pull/conflict. Đặc biệt `acknowledge` giữ later pending edits và `SyncConflictResolver` tạo note ID mới.

Save-as-new không được copy `storageObjectId` đang bind note cũ sang note mới. Chọn explicit rebind/copy được server authorize, hoặc giữ pending copy và thông báo rõ. Không tự bỏ attachments.

### 3.4. Chỉ rõ persistence owner của upload attempts và cleanup

Report nói durable attempt nhưng picker/gateway/cache ports chưa chỉ rõ nơi lưu record. Chốt một owner lưu attempt manifest và binary reference: native private manifest/files; Web account-namespaced IndexedDB binary/manifest storage. Reuse account namespace; không encode binary/base64 vào sync JSON. Có thể để cache boundary sở hữu manifest, không cần thêm một Domain repository.

Web store hiện chỉ có một JSON envelope object store, database version 1. Nếu bổ sung binary store, chọn database riêng theo cùng namespace hoặc thiết kế upgrade/versionchange/multi-tab lifecycle rõ; không đặt Blob vào codec JSON hiện tại rồi coi là tương thích.

Persist accountUserId, canonical note identity, attemptId, attachmentId dự kiến, cacheRef, phase/resumePhase, server attempt identity và verified descriptor cần phục hồi. Không persist JWT, unlock grant, signed URL hay function/file handle.

`sessionGeneration` là fence của một lần chạy trong process, không phải authorization bền vững. Khi restart hoặc user đăng nhập lại, attempt còn tồn tại chỉ được resume sau khi capture session mới và revalidate quyền. Late callback của session cũ không được link hoặc mở preview vào phiên mới.

Lost ACK phải được xử lý bằng lookup attempt/current note association; không upload lại mù quáng. Cancel đang race với link phải hỏi kết quả authoritative, không xóa object đã link. Retry remove tiếp tục remove. Link conflict không tự biến thành retry upload.

Binary cache và note/outbox ở hai tài nguyên khác nhau: không claim cross-store atomicity. Dùng stable IDs + recovery scan/reconciliation để xử lý crash giữa các bước. Cleaner phải phân biệt lease của queued attempt, referenced object và unreferenced staging; TTL là thời hạn eligibility cleanup, không phải bảo đảm xóa đúng tức thời.

### 3.5. Khóa object binding, access dependencies và khả năng platform

M05/M06 phân biệt actor hiện tại với canonical owner. Các boundary dùng resource identity `(canonicalOwnerId, noteId)` khi shared-note contract được chốt, không lấy account cache namespace làm owner. Server phải kiểm tra object thuộc đúng note/attempt/actor và lấy verified size/type/object descriptor từ record phía server, không tin metadata client.

Read requires live note/object association + quyền read; upload/link/remove requires quyền edit tương ứng. Protected content cần unlock grant gắn đúng actor, note và protection revision. Grant của owner không chuyển cho recipient. Current Note read/write vẫn owner-only; không invent production allow-all `INoteAccessGuard` để vượt dependency.

`HEAD Content-Type` hoặc extension không phải xác minh actual type. Phải kiểm tra actual size/checksum và bytes phù hợp policy trước link; active HTML/SVG không được render cùng origin với app. Quarantine/final object lifecycle không đồng nghĩa đã có malware scanner; chỉ claim đúng kiểm tra đã implement.

Chốt giới hạn cả binary lẫn metadata: bytes/file, số attachments/note, filename length, MIME/extensions, tổng encoded note size, staged bytes/account, attempt timeout và cache quota. Backend hiện giới hạn text payload 300,000 bytes để nằm dưới DynamoDB item limit; thêm metadata phải tính cả note snapshot và replay record.

Pubspec hiện chưa có picker/camera/opening plugin. Candidate để spike: [file_selector](https://pub.dev/packages/file_selector) cho file picker, [image_picker](https://pub.dev/packages/image_picker) cho gallery/camera nơi hỗ trợ. Đây chưa phải dependency approval. macOS cần user-selected-file entitlement; desktop camera có fallback vì image_picker không cung cấp camera mặc định. Matrix tối thiểu phải có Web, iOS và macOS đang được sử dụng; Android theo target của project. Đặt picker permission declarations trong platform adapters/manifests theo nhu cầu thực, không yêu cầu quyền storage rộng mặc định.

## 4. Contract cần chốt trước full implementation

| Gate | Kết quả cần có | Không được tự giả định |
| --- | --- | --- |
| G1 Transport | Separate upload/read design; Web + Native proof; Range/auth/CORS | Current HTTP API stream được binary lớn |
| G2 Policy | Approved limits, type rules, cache quota và nền tảng | Limit hoặc plugin đã được duyệt |
| G3 Mutation/schema | Atomic Note writer + legacy/vNext migration/idempotency | `updateById` đã tồn tại hoặc v2 cho phép thêm field |
| G4 Access | M05/M06 action, NoteKey, grants, revoke, cache policy | Owner-only là đầy đủ ATT-FR-06; namespace là owner |
| G5 Attempts/binding | Durable attempt owner, immutable final object, cancel/cleanup semantics | Upload thành công nghĩa attachment Ready |

Owned/unprotected foundation có thể được nghiệm thu như một slice giới hạn. Shared/protected controls phải fail closed khi contract/runtime chưa sẵn sàng; không đánh dấu toàn bộ ATT-FR-06/NFR-01 đã hoàn thành.

## 5. Lifecycle đề xuất để teammate implement

```text
select + validate
  → durable private staging / Queued
  → wait for saved remote Note + current edit access
  → upload staging object
  → server byte verification + immutable final descriptor
  → fresh local Note mutation + metadata outbox / AwaitingLink
  → server ACL + unlock + revision + object-binding commit
  → association ACK / Ready
```

UI có thể cho mở bản local pending theo cache policy, nhưng phải hiện Pending và không gọi nó là server Ready. Unlink/remove chỉ cleanup final binary sau server ACK và reference check. Note deletion/tombstone phải vô hiệu hóa read association, xử lý mọi linked attachment và staging lease liên quan; không giao nhiệm vụ này cho widget dispose.

## 6. Chia implementation thành năm slice

| Slice | Phạm vi | Exit gate |
| --- | --- | --- |
| A0 — Contract + feasibility | G1–G5; payload examples; platform matrix; upload/read spike; file ownership với teammates 02/05/06/11 | Reviewable contract; unresolved choices được ghi rõ. Không deploy/cloud write chưa được phép |
| A1 — Aggregate + atomic metadata path | Attachment invariants; fresh Note mutation; DTO/local models/codecs/outbox/ACK/conflicts; legacy replay tests; backend metadata contract với fake object verifier | Concurrent text/link/remove không mất dữ liệu; old outbox/cursor giữ nguyên; production flag chưa gửi unsupported payload |
| A2 — Staging + attempts + platform IO | Private durable binary/manifest adapters; picker cancel/denied/fallback; session fences; retry/cancel/restart | Web + Native staged file survives reopen; late session results ignored; không full-file buffer trong đường đã claim bounded memory |
| A3 — Private backend + verified association | Storage/resources/IAM; attempt/control API; actual-byte validation; immutable binding; approved read transport; cleanup | Direct-access negative tests, duplicate/lost ACK/cancel races pass; deploy/live evidence riêng sau approval |
| A4 — UI + release integration | Attachment panel; open/preview/download; confirmation/progress; access state; full sync integration và real platform smoke | Image/video/general file + multiple files + offline/retry/remove verified; all mandatory requirements supported hoặc explicit pending |

Implementation có thể làm bằng fake boundaries trước deploy. Production rollout vẫn backend-compatible trước client feature enable. Không chạy A1/A3 song song với writer khác trên cùng sync files khi chưa có ownership contract.

## 7. Cấu trúc file và trách nhiệm

Giữ nhóm existing files trong report, bổ sung ownership dưới đây. Tạo file theo responsibility khi slice dùng tới; không scaffold hết từ A0.

| Owner | Files/boundary | Quy tắc |
| --- | --- | --- |
| Domain | `lib/domain/notes/attachment.dart`, `note.dart`, agreed `note_repository.dart` change | Metadata/invariants; readonly collection; không Stream/S3/Flutter/token. Policy object không được import từ Application vào Domain |
| Application | `lib/application/attachments/attachment_application_service.dart`, transfer coordinator/record, policy/failure; riêng `attachment_picker.dart`, `attachment_gateway.dart`, `attachment_cache.dart` khi dùng | Service gọi use cases; coordinator sở hữu attempt transitions. Không gom mọi port/model trong `attachment_ports.dart`; không generic task/event framework |
| Infrastructure | Separate picker/cache/binary-upload adapters for IO/Web; metadata gateway; sync codecs/mapper/repository | Tái sử dụng path_provider/account namespace/installed IO helpers; kiểm chứng browser transport; SDK không đi lên Application |
| Backend | Attachment routes/parser/use cases, attempt storage, object validation/binding, S3 adapter, cleanup và resource wiring | One owner cho final association transaction; không nhét upload/read/cleanup vào `DynamoSyncStore` hoặc tạo Note CRUD path thứ hai |
| Presentation/tests | Attachment controller/panel + editor integration, scoped tests and platform smoke | Widget chỉ render/call Application; tests source có fake access denied/expired và server-binding outcomes |

Report phải bổ sung `SummaryRunGuard` vào impact list: nó dựng lại `NoteDto` từ local state để so snapshot. Khi thêm metadata vào DTO/equality, guard phải map cùng shape. Mặc định giữ conservative snapshot invalidation khi Note thay đổi; không chuyển sang chỉ so text bằng cách bỏ các guard hiện có. Binary/filenames không tự trở thành AI inputs.

Architecture Gate “limited to assigned module” cần ghi **cross-module contract approved/pending** vì atomic mutation, sync protocol, Summary projection và M05/M06 access cùng bị tác động. Dependency arrows PASS chỉ là thiết kế, chưa phải runtime evidence.

## 8. Verification cần bàn giao cùng PR

| Nhóm | Những case bắt buộc |
| --- | --- |
| Aggregate/atomic | Add/remove giữ text; text save giữ attachment; concurrent link/text/remove; duplicate descriptor; note deletion giữa upload/link |
| Protocol/migration | v2 legacy notes/outbox/conflicts/cursor; attempted v1 replay; vNext fingerprint includes metadata; old client save does not drop attachments; ACK with later pending edit; save-as-new association |
| Transfer/crash | Queued note serverRevision 0; offline/reopen; lost verify/link ACK; duplicate retry; cancel race with link; restart with new generation; storage quota/full failure; remove retry resumes remove |
| Security/storage | Foreign note/object descriptor; viewer edit; recipient/protected grant; revoke before link/read; expired/reusable upload URL; overwrite after verification; stale association; active-file preview; cleanup never deletes referenced object |
| Runtime/UI | Multiple image/video/file; picker cancel/denied; actual Web upload memory path; native transfer; video seek; download progress/failure; logout clears preview; Web plus iOS/macOS smoke, Android per target |

Commands khi có source implementation: run format cho file đã sửa; `flutter analyze`; focused Flutter tests trước `flutter test` theo AGENTS; Chrome tests cho các adapters/flows Web; backend checks theo scripts trong `package.json`; `git diff --check`. Build/runtime và deployed AWS evidence phải ghi riêng. Không đánh dấu live checks pass từ mocks.

## 9. Prompt khởi động cho Codex của teammate

```text
Read AGENTS.md, docs/contracts/modules_02_03_04_contract.md and
docs/attachments/module_03_teammate_handoff.md completely.
We are implementing Module 03 incrementally, preserving the existing local-first
Note/outbox/cursor/conflict engine and DDD dependency direction.

First verify the current branch/HEAD, dirty worktree, dependencies and relevant
source. The reviewed source baseline is Final-here-do-not-merge-main@6ce2afe;
do not assume your checkout matches it. Use graph tools when available, disclose
Dart/coverage limitations, and verify material behavior in exact source.

Start with A0: produce concrete upload/read contracts, platform/limit choices,
atomic-mutation ownership, schema/idempotency rollout and access dependency gates.
Confirm which implementation slice the human approved before moving into source
changes. Do not assume updateById, shared access, note unlock, encryption or a
streaming HTTP gateway already exists.

Use focused files and one writer for shared sync code. Preserve attempted request
identities, legacy data, note content, account isolation and explicit conflicts.
Do not use an allow-all production access guard, public storage, durable signed
URLs, whole-file Web buffering while claiming streaming, or a second Note CRUD
backend. Keep bytes outside Note/JSON outbox and require authoritative association
ACK before Ready.

Add dependencies or platform capability changes only after their choices are
approved. Do not change signing identities/credentials/secrets, deploy AWS, merge,
commit or push without the corresponding authorization. Run the required source
checks and record mock, platform and live evidence separately.
```

## 10. Evidence và giới hạn review

Exact source được kiểm tra: `lib/domain/notes/{note,note_repository}.dart`, `lib/application/notes/note_application.dart`, `lib/application/auth/current_user_session.dart`, sync models/ports/coordinator/reconciliation/conflict resolver, `lib/infrastructure/notes/note_repository.dart`, local store IO/Web/schema/codecs/mapper, `lib/presentation/notes/note_detail_page.dart`, SummaryRunGuard, `amplify/backend.ts`, sync HTTP API/parser/store/response và `pubspec.yaml`.

Graph MCP/coverage tools không có trong phiên. Local graph tại `e24dd7f` giúp tìm backend TS nhưng không phủ Dart; Attachment hits từ vendored llama.cpp UI không được tính là feature evidence. Review sử dụng exact source và bounded search trong first-party paths. Không chạy Flutter/backend tests hoặc deployment trong planning review này.
