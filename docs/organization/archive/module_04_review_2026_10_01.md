# Historical review — superseded 2026-10-02

This file is history, not current implementation instructions. Read [the current M04 plan](../module_04_teammate_handoff.md).

# Module 04 — Search, Labels & Organization: review và teammate handoff

Ngày review: 2026-10-01. Common mutation/access contract, ALL label filter và pinned ordering đã chốt tại [Module 02–03–04](../../contracts/modules_02_03_04_contract.md). Name uniqueness, shared runtime và wire migration details vẫn cần gates riêng; contract này chưa được implement.

## 1. Kết luận và baseline

- Source được kiểm tra ở Final-here-do-not-merge-main@6ce2afe. Report baseline e24dd7fc tồn tại nhưng Git diff tới HEAD có 49 files, gồm 47 Dart files. Session checker thiếu .dart trong CODE_SUFFIXES; nhận định trước “không có code delta” đã đính chính. Evidence phải đọc source tại current HEAD.
- Có sẵn live keyword search theo title/content. Trong first-party Note/sync paths đã kiểm tra chưa có Label aggregate, labelIds, label catalog hay typed Label feed.
- Plan phù hợp hướng DDD/local-first: ID-stable Label riêng, Note giữ ID set, pure local query, reuse outbox/cursor/revision engine.
- **NOT READY cho full implementation** tới khi typed push/pull, atomic association, dependency/conflict behavior và shared-access scope được chốt. Có thể bắt đầu O0 để tạo contract reviewable; O1 query/domain groundwork dùng fakes sau khi phạm vi được duyệt.
- Tài liệu Attachment handoff từ review trước đang có ở local và cần được phối hợp; không overwrite tài liệu hoặc thay đổi đang có của teammate khác.

Requirements đã đọc: [04 — Search, Labels & Organization](https://app.notion.com/p/3dc25edc9a258179b008d1376f160471?pvs=204) và report người dùng đính kèm. Original DOCX mà report viện dẫn không được đọc độc lập ở phiên này.

## 2. Những lựa chọn nên giữ

1. Keyword search vẫn là substring title OR content, cập nhật khi gõ, không request mạng mỗi keystroke. Semantic/RAG không thay thế requirement này.
2. Note lưu immutable label ID set; tên chỉ nằm trong Label catalog. Rename giữ ID; delete không delete Note.
3. Reuse một account-scoped local store/outbox/cursor engine. Label có revision/tombstone/conflict riêng; không giả label thành noteId.
4. Filter/sort là pure Presentation functions trên Application projections; không cần search framework, index server hay state-management package mới.
5. Catalog chưa đầy đủ không chứng minh label đã xóa; missing/unknown và tombstoned cần khác nhau.

## 3. Năm nhóm cần nâng cấp

### 3.1. Giữ đúng search và sort hiện tại

`DashboardContent.visibleNotes` trim/lowercase query, match title OR content, rồi sort theo `DashboardSort.updated` hoặc created time với ID tie-break. Report mô tả “newest sort” còn thiếu việc giữ cả hai sort modes. Comparator/query từ Module02 hiện là dependency proposal; đừng giả `note_query.dart` đã tồn tại.

Target đã chốt: lọc keyword + ALL labels trước; trong results, pinned trước unpinned, pinnedAt descending; unpinned dùng selected created/updated descending; tie-break ownerId rồi noteId. List/grid/search/filter dùng cùng comparator. Pinned không vượt filter để hiện note không match.

`DashboardPage._loadInternal` lấy `_notes` từ `notesController.listNotes()` riêng với overview. Search hiện không bị giới hạn bởi recent-note limit của Dashboard overview. Giữ full loaded note list; không chuyển search sang `overview.recentNotes` trong refactor.

Khi thêm Label, extract một helper pure và dùng cùng semantics cho các surfaces đang có search/filter. Không nhân đôi helper trong Dashboard và Notes. Debounce là lựa chọn sau profiling, không tự thêm delay/network call. Không thêm accent-insensitive/fuzzy matching vào requirement hiện tại.

ALL selected labels AND keyword đã chốt theo common contract; UI nói rõ phải có đủ labels đã chọn. Empty selection, deleted selection, unknown catalog, zero results và clear filters tuân theo common contract. Unicode/case behavior cần fixtures tiếng Việt; trim/lowercase không tự có accent folding hoặc Unicode normalization.

### 3.2. Association cần fresh Note và fresh Label trong cùng transaction

`INoteRepository.updateById` chưa tồn tại. Text use cases vẫn read → mutate → save; serialize từng repository call không biến chuỗi này thành atomic aggregate mutation. Label attach/detach, text edits và Attachment link/remove cần cùng mutation seam đọc fresh state để không ghi đè metadata của nhau.

Signature/return/fence dùng nguyên common contract. ILabelRepository.updateById giữ cùng named-parameter/fence pattern, đổi noteId/Note sang labelId/Label; callback synchronous trả chính fresh Label. M04 không tự thêm owner/canCommit overload khác M02/M03.

Chỉ read Label trong Application rồi gọi Note.update chưa đủ: delete Label có thể commit giữa lookup và attach. Atomic association phải kiểm tra fresh Note, fresh active Label, ownership và local outbox trong cùng `ILocalSyncStore.update`. Callback hiện synchronous, không I/O; network/access lookup nằm ngoài transaction và server kiểm tra quyền cuối tại commit.

Inject LabelRepository, NoteRepository và coordinator cùng cached account store instance từ `main.dart::_localSyncStoreForAccount`. Không tạo các native store instance/queues độc lập cùng ghi một file. Local uniqueness check cũng nằm trong transaction catalog + label outbox.

Module03 và Module04 đang cùng đề xuất nâng local schema v2 lên v3 nhưng thêm field khác nhau. Chốt **một metadata schema/migration owner**, bao gồm attachment metadata, labelIds, label catalog và typed outbox/conflicts theo scope được duyệt. Không merge hai codec đều nhận schemaVersion3 nhưng hiểu record khác nhau. Envelope version, wire version và IndexedDB database version là ba thứ riêng.

Xem [Attachment handoff](../../attachments/module_03_teammate_handoff.md) trước khi sửa Note/codec/outbox. Không thêm Label bằng cách thay thế full payload và bỏ Attachment fields chưa được surface này render.

### 3.3. Typed sync cần cả push, pull và dependency ordering

`IRemoteNoteDataSource`, `SyncMutationResult`, `SyncChangesPage`, PendingMutation và reconciliation hiện note-only. File plan phải bổ sung remote port, snapshot/page/result types, sync failures/status projections, composition và Diagnostics smoke/fakes liên quan; đổi mapper một mình không đủ.

Wire v2 phải negotiate/validate cho cả mutations và changes. GET hiện gửi cursor/limit; parser backend chưa nhận version. Nếu một feed trả Label rows cho client v1, client hiện sẽ decode chúng thành Note và fail. Chốt explicit version route/capability/query và legacy-read behavior trước emission. Nếu legacy feed lọc label rows trong cùng global sequence, cursor vẫn phải advance qua contiguous consumed prefix, không mắc kẹt ở row bị lọc hoặc bỏ qua GSI visibility gap.

Giữ legacy attempted mutations theo original wire semantics/ID/fingerprint; không đổi noteId thành entityId hoặc thêm labelIds vào một request đã thử gửi. VNext fingerprint phải gồm entity type/resource identity và payload đầy đủ. labelIds là set: serialize theo canonical sorted order, để attach theo thứ tự khác nhau không tạo fingerprint khác cho cùng membership.

Tất cả stopped/conflicted/ACK identities phải có entityType và resource identity. Note và Label cùng string ID không được block/overwrite nhau. Giữ JWT-sub/token-refresh/account/session guards của HTTP adapter khi mở rộng port.

**Dependency bắt buộc:** server phải ACK Label create trước Note mutation thêm labelId đó. Outbox hiện gửi theo thứ tự queue; một pending Note create cũ có thể được coalesce với labelIds mới và đứng trước Label create. Typed dispatcher cần hoãn dependent Note, push prerequisite Label và tiếp tục unrelated entries; không đổi payload của attempted request để chữa ordering.

Label name collision và label revision conflict phải là typed outcomes khác nhau. Khi hai thiết bị offline tạo cùng tên bằng hai IDs khác nhau, không map server Label B thành ACK của Label A. Đề xuất tối thiểu: block candidate A để user đổi tên; dependent Note mutations chờ resolution. “Use existing label” cần explicit user choice cùng association migration, không auto merge IDs. Account auth failure dừng run; per-entity name/conflict failure không tự chặn mọi unrelated Note sync.

### 3.4. Uniqueness/delete phải có semantics và concurrency tests cụ thể

Canonical Module04 spec không bắt buộc tên label unique. Đây là business constraint thêm trong report; chốt lợi ích/chi phí trước implementation. Nếu giữ, đề xuất unique active normalized name theo owner, preserve display spelling và dấu; cùng một normalization policy ở Dart/TS và bounded length.

Local check giúp UX, không bảo đảm uniqueness giữa thiết bị. Backend cần name-claim conditional transaction cùng Label revision, account sequence, mutation replay record và change feed. [AWS unique-constraint pattern](https://aws.amazon.com/blogs/database/simulating-amazon-dynamodb-unique-constraints-using-transactions/).

Case-only rename có thể có old/new normalized key giống nhau: không dựng hai actions chạm cùng item trong một transaction. Delete/release claim phải conditional trên labelId đang sở hữu claim. Replay delete của ID cũ không được xóa claim đã thuộc ID mới sau khi reuse tên. [TransactWriteItems](https://docs.aws.amazon.com/amazondynamodb/latest/APIReference/API_TransactWriteItems.html).

Deletion nên theo tombstone/effective association model của report, không fan out rewrite mọi Note ngay. Tombstoned ID không hiện chip/filter active, không hồi sinh; tên có thể được dùng lại bởi ID mới. Chốt inactive-reference cleanup/limits riêng; không clear raw labelIds do catalog load/error.

Backend association validation kiểm tra **newly added IDs** active/đúng scope tại commit. Không từ chối mọi text edit chỉ vì Note có unchanged stale IDs của label đã xóa; detach stale ID vẫn được. Attach race với delete phải reject new association hoặc serialize theo current contract. Không biến liveness check thành stale cached decision.

Label rename cập nhật catalog, không cần rewrite label name/updatedAt trong mọi Note. Label delete không đổi text, attachments, owner hay delete Note. Cần cap metadata/association count phù hợp current Dynamo snapshot/replay sizes, tránh tạo một transaction vượt giới hạn khi check nhiều IDs.

### 3.5. Shared/protected query, UI refresh và Summary cần contract rõ

Owner labels trên canonical Note khác organization riêng của recipient. Owned-only baseline là proposal nhỏ nhất; chưa đáp ứng shared behavior đầy đủ. Với shared note, recipient không có toàn bộ owner catalog trong account store hiện tại: chốt authorized label projection chỉ cho labels được phép xem, thay vì tải toàn bộ private owner catalog. Quyền organize/attach có thể owner-only dù editor được sửa text; không suy từ edit permission nếu M06 chưa duyệt.

Keyword/filter/count/snippet chỉ dùng authorized readable projections **trước** khi chạy matching. Không lọc/đếm full plaintext rồi chỉ hide card. Locked/revoked notes, note-associated label chips/counts và shared catalogs phải theo M05/M06 metadata policy. Clear account-bound query/catalog/selection và bỏ late async result khi đổi session; không ghi keyword/name/content/token vào log.

Catalog controller/state cần loading/ready/error distinction và notifications tới mọi chip/filter surface. Rename/delete cập nhật bằng ID resolution; không gọi nguyên NotesWorkspace.reload cho mỗi catalog event vì hàm đó reset selection và dirty state. Reuse editor incoming-snapshot handling giữ dirty text; label refresh không được thay draft bằng persisted content.

SummaryRunGuard đang tự dựng NoteDto từ local state. Thêm labelIds/attachments vào DTO/equality phải sửa tất cả producers của projection này; nếu không, summary của note có metadata mới có thể bị từ chối do snapshot mismatch. Giữ account/session/consent/revision guards. Mặc định conservative invalidation khi Note thay đổi; rename Label không tự gửi tên/ID vào AI hay làm text của Note thay đổi.

## 4. Gate phải chốt

| Gate | Cần quyết định/contract | Tránh giả định |
| --- | --- | --- |
| G1 Query semantics | ALL + keyword/pinned comparator đã chốt; implement/test cold catalog và deleted selection | Helpers đã có trong code; recent overview là full search list |
| G2 Metadata/transaction | Common schema với M03; atomic Note+Label association; same account store | updateById tồn tại; hai migrations v3 tương thích |
| G3 Typed sync | Push/pull versioning, legacy fingerprints/feed/cursor, typed errors and dependency ordering | chỉ thêm entityType vào POST là đủ |
| G4 Catalog invariants | Optional name uniqueness, normalization, tombstone/reuse and collision resolution | registered local name bảo đảm cloud unique; name collision là revision conflict |
| G5 Access/lifecycle | Owned/shared organization, permitted catalog projections, locked query/count behavior and Summary DTO mapping | recipient namespace là owner; metadata có thể đọc không điều kiện |

Query/common-port decisions đã chốt trong common contract. Owned/shared-label behavior, sync migration và server active-name uniqueness tiếp tục là gates riêng, không tự ghi thành decision đã approve.

## 5. Chia implementation thành năm slice

| Slice | Phạm vi | Exit gate |
| --- | --- | --- |
| O0 — Contract + coordination | G1–G5; Note metadata schema chung M02/M03/M11; push/pull examples; legacy policy; catalog conflict and permissions matrix | Reviewable contract và writer ownership; decisions pending được ghi rõ |
| O1 — Domain + pure query | Label lifecycle, immutable labelIds, shared filter/comparator function; atomic-mutation contract groundwork với fakes | Domain/Presentation pure tests pass; created/updated sort và current search không regress |
| O2 — Local catalog + typed engine | Same cached store; atomic label CRUD/association/outbox; coordinated migration; Note/Label dispatch/reconciliation; dependency blocks/conflicts | Offline/reopen, same-ID across types, concurrent text/attachment/label, catalog cold-load và legacy outbox pass |
| O3 — Backend protocol + constraints | Versioned push/pull; Label records/name claims/revision/tombstone; association validation; typed replay/feed/errors | Conditional race/name collision/mixed-version/direct-access tests pass; no cloud deploy chưa authorized |
| O4 — UI + integration | Label admin/controller/panel; chips resolve catalog; attach/detach; query/filter list/grid; safe sync/account refresh | Web + Native CRUD/search/filter/reopen/reconnect; dirty draft preserved; mandatory requirements verified hoặc explicit pending |

Backend compatibility phải được deploy/verify trước client vNext emission. Local/fake groundwork không đồng nghĩa feature complete hoặc cloud integration pass.

## 6. File responsibilities và missing impact list

Tạo file theo responsibility khi slice dùng tới; không scaffold generic registry/framework trước nhu cầu.

| Boundary | Files/responsibility | Hướng giữ đơn giản |
| --- | --- | --- |
| Domain | `lib/domain/labels/{label,label_repository}.dart`; agreed Note/INoteRepository delta | Label model/port nhỏ; names tách khỏi Note; không SDK/cache/filter state |
| Application | Label service + local_label_state/payload/snapshot/conflict/failure; common remote/sync ports/results/pages; separate label reconciliation/resolution | Typed Note/Label branch rõ; giữ Note conflict resolver behavior, không chạy nó cho Label |
| Infrastructure | Label repository qua existing account store; coordinated codecs/schema; typed mapper/HTTP adapter | Không Label database/engine thứ hai; local native/Web store instance vẫn shared |
| Backend | Label payload validation, name-claim rules, Label transaction construction and typed response/read negotiation helpers | `DynamoSyncStore` hiện 711 lines: extract đúng trách nhiệm khi mở rộng, không nhét tất cả Label logic vào class hiện tại; một commit owner cho sequence/replay/feed |
| Presentation/composition/tests | Label controller/state/panel, label picker/chips, common pure note query, Dashboard/Workspace integration, main DI và scoped tests | Same rules/list/grid; no new search service/event bus/state package; keep active dirty editor |

Bổ sung explicit paths vào report: `lib/application/sync/remote_note_data_source.dart`, `sync_snapshot.dart` (gồm page), `sync_failure.dart`, existing sync presentation/status handling, `lib/application/note_intelligence/summary_run_guard.dart`, Diagnostics smoke/fakes và metadata producers. Nếu đổi tên port thành remote sync port, cập nhật caller/tests có chủ đích, không wrapper facade trùng trách nhiệm.

`main.dart` chỉ wire. Nếu LabelRepository cần store, nhận cùng `_localSyncStoreForAccount`, không tự resolve path/IndexedDB trong LabelApplicationService. UI không gọi repository hoặc Domain mutation trực tiếp.

Architecture checkbox “limited to assigned module” cần thay bằng cross-module contract/ownership gate vì sync, Note metadata, Attachment và Summary projection cùng bị tác động.

## 7. Verification cho PR

| Nhóm | Cases bắt buộc |
| --- | --- |
| Query/UI | Title-only/content-only; empty/mixed case/tiếng Việt; ALL/ANY policy; keyword AND labels; updated/created sort; full loaded list beyond overview recent limit; same list/grid; no network per keystroke; cold catalog không clear selection |
| Domain/local | Blank/normalization/duplicate policy; stable ID rename; immutable set; no-op duplicate attach/absent detach; transaction attach/delete race; concurrent text+attachment+label; same store; account/session changes |
| Sync/protocol | Label create ACK trước dependent Note; same ID Note/Label; v1 attempted replay; v2 push/pull; filtered legacy cursor progress; mixed metadata schema; later pending label rename after ACK; name collision distinct from revision conflict; unrelated Note sync continues |
| Backend/catalog | Concurrent claim; case-only rename; lost ACK; delete/reuse name/new ID; old delete replay cannot release new claim; stale unchanged references allow text edit; new tombstoned association reject; no Note cascade delete |
| Cross-platform/access | Web/native offline CRUD/filter/reopen/reconnect; rename chips everywhere without closing draft; locked/revoked projection/count; shared catalog least disclosure; foreign label mutation reject; conservative Summary guard mapping |

Existing tests to preserve: `test/presentation/dashboard/dashboard_page_test.dart`, `dashboard_controller_test.dart`; Application/Infrastructure sync model, coordinator, conflict, codec and mapper suites. Không giả có `dashboard_content_test.dart`; tạo pure query test đúng path khi helper được thêm.

Khi sửa source: format touched Dart files, run `flutter analyze`, focused tests trước `flutter test` theo AGENTS, Chrome tests cho relevant Web flows, backend checks theo `package.json`, và `git diff --check`. Ghi mocks/source, runtime platform và deployed cloud evidence riêng. Planning review hiện chưa chạy các tests đó.

## 8. Prompt khởi động cho Codex của teammate

```text
Read AGENTS.md, docs/contracts/modules_02_03_04_contract.md,
docs/organization/module_04_teammate_handoff.md and the existing Attachment
handoff completely. Implement Module04 incrementally and preserve the
single local-first Note/outbox/cursor engine and DDD dependency direction.

First verify branch/HEAD, dirty files, current source and approved scope. The
reviewed baseline is Final-here-do-not-merge-main@6ce2afe; your checkout may differ.
Use graph tools when available and exact source for missing/stale Dart coverage.

Start with O0: make query/uniqueness/shared-scope decisions and versioned push/pull,
metadata migration, atomic association and dependency/conflict contracts concrete.
Do not assume updateById, NoteQuery, labels, shared ACL/unlock or schema v3 exist.
Confirm the human-approved implementation slice before source changes; keep all
pending defaults explicit.

Coordinate one writer for shared Note/sync codecs/backend. Reuse the cached
account store, current keyword/sort behavior and known guards. Do not create a
second sync database/engine, fake labels as notes, copy label names into Notes,
mutate attempted request identities, clear legacy cache/outbox, or silently merge
two label IDs after a name collision. Ensure prerequisite Label create completes
before dependent Note association pushes and mixed feed types cannot break old
clients. Preserve Attachment metadata and dirty text edits.

Use small files by responsibility and a bounded Note/Label dispatcher. No generic
framework, search dependency, allow-all access guard, deploy, credentials/signing
changes, merge, commit or push without the corresponding authorization. Add
meaningful concurrency, migration, access and UI tests; run required checks and
report unfinished gates separately from completed source/mock work.
```

## 9. Evidence và giới hạn

Current source checked: DashboardContent/Page/Controller, main store composition, Note/application/repository, local sync state/schema/store/ports, snapshot/page/result/pending/coordinator/mapper/HTTP adapter, backend parser/transaction/store/feed/response, Workspace reload/NoteDetail update and SummaryRunGuard.

Graph MCP/coverage tools không có trong phiên. Local index tại e24dd7f không phủ Dart; backend TS graph chỉ là navigation lead đã kiểm tra source. Report được review bằng exact source/bounded first-party searches và canonical Notion04 spec. Không sửa implementation, chạy runtime tests hoặc deploy AWS trong review này.

