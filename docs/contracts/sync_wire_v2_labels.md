# Sync wire v2 và local schema 4 — Module 04

Chốt 2026-10-02 theo yêu cầu hoàn thiện plan để implement. Authority cho versioning/bootstrap/metadata-preservation của M04; source baseline được review là [16ee44b](https://github.com/IvanTran0101/note_ai_app/commit/16ee44b247d42119b4912ff38cf3f551fa0a8434). Đây là target, không phải endpoint đã deploy.

## 1. Scope và identity

Một account local store, một outbox/cursor engine và một account sequence; hai entity types đóng là note/label. Resource key là (entityType, ownerId, entityId), mutationId unique trong actor/account journal. Owner/identity server luôn được kiểm tra từ verified JWT sub; body ownerId chỉ là resource locator.

M04 rollout owned/unprotected: ownerId phải bằng authenticated sub. Shared/protected organization fail closed cho tới integration M05/M06. Không Label engine/database thứ hai, không NameClaim vì duplicate names được phép.

## 2. Routes và version negotiation

Giữ POST /sync/mutations, GET /sync/changes, existing health route.

- POST wireVersion absent/1: legacy Note request/encoder/fingerprint/response.
- POST wireVersion=2: typed Note/Label request; fields không thuộc schema bị từ chối.
- GET wireVersion absent/1: legacy Note-only projection.
- GET wireVersion=2: typed Note/Label feed, response phải có wireVersion=2.
- V2 runtime kiểm chứng GET v2 trước khi dispatch v2 writes. Unsupported/malformed version response không được coi là business rejection và không làm blocked/fresh-ID repair pending entries.
- 401 vẫn refresh token tối đa một lần trong deadline; account/session/auth failure dừng run. Typed resource rejection chỉ block đúng resource/dependent writes.

Không fallback Label sang noteId giả hoặc đổi wire của attempted request. Server v2 support phải deploy/verify trước production client enable. V1 vẫn được hỗ trợ trong rollout này.

## 3. Request và response shapes

Label create:

```json
{
  "wireVersion": 2,
  "entityType": "label",
  "entityId": "label-1",
  "ownerId": "current-sub",
  "mutationId": "label-create-1",
  "operation": "create",
  "baseRevision": 0,
  "payload": { "name": "Công việc" }
}
```

Note update giữ required title/content; metadata fields là presence-aware, không default unknown thành clear:

```json
{
  "wireVersion": 2,
  "entityType": "note",
  "entityId": "note-1",
  "ownerId": "current-sub",
  "mutationId": "note-label-1",
  "operation": "update",
  "baseRevision": 3,
  "payload": {
    "title": "Kế hoạch",
    "content": "Nội dung",
    "labelIds": ["label-1"]
  }
}
```

Omitted pinnedAt/labelIds/attachments nghĩa giữ server value. Explicit null pinnedAt là unpin; explicit [] labelIds/attachments là clear theo action/association policy. M04 không phát new attachment references; backend chặn added attachment references khi M03 binding verifier chưa sẵn sàng. Label payload chỉ name; delete không cần payload.

Label applied:

```json
{
  "wireVersion": 2,
  "status": "applied",
  "mutationId": "label-create-1",
  "entityType": "label",
  "snapshot": {
    "id": "label-1",
    "ownerId": "current-sub",
    "name": "Công việc",
    "revision": 1,
    "createdAt": "2026-10-02T00:00:00.000Z",
    "serverUpdatedAt": "2026-10-02T00:00:00.000Z",
    "deletedAt": null
  }
}
```

409 revision conflict:

```json
{
  "wireVersion": 2,
  "status": "conflict",
  "mutationId": "label-rename-1",
  "entityType": "label",
  "remoteSnapshot": null
}
```

remoteSnapshot nếu có phải đúng requested type/owner/id. Never interpret Label as Note conflict. Successful Note snapshot v2 luôn có ownerId, pinnedAt, labelIds, attachments và existing identity/text/revision/time/tombstone fields. Label snapshot không giả title/content. Server giữ name cuối trong Label tombstone.

Typed application failure:

```json
{
  "wireVersion": 2,
  "code": "INVALID_ASSOCIATION",
  "entityType": "note",
  "entityId": "note-1",
  "retryable": false
}
```

Codes cần implement: INVALID_MUTATION, INVALID_ASSOCIATION, INVALID_LABEL, PAYLOAD_TOO_LARGE, INVALID_CURSOR, NOT_FOUND, FORBIDDEN, UNAUTHORIZED, UNSUPPORTED_WIRE_VERSION, BOOTSTRAP_UNAVAILABLE, SERVER_UNAVAILABLE. Không LABEL_NAME_CONFLICT/name claim trong scope duplicate-name.

HTTP mapping: 200 success; 400 malformed request/invalid cursor; 401 unauthorized; typed403 resource forbidden (block resource), untyped authorizer403 account/auth failure (stop run); 404 not found; 409 typed revision conflict; 422 validation/association/payload rejection; 426 unsupported wire; 503 storage/service failure hoặc known bootstrap unavailable. retryable=false cho validation/unsupported/known history-unavailable; true cho transient service failure. Response thiếu expected wire2 ở application-level rejection là protocol mismatch, không blanket-map422 thành invalidAssociation hoặc sửa mutation ID.

## 4. Legacy preservation và fingerprints

Legacy requests đã attempted dùng nguyên mutationId/version/payload semantics/metadata presence và encoder cũ. V1 fingerprint giữ exact existing shape, gồm pinnedAt chỉ khi field có mặt. Journal replay không áp dụng mutation lần hai.

V1 update missing labelIds/attachments giữ server arrays. V1 response không làm client v2 hiểu thiếu metadata là []; legacy ACK/conflict hydration phải preserve local metadata và later user intent, không giảm known server revision.

V2 fingerprint gồm wireVersion, entityType, resource owner/id, operation, baseRevision, normalized payload và metadata-presence markers. Note text formatting giữ nguyên; Label name trim theo policy. labelIds encode sorted unique bằng ordinal/code-unit order (Dart compareTo/JS default sort), không localeCompare; duplicate IDs trên wire bị reject. Attachments giữ agreed list order. Reusing mutationId cho request khác trả INVALID_MUTATION. Definitive rejected request chỉ được sửa thành successor mới khi user Retry/edit; lost ACK retry nguyên request.

Note snapshot v2: id, ownerId, title, content, createdAt, serverUpdatedAt, revision, pinnedAt(nullable UTC), deletedAt(nullable UTC), labelIds và attachments. Label snapshot có shape của applied example. Attachment metadata consume đúng seven fields từ M03: id/noteId/fileName/mimeType/sizeBytes/storageObjectId/addedAt; parent Note cung cấp canonical owner. Không binary/URL/token hoặc silently change this descriptor shape trong schema4.

Mọi hydration/ACK/pull có pending writes phải preserve text/pin/label/attachment intent theo từng field. Omitted metadata không là clear; attempted request/baseRevision không bị rewrite để hydrate metadata. Missing/unknown không là tombstone.

## 5. Feed, byte budget và cursor

GET v2 page example:

```json
{
  "wireVersion": 2,
  "items": [
    {
      "entityType": "label",
      "snapshot": {
        "id": "label-1",
        "ownerId": "current-sub",
        "name": "Công việc",
        "revision": 1,
        "createdAt": "2026-10-02T00:00:00.000Z",
        "serverUpdatedAt": "2026-10-02T00:00:00.000Z",
        "deletedAt": null
      }
    }
  ],
  "nextCursor": "<opaque-v2>",
  "hasMore": false,
  "caughtUp": true
}
```

- limit defaults50, max100, tính trên raw contiguous change rows đã inspect/consume, không chỉ filtered returned items.
- Request/response body encoded UTF-8 tối đa2,500,000bytes, để Lambda proxy double-encoding envelope còn headroom dưới buffered limit và một legacy text snapshot nhiều escaped control characters vẫn fit. Stop trước row làm vượt response cap; không advance qua row chưa consume.
- Note payload cost = raw UTF-8 title+content + encoded metadata-fields JSON, max300,000bytes; composed snapshot cost = raw UTF-8 title+content + encoded remaining snapshot fields/overhead, max350,000bytes dưới Dynamo item budget. Không đo legacy text bằng JSON-escaped length rồi reject/drop valid old text. Label payload dùng normalized fields cùng bounds. V1 update check composed snapshot cũng không drop preserved metadata để fit.
- Cursor opaque, bound account+wire protocol. V1 cursor không được dùng cho GET v2; server trả INVALID_CURSOR, không silently accept hoặc skip data.
- V2 pass capture high-water H từ strongly-consistent account metadata; H nằm trong opaque pagination cursor tới khi pass kết thúc. Chỉ consume sequences <=H, giữ contiguous-prefix GSI rule.
- caughtUp=true chỉ khi consumed sequence đạt H. Không suy từ hasMore=false.
- Paging phải honor Dynamo Query LastEvaluatedKey/byte truncation, không chỉ Items.length>limit. Contiguous prefix còn H rows hoặc unconsumed returned row/LastEvaluatedKey thì hasMore=true; không coi SDK byte truncation là end-of-feed.
- GSI gap hoặc tail chưa visible: trả prefix đã thấy, hasMore=false/caughtUp=false; giữ checkpoint và catalog chưa complete. Coordinator làm tối đa một delayed foreground retry sau1giây; còn gap thì giữ pending/waiting status, chờ resume/manual/local-mutation trigger; không busy-loop.
- Khi caughtUp=true, nextCursor là normal delta checkpoint; pass sau capture H mới.
- V1 filter Label rows SAU contiguous scan, advance cursor qua raw rows thật đã consume. Có thể items=[] nhưng cursor tiến/hasMore=true. Không tạo gap giả do lọc type.

## 6. Upgrade bootstrap chốt: typed replay từ đầu

Reuse retained change feed, không thêm snapshot endpoint trong slice này. Source16 notes table không có feed GC/TTL; yêu cầu deployment giữ toàn bộ change history cho bootstrap này. Nếu history thực tế đã bị cleanup hoặc có permanent gap, dừng với safe bootstrap-unavailable state; không false Ready. Snapshot bootstrap/retention là upgrade riêng sau khi nhu cầu được chứng minh.

1. Migrate state4, giữ notes/preferences/outbox/conflicts. Nếu cursorWireVersion=1 hoặc catalog chưa từng bootstrap, atomic transition cursor=null, cursorWireVersion=2, labelCatalogPhase=replaying. Đây là cursor bootstrap có chủ đích, không reset database.
2. GET v2 từ sequence0, capture H và paginate. Page + entity applications + cursor commit cùng một store.update. Preserve local pending Label/Note intent.
3. Resume từ persisted v2 bootstrap cursor nếu app dừng. Không bắt đầu lại từ0 ở mỗi launch.
4. Chỉ response caughtUp=true hợp lệ mới chuyển labelCatalogPhase=ready. New events sau H được normal delta sync xử lý.
5. Snapshot revision <= known revision không overwrite; old replay không giảm revisions hoặc clear metadata. Stale Label IDs/tombstones không hồi sinh.

Async pages yield bình thường và cancellation/session guards vẫn có hiệu lực. ponytail: replay full retained history là ceiling của bản đầu; thêm snapshot bootstrap khi lịch sử lớn gây chi phí/thời gian đo được, không xóa feed trước khi có replacement contract.

## 7. Local schema4 duy nhất

JSON envelope4 giữ existing fields và thêm:
- labels, labelConflicts, cursorWireVersion (1|2), labelCatalogPhase (needsBootstrap|replaying|ready).
- LocalNoteState/NoteDto labelIds, attachments và labelIdsKnown/attachmentsKnown facts; domain collections immutable. Flags thuộc cache/projection, không security credential.
- Typed outbox lưu original wire version/entity identity/payload presence. Existing Note conflicts vẫn có branch riêng với Label conflicts.
- userPreferences/pinnedAt/cursor không bị mất khi writer chỉ đổi catalog hoặc notes.

Migrate2→4 hoặc3→4 trong một coordinated writer; v2/v3 records thiếu metadata mới => collections[], known=false cho remote-existing Notes. New local Note có metadata empty known=true. V2 authoritative snapshots set known=true. Legacy empty defaults không chứng minh remote associations rỗng.

Một copyWith/preservation helper cho LocalSyncState; omitted field giữ existing value, explicit cursor=null phải clear được. Mọi repository/reconciliation/conflict/preferences writer dùng helper và giữ fields khác. Không constructor-based copy thiếu labels/preferences. IndexedDB database version hiện1 giữ nguyên vì catalog vẫn trong JSON envelope; binary cache M03 là boundary riêng.

Unknown metadata không được emit explicit[] chỉ vì migration default[]. V2 producer omit unknown metadata và metadata không thuộc intended mutation. Before organize on remote-existing Note, require labelIdsKnown; typing/autosave vẫn hoạt động theo presence-aware protocol. Hydrate authoritative metadata khi không có pending intent cho field, giữ pending text và frozen requests.

## 8. Dependency và conflict rules

Label create ACK trước dependent Note có reference chưa được server acknowledge. Scheduler defer Note, push eligible Label prerequisite; unrelated entries tiếp tục. Never-sent coalescing không đổi queue position thì dependency scheduler vẫn phải xử lý correctly.

Verified tombstoned IDs có thể được compact trong một genuine association edit hoặc never-sent payload; never infer tombstone từ missing catalog. Không rewrite attempted payload. Label create chưa từng attempted bị delete có thể bỏ create khỏi queue nhưng giữ local tombstone; attempted create phải settle trước successor delete.

Revision conflict giữ local/remote/later theo đúng entity. Remote Label deleted không hồi sinh cùng ID; save-as-new cần user action, new ID, không tự remap Note associations. Definitive invalid association block resource; pull/catalog recovery vẫn chạy; explicit Retry creates valid fresh successor. Không auto overwrite hoặc auto merge label IDs.

## 9. Acceptance fixtures cần có trước production enable

V1 attempted pin replay; absent-versus-empty metadata; v2 Note/Label same id; duplicate names distinct IDs; ACK/later intent; first upgrade legacy cursor đã skip Labels; multi-page bootstrap/high-water race; transient/permanent GSI gap; interrupted bootstrap; Query LastEvaluatedKey và escaped-text page byte cap/Lambda envelope headroom; preference/text/conflict writer preservation; unknown metadata autosave; explicit clear; prerequisite ordering; stale Label tombstone; foreign owner; replay revision monotonicity.

Mọi request/response/cursor fixtures được version-pinned trong repo. Mocks/source checks không phải deployed evidence. No dependencies, source hoặc deployment đã được thực hiện qua document này.
